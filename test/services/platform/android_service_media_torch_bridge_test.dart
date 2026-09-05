import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/platform/android_service_media_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('miucam/test_service_media_torch');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('torch channel preserves on/off and waits for native result', () async {
    final calls = <MethodCall>[];
    final applied = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.arguments['enabled'] == true ? applied.future : true;
    });
    final bridge =
        MethodChannelAndroidServiceMediaBridge(methodChannel: channel);
    var completed = false;
    final enabling = bridge.setTorchEnabled(true).then((value) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);

    expect(calls.single.method, 'setTorchEnabled');
    expect(calls.single.arguments, {'enabled': true});
    expect(completed, isFalse);
    applied.complete(true);
    expect(await enabling, isTrue);
    expect(await bridge.setTorchEnabled(false), isTrue);
    expect(calls.last.arguments, {'enabled': false});
  });

  test('native missing flash returns false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    final bridge =
        MethodChannelAndroidServiceMediaBridge(methodChannel: channel);

    expect(await bridge.setTorchEnabled(true), isFalse);
  });
}
