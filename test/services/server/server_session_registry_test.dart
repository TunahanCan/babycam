import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/services/server/active_client_registry.dart';
import 'package:miucam/services/server/server_session_controller.dart';
import 'package:miucam/services/server/server_session_registry.dart';

void main() {
  group('ServerSessionRegistry', () {
    test('keeps all runtime state in one session aggregate', () {
      final registry = ServerSessionRegistry();
      final activeClients = _activeClients();
      const demand = (video: true, audio: false);
      const standalone = (video: false, audio: true);

      registry.recordRequest(
        'client-1',
        demand: demand,
        mediaTransport: 'webrtc',
        streamAttemptId: 'attempt-1',
      );
      registry.setStandaloneDemand('client-1', standalone);
      registry.bindWebRtcPeer(
        'client-1',
        peerId: 'peer-1',
        transportLease: activeClients.attachStream('client-1'),
      );
      registry.markRuntimeOwned('client-1', owned: true);

      final session = registry.snapshot('client-1');
      expect(session?.demand, demand);
      expect(session?.mediaTransport, 'webrtc');
      expect(session?.streamAttemptId, 'attempt-1');
      expect(session?.webRtcPeerId, 'peer-1');
      expect(session?.standaloneDemand, standalone);
      expect(registry.ownsRuntime('client-1'), isTrue);
      expect(activeClients.mediaConnectionCount, 1);

      registry.clear();
      expect(activeClients.mediaConnectionCount, 0);
    });

    test('same WebRTC reconnect preserves runtime and exact peer ownership',
        () {
      final activeClients = _activeClients();
      final lease = activeClients.attachStream('client-1');
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'webrtc',
          streamAttemptId: 'attempt-1',
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-1',
          transportLease: lease,
        )
        ..markRuntimeOwned('client-1', owned: true);

      registry.recordRequest(
        'client-1',
        demand: (video: false, audio: true),
        mediaTransport: 'webrtc',
        streamAttemptId: 'attempt-2',
      );

      expect(registry.ownsRuntime('client-1'), isTrue);
      expect(registry.snapshot('client-1')?.streamAttemptId, 'attempt-2');
      expect(registry.snapshot('client-1')?.webRtcPeerId, 'peer-1');
      expect(registry.webRtcPeer('client-1')?.transportLease, same(lease));
      expect(
        registry.requestMatches(
          'client-1',
          demand: (video: false, audio: true),
          mediaTransport: 'webrtc',
        ),
        isTrue,
      );

      registry.clear();
    });

    test('restores the complete snapshot after a failed replacement', () {
      final activeClients = _activeClients();
      final stableLease = activeClients.attachStream('client-1');
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: false),
          mediaTransport: 'webrtc',
          streamAttemptId: 'attempt-stable',
        )
        ..setStandaloneDemand(
          'client-1',
          (video: true, audio: false),
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-stable',
          transportLease: stableLease,
        )
        ..markRuntimeOwned('client-1', owned: true);
      final previous = registry.snapshot('client-1');

      final retired = registry.takeWebRtcPeer(
        'client-1',
        peerId: 'peer-stable',
      );
      final replacementLease = activeClients.attachStream('client-1');
      registry
        ..recordRequest(
          'client-1',
          demand: (video: false, audio: true),
          mediaTransport: 'webrtc',
          streamAttemptId: 'attempt-failed',
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-failed',
          transportLease: replacementLease,
        );
      registry.setStandaloneDemand('client-1', null);
      registry.restore('client-1', previous);

      expect(retired?.transportLease, same(stableLease));
      expect(registry.snapshot('client-1'), same(previous));
      expect(
        registry.snapshot('client-1')?.streamAttemptId,
        'attempt-stable',
      );
      expect(registry.snapshot('client-1')?.webRtcPeerId, 'peer-stable');
      expect(registry.ownsRuntime('client-1'), isTrue);
      expect(
        registry.standaloneDemands,
        contains((video: true, audio: false)),
      );
      expect(replacementLease.isReleased, isTrue);
      expect(stableLease.isReleased, isFalse);
      expect(activeClients.mediaConnectionCount, 1);

      registry.clear();
      expect(activeClients.mediaConnectionCount, 0);
    });

    test('removing a session releases its exact WebRTC transport lease', () {
      final activeClients = _activeClients();
      final lease = activeClients.attachStream('client-1');
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'webrtc',
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-1',
          transportLease: lease,
        )
        ..markRuntimeOwned('client-1', owned: true);

      final removed = registry.remove('client-1');

      expect(removed?.runtimeOwned, isTrue);
      expect(lease.isReleased, isTrue);
      expect(activeClients.mediaConnectionCount, 0);
      expect(registry.snapshot('client-1'), isNull);
    });

    test('stale peer CAS cannot release a successor lease', () {
      final activeClients = _activeClients();
      final oldLease = activeClients.attachStream('client-1');
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'webrtc',
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-old',
          transportLease: oldLease,
        );

      registry.takeWebRtcPeer('client-1', peerId: 'peer-old')!.release();
      final successorLease = activeClients.attachStream('client-1');
      registry.bindWebRtcPeer(
        'client-1',
        peerId: 'peer-current',
        transportLease: successorLease,
      );

      expect(
        registry.takeWebRtcPeer('client-1', peerId: 'peer-old'),
        isNull,
      );
      expect(successorLease.isReleased, isFalse);
      expect(registry.snapshot('client-1')?.webRtcPeerId, 'peer-current');
      expect(activeClients.mediaConnectionCount, 1);

      registry.clear();
      expect(activeClients.mediaConnectionCount, 0);
    });

    test('transport cannot change while a physical WebRTC peer is owned', () {
      final activeClients = _activeClients();
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'webrtc',
        )
        ..bindWebRtcPeer(
          'client-1',
          peerId: 'peer-1',
          transportLease: activeClients.attachStream('client-1'),
        );

      expect(
        () => registry.recordRequest(
          'client-1',
          demand: (video: true, audio: false),
          mediaTransport: 'mjpeg_wav',
        ),
        throwsStateError,
      );

      registry.clear();
    });
  });

  group('ServerSessionController stream attempt tombstones', () {
    test('tombstones are scoped, bounded and evict the oldest entry', () {
      final controller = ServerSessionController(
        activeClients: _activeClients(),
        maxStreamAttemptTombstones: 2,
      );

      controller
        ..cancelStreamAttempt('client-1', 'attempt-1')
        ..cancelStreamAttempt('client-1', 'attempt-2')
        ..cancelStreamAttempt('client-2', 'attempt-3');

      expect(controller.streamAttemptTombstoneCount, 2);
      expect(
        controller.isStreamAttemptCancelled('client-1', 'attempt-1'),
        isFalse,
      );
      expect(
        controller.isStreamAttemptCancelled('client-1', 'attempt-2'),
        isTrue,
      );
      expect(
        controller.isStreamAttemptCancelled('client-2', 'attempt-3'),
        isTrue,
      );
      expect(
        controller.isStreamAttemptCancelled('client-2', 'attempt-2'),
        isFalse,
      );
    });

    test('expired tombstones no longer reject a stream attempt', () {
      var now = DateTime(2026);
      final controller = ServerSessionController(
        activeClients: _activeClients(),
        now: () => now,
        streamAttemptTombstoneTtl: const Duration(seconds: 10),
      );

      controller.cancelStreamAttempt('client-1', 'attempt-1');
      expect(
        controller.isStreamAttemptCancelled('client-1', 'attempt-1'),
        isTrue,
      );

      now = now.add(const Duration(seconds: 10));

      expect(
        controller.isStreamAttemptCancelled('client-1', 'attempt-1'),
        isFalse,
      );
      expect(controller.streamAttemptTombstoneCount, 0);
    });
  });
}

ActiveClientRegistry _activeClients() => ActiveClientRegistry(
      tokenService: PairingTokenService(),
      maxActiveClients: 5,
    );
