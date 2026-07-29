import 'package:flutter/services.dart';

enum DeviceThermalState {
  unknown,
  nominal,
  fair,
  serious,
  critical;

  static DeviceThermalState fromName(Object? value) =>
      DeviceThermalState.values.firstWhere(
        (state) => state.name == value?.toString().toLowerCase(),
        orElse: () => DeviceThermalState.unknown,
      );
}

class DeviceResourceSnapshot {
  const DeviceResourceSnapshot({
    required this.thermalState,
    required this.lowPowerMode,
    required this.measuredAtMs,
    this.charging,
    this.batteryLevelPercent,
  });

  final DeviceThermalState thermalState;
  final bool lowPowerMode;
  final bool? charging;
  final int? batteryLevelPercent;
  final int measuredAtMs;

  static DeviceResourceSnapshot unknown({int? measuredAtMs}) =>
      DeviceResourceSnapshot(
        thermalState: DeviceThermalState.unknown,
        lowPowerMode: false,
        measuredAtMs: measuredAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  factory DeviceResourceSnapshot.fromMap(
    Map<Object?, Object?> value, {
    int? measuredAtMs,
  }) {
    final level = _intValue(value['batteryLevelPercent']);
    return DeviceResourceSnapshot(
      thermalState: DeviceThermalState.fromName(value['thermalState']),
      lowPowerMode: _boolValue(value['lowPowerMode']),
      charging: _nullableBoolValue(value['charging']),
      batteryLevelPercent: level?.clamp(0, 100),
      measuredAtMs: _intValue(value['measuredAtMs']) ??
          measuredAtMs ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toJson() => {
        'thermalState': thermalState.name,
        'lowPowerMode': lowPowerMode,
        'charging': charging,
        'batteryLevelPercent': batteryLevelPercent,
        'measuredAtMs': measuredAtMs,
      };

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _boolValue(Object? value) => _nullableBoolValue(value) ?? false;

  static bool? _nullableBoolValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }
}

abstract interface class DeviceResourceSnapshotProvider {
  Future<DeviceResourceSnapshot> snapshot();
}

class MethodChannelDeviceResourceSnapshotProvider
    implements DeviceResourceSnapshotProvider {
  const MethodChannelDeviceResourceSnapshotProvider({
    MethodChannel channel = const MethodChannel('miucam/device_resources'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<DeviceResourceSnapshot> snapshot() async {
    final measuredAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'snapshot',
      );
      if (value == null) {
        return DeviceResourceSnapshot.unknown(measuredAtMs: measuredAtMs);
      }
      return DeviceResourceSnapshot.fromMap(
        value,
        measuredAtMs: measuredAtMs,
      );
    } on MissingPluginException {
      return DeviceResourceSnapshot.unknown(measuredAtMs: measuredAtMs);
    } on PlatformException {
      return DeviceResourceSnapshot.unknown(measuredAtMs: measuredAtMs);
    } catch (_) {
      // Pure dart:io integration tests may construct the server without a
      // Flutter ServicesBinding. Resource telemetry is optional there.
      return DeviceResourceSnapshot.unknown(measuredAtMs: measuredAtMs);
    }
  }
}

class CachedDeviceResourceSnapshotProvider
    implements DeviceResourceSnapshotProvider {
  CachedDeviceResourceSnapshotProvider(
    this._source, {
    this.ttl = const Duration(seconds: 10),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DeviceResourceSnapshotProvider _source;
  final Duration ttl;
  final int Function() _nowMs;
  DeviceResourceSnapshot? _cached;
  Future<DeviceResourceSnapshot>? _inFlight;

  @override
  Future<DeviceResourceSnapshot> snapshot() {
    final cached = _cached;
    if (cached != null && _nowMs() - cached.measuredAtMs < ttl.inMilliseconds) {
      return Future.value(cached);
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final operation = _source.snapshot().then((value) {
      _cached = value;
      return value;
    });
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  void invalidate() => _cached = null;
}
