import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/webrtc/flutter_webrtc_server_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('FlutterWebRTC.Method');
  const events = MethodChannel('FlutterWebRTC/peerConnectionEventprobe-peer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test('failed native peer disposal cannot report a completed role handoff',
      () async {
    var failDispose = true;
    var disposals = 0;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      switch (call.method) {
        case 'getRtpSenderCapabilities':
          return _capabilities((call.arguments as Map)['kind']);
        case 'createPeerConnection':
          return {'peerConnectionId': 'probe-peer'};
        case 'peerConnectionDispose':
          disposals++;
          if (failDispose) throw PlatformException(code: 'native_owned');
          return null;
        default:
          return null;
      }
    });
    final gateway = FlutterWebRtcServerGateway();
    // The incomplete native probe is deliberately unavailable; even rejected
    // probes can own a native connection that the role must release.
    expect(await gateway.initialize(), isFalse);
    await expectLater(gateway.dispose(), throwsStateError);
    final failedDisposals = disposals;
    failDispose = false;
    await gateway.dispose();
    expect(disposals, greaterThan(failedDisposals));
  });

  test('late native peer acquisition blocks handoff until its cleanup finishes',
      () async {
    final create = Completer<Map<String, Object?>>();
    var disposed = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      switch (call.method) {
        case 'getRtpSenderCapabilities':
          return _capabilities((call.arguments as Map)['kind']);
        case 'createPeerConnection':
          return create.future;
        case 'peerConnectionDispose':
          disposed = true;
          return null;
        default:
          return null;
      }
    });
    final gateway = FlutterWebRtcServerGateway(
      nativeOperationTimeout: const Duration(milliseconds: 30),
      cleanupTimeout: const Duration(milliseconds: 30),
    );
    expect(await gateway.initialize(), isFalse);
    await expectLater(gateway.dispose(), throwsA(isA<TimeoutException>()));
    expect(disposed, isFalse);

    create.complete({'peerConnectionId': 'probe-peer'});
    await pumpEventQueue();
    await gateway.dispose();
    expect(disposed, isTrue);
  });
}

Map<String, Object> _capabilities(Object? kind) => {
      'codecs': [
        {
          'mimeType': kind == 'video' ? 'video/H264' : 'audio/opus',
          'clockRate': kind == 'video' ? 90000 : 48000,
        }
      ],
      'headerExtensions': [],
      'fecMechanisms': [],
    };
