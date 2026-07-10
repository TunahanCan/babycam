import 'package:battery_plus/battery_plus.dart';

import '../../core/protocol/device_feature_models.dart';

abstract interface class BatterySnapshotProvider {
  Future<BatterySnapshot> snapshot();
}

/// Time-bound cache/decorator for platform battery reads.
///
/// Multiple status and quality requests can arrive together. Coalescing the
/// in-flight read avoids repeated method-channel calls while the TTL keeps the
/// telemetry fresh enough for low-battery decisions.
class CachedBatterySnapshotProvider implements BatterySnapshotProvider {
  CachedBatterySnapshotProvider(
    this._source, {
    this.ttl = const Duration(seconds: 15),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final BatterySnapshotProvider _source;
  final Duration ttl;
  final int Function() _nowMs;

  BatterySnapshot? _cached;
  int? _cachedAtMs;
  Future<BatterySnapshot>? _inFlight;

  @override
  Future<BatterySnapshot> snapshot() {
    final cached = _cached;
    final cachedAtMs = _cachedAtMs;
    if (cached != null &&
        cachedAtMs != null &&
        _nowMs() - cachedAtMs < ttl.inMilliseconds) {
      return Future<BatterySnapshot>.value(cached);
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _source.snapshot().then((value) {
      _cached = value;
      _cachedAtMs = _nowMs();
      return value;
    });
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  void invalidate() {
    _cached = null;
    _cachedAtMs = null;
  }
}

class BatteryPlusSnapshotProvider implements BatterySnapshotProvider {
  BatteryPlusSnapshotProvider({Battery? battery})
      : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<BatterySnapshot> snapshot() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      return BatterySnapshot.fromLevel(
        levelPercent: level,
        state: _stateName(state),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return BatterySnapshot.unknown();
    }
  }

  String _stateName(BatteryState state) => switch (state) {
        BatteryState.charging => 'charging',
        BatteryState.discharging => 'discharging',
        BatteryState.connectedNotCharging => 'connectedNotCharging',
        BatteryState.full => 'full',
        BatteryState.unknown => 'unknown',
      };
}
