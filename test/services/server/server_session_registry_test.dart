import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/server_session_registry.dart';

void main() {
  group('ServerSessionRegistry', () {
    test('keeps all runtime state in one session aggregate', () {
      final registry = ServerSessionRegistry();
      const demand = (video: true, audio: false);
      const standalone = (video: false, audio: true);

      registry.recordRequest(
        'client-1',
        demand: demand,
        mediaTransport: 'mjpeg_wav',
      );
      registry.setStandaloneDemand('client-1', standalone);
      registry.markRuntimeOwned('client-1', owned: true);

      final session = registry.snapshot('client-1');
      expect(session?.demand, demand);
      expect(session?.mediaTransport, 'mjpeg_wav');
      expect(session?.standaloneDemand, standalone);
      expect(registry.ownsRuntime('client-1'), isTrue);
    });

    test('recording a reconnect request preserves runtime ownership', () {
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'mjpeg_wav',
        )
        ..markRuntimeOwned('client-1', owned: true);

      registry.recordRequest(
        'client-1',
        demand: (video: false, audio: true),
        mediaTransport: 'webrtc',
      );

      expect(registry.ownsRuntime('client-1'), isTrue);
      expect(
        registry.requestMatches(
          'client-1',
          demand: (video: false, audio: true),
          mediaTransport: 'webrtc',
        ),
        isTrue,
      );
    });

    test('restores the complete snapshot after a failed replacement', () {
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: false),
          mediaTransport: 'mjpeg_wav',
        )
        ..setStandaloneDemand(
          'client-1',
          (video: true, audio: false),
        )
        ..markRuntimeOwned('client-1', owned: true);
      final previous = registry.snapshot('client-1');

      registry.recordRequest(
        'client-1',
        demand: (video: false, audio: true),
        mediaTransport: 'webrtc',
      );
      registry.setStandaloneDemand('client-1', null);
      registry.restore('client-1', previous);

      expect(registry.snapshot('client-1'), same(previous));
      expect(registry.ownsRuntime('client-1'), isTrue);
      expect(
        registry.standaloneDemands,
        contains((video: true, audio: false)),
      );
    });

    test('removing a session returns its runtime ownership', () {
      final registry = ServerSessionRegistry()
        ..recordRequest(
          'client-1',
          demand: (video: true, audio: true),
          mediaTransport: 'mjpeg_wav',
        )
        ..markRuntimeOwned('client-1', owned: true);

      final removed = registry.remove('client-1');

      expect(removed?.runtimeOwned, isTrue);
      expect(registry.snapshot('client-1'), isNull);
    });
  });
}
