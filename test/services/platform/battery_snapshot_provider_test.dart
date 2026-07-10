import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/device_feature_models.dart';
import 'package:mimicam/services/platform/battery_snapshot_provider.dart';

void main() {
  test('TTL icinde platform battery okumasini cache eder', () async {
    var nowMs = 1000;
    final source = _CountingBatteryProvider();
    final cached = CachedBatterySnapshotProvider(
      source,
      ttl: const Duration(seconds: 15),
      nowMs: () => nowMs,
    );

    final first = await cached.snapshot();
    nowMs += 14000;
    final second = await cached.snapshot();
    nowMs += 1000;
    final third = await cached.snapshot();

    expect(first.levelPercent, 99);
    expect(identical(first, second), isTrue);
    expect(third.levelPercent, 98);
    expect(source.calls, 2);
  });

  test('es zamanli talepler tek platform okumasinda birlesir', () async {
    final completer = Completer<BatterySnapshot>();
    final source = _CompletingBatteryProvider(completer.future);
    final cached = CachedBatterySnapshotProvider(source);

    final first = cached.snapshot();
    final second = cached.snapshot();
    completer.complete(
      BatterySnapshot.fromLevel(
        levelPercent: 50,
        state: 'discharging',
        updatedAtMs: 1000,
      ),
    );

    expect(await first, same(await second));
    expect(source.calls, 1);
  });
}

class _CountingBatteryProvider implements BatterySnapshotProvider {
  int calls = 0;

  @override
  Future<BatterySnapshot> snapshot() async {
    calls++;
    return BatterySnapshot.fromLevel(
      levelPercent: 100 - calls,
      state: 'discharging',
      updatedAtMs: calls,
    );
  }
}

class _CompletingBatteryProvider implements BatterySnapshotProvider {
  _CompletingBatteryProvider(this.result);

  final Future<BatterySnapshot> result;
  int calls = 0;

  @override
  Future<BatterySnapshot> snapshot() {
    calls++;
    return result;
  }
}
