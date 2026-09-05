import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/baby_monitor_feature_services.dart';

void main() {
  test('switching from torch to screen glow releases the hardware light',
      () async {
    final controller = NightLightController();
    final torchCommands = <bool>[];
    Future<bool> setTorch(bool enabled) async {
      torchCommands.add(enabled);
      return true;
    }

    await controller.applyCommand(
      {'action': 'on', 'mode': 'torch'},
      torchSetter: setTorch,
    );
    final state = await controller.applyCommand(
      {'action': 'set', 'enabled': true, 'mode': 'screenGlow'},
      torchSetter: setTorch,
    );

    expect(torchCommands, [true, false]);
    expect(state.enabled, isTrue);
    expect(state.mode, 'screenGlow');
    expect(state.lastError, isNull);
  });
}
