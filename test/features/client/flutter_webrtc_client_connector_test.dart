import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/webrtc/flutter_webrtc_client_connector.dart';
import 'package:miucam/features/client/media/webrtc/webrtc_client_connector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final resource in ['peer', 'renderer']) {
    test('late native $resource creation is cleaned after negotiation timeout',
        () async {
      const methods = MethodChannel('FlutterWebRTC.Method');
      const peerEvents =
          MethodChannel('FlutterWebRTC/peerConnectionEventlate-peer');
      const textureEvents = MethodChannel('FlutterWebRTC/Texture7');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final release = Completer<Map<String, Object?>>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getRtpReceiverCapabilities':
            final kind = (call.arguments as Map)['kind'];
            return {
              'codecs': [
                {
                  'mimeType': kind == 'video' ? 'video/H264' : 'audio/opus',
                  'clockRate': kind == 'video' ? 90000 : 48000
                }
              ],
              'headerExtensions': [],
              'fecMechanisms': [],
            };
          case 'createPeerConnection':
            return resource == 'peer'
                ? release.future
                : {'peerConnectionId': 'late-peer'};
          case 'createVideoRenderer':
            return release.future;
          default:
            return null;
        }
      });
      messenger.setMockMethodCallHandler(peerEvents, (_) async => null);
      messenger.setMockMethodCallHandler(textureEvents, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(methods, null);
        messenger.setMockMethodCallHandler(peerEvents, null);
        messenger.setMockMethodCallHandler(textureEvents, null);
      });
      final connector = FlutterWebRtcClientConnector(
        negotiationTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(connector.dispose);
      final connecting = connector.connect(
        session: _session,
        streamToken: 'room-stream',
        video: true,
        audio: true,
      );
      final failure = connecting.then<Object?>((_) => null,
          onError: (Object error) => error);
      final error = await failure.timeout(const Duration(seconds: 1));
      final disposing = connector.dispose();
      expect(connector.dispose(), same(disposing));
      var disposed = false;
      unawaited(disposing.then((_) => disposed = true));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(disposed, isFalse,
          reason: 'Role handoff must wait for the pending native $resource.');
      release.complete(resource == 'peer'
          ? {'peerConnectionId': 'late-peer'}
          : {'textureId': 7});
      await disposing.timeout(const Duration(seconds: 1));
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while ((!calls.contains('peerConnectionDispose') ||
              (resource == 'renderer' &&
                  !calls.contains('videoRendererDispose'))) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(error, isA<WebRtcNegotiationException>());
      expect(calls,
          containsAllInOrder(['peerConnectionClose', 'peerConnectionDispose']));
      if (resource == 'renderer') {
        expect(calls, contains('videoRendererDispose'));
      }
    });
  }

  test('failed native peer disposal blocks connector handoff', () async {
    const methods = MethodChannel('FlutterWebRTC.Method');
    const peerEvents =
        MethodChannel('FlutterWebRTC/peerConnectionEventlate-peer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final release = Completer<Map<String, Object?>>();
    final disposeFailure = PlatformException(code: 'peer_still_active');
    final calls = <String>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getRtpReceiverCapabilities':
          final kind = (call.arguments as Map)['kind'];
          return {
            'codecs': [
              {
                'mimeType': kind == 'video' ? 'video/H264' : 'audio/opus',
                'clockRate': kind == 'video' ? 90000 : 48000,
              },
            ],
            'headerExtensions': [],
            'fecMechanisms': [],
          };
        case 'createPeerConnection':
          return release.future;
        case 'peerConnectionDispose':
          throw disposeFailure;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(peerEvents, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(peerEvents, null);
    });
    final connector = FlutterWebRtcClientConnector(
      negotiationTimeout: const Duration(milliseconds: 40),
    );
    await expectLater(
      connector.connect(
        session: _session,
        streamToken: 'stream',
        video: true,
        audio: true,
      ),
      throwsA(isA<WebRtcNegotiationException>()),
    );
    final disposing = connector.dispose();
    final rejected = expectLater(disposing, throwsA(isNotNull));
    release.complete({'peerConnectionId': 'late-peer'});
    await rejected;

    expect(calls, contains('peerConnectionDispose'));
    expect(connector.dispose(), same(disposing));
    await expectLater(connector.dispose(), throwsA(isNotNull));
    expect(connector.isAvailable, isFalse);
  });
}

const _session = PairingSession(
  payload: PairingPayload(
    schemaVersion: 2,
    host: '127.0.0.1',
    port: 8080,
    deviceId: 'room',
    deviceName: 'Room',
    pairingNonce: 'nonce',
    expiresAtMs: 0,
    capabilities: {'transport': 'http_ws'},
  ),
  sessionToken: 'room-trusted',
);
