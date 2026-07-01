import 'package:battery_plus/battery_plus.dart';

import '../../core/protocol/device_feature_models.dart';

abstract interface class BatterySnapshotProvider {
  Future<BatterySnapshot> snapshot();
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
