import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/alerts/client_alert_background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android alert foreground demand start ve stop ile iletilir', () async {
    const channel = MethodChannel('mimicam/alert_background_service_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    const service = ClientAlertBackgroundService(channel: channel);

    await service.start();
    await service.stop();

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setAlertDemand');
    expect(calls[0].arguments, {'active': true});
    expect(calls[1].method, 'setAlertDemand');
    expect(calls[1].arguments, {'active': false});
  });

  test('native servis baslatma hatasi basari gibi yutulmaz', () async {
    const channel = MethodChannel('mimicam/alert_background_failure_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'foreground_service_start_failed');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await expectLater(
      const ClientAlertBackgroundService(channel: channel).start(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'foreground_service_start_failed',
        ),
      ),
    );
  });
}
