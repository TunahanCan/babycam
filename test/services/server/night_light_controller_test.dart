import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/baby_monitor_feature_services.dart';

void main() {
  test('a later off command wins over an unfinished torch enable', () async {
    final controller = NightLightController();
    final enableStarted = Completer<void>();
    final finishEnable = Completer<void>();
    var hardwareEnabled = false;
    final torchCommands = <bool>[];
    Future<bool> setTorch(bool enabled) async {
      torchCommands.add(enabled);
      if (enabled) {
        enableStarted.complete();
        await finishEnable.future;
      }
      hardwareEnabled = enabled;
      return true;
    }

    final enable = controller.applyCommand(
      {'action': 'on', 'mode': 'torch'},
      torchSetter: setTorch,
    );
    await enableStarted.future;
    final disable = controller.applyCommand(
      {'action': 'off'},
      torchSetter: setTorch,
    );
    await Future<void>.delayed(Duration.zero);
    finishEnable.complete();
    await Future.wait([enable, disable]);

    expect(controller.state.enabled, isFalse);
    expect(controller.state.mode, 'off');
    expect(hardwareEnabled, isFalse);
    expect(torchCommands, [true, false]);
  });

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
