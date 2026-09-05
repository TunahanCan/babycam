import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/services/server/media_frame_policy.dart';

void main() {
  group('MediaFrameBudget', () {
    test('kamera frame işlemesini minimum aralıkla sınırlar', () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 120));

      expect(budget.shouldProcess(1000), isTrue);
      expect(budget.shouldProcess(1050), isFalse);
      expect(budget.shouldProcess(1119), isFalse);
      expect(budget.shouldProcess(1120), isTrue);
      expect(budget.shouldProcess(1240), isTrue);
    });

    test('reset sonrası ilk frame hemen işlenebilir', () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 120));

      expect(budget.shouldProcess(1000), isTrue);
      expect(budget.shouldProcess(1010), isFalse);
      budget.reset();

      expect(budget.shouldProcess(1011), isTrue);
    });

    test('profile updates preserve pacing across the last accepted frame', () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 120));

      expect(budget.shouldProcess(1000), isTrue);
      budget.updateMinInterval(const Duration(milliseconds: 250));

      expect(budget.minInterval, const Duration(milliseconds: 250));
      expect(budget.shouldProcess(1010), isFalse);
      expect(budget.shouldProcess(1200), isFalse);
      expect(budget.shouldProcess(1250), isTrue);
    });

    test('wall clock rollback does not freeze video until old time catches up',
        () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 120));

      expect(budget.shouldProcess(60000), isTrue);
      expect(budget.shouldProcess(1000), isTrue);
      expect(budget.shouldProcess(1119), isFalse);
      expect(budget.shouldProcess(1120), isTrue);
    });

    test('rapid content profile oscillation cannot bypass the FPS cap', () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 125));
      final acceptedAt = <int>[];
      for (var frame = 0; frame < 30; frame++) {
        final timestamp = frame * 33;
        budget.updateMinInterval(
            Duration(milliseconds: frame.isEven ? 125 : 167));
        if (budget.shouldProcess(timestamp)) acceptedAt.add(timestamp);
      }

      expect(acceptedAt.length, lessThanOrEqualTo(8));
      for (var i = 1; i < acceptedAt.length; i++) {
        expect(acceptedAt[i] - acceptedAt[i - 1], greaterThanOrEqualTo(125));
      }
    });
  });

  group('MediaEncodingPolicy', () {
    test('izleyen yokken ve legacy kapalıyken JPEG encode etmez', () {
      expect(
        const MediaEncodingPolicy().shouldEncodeJpeg(
          hasMjpegClients: false,
          legacyWebSocketEnabled: false,
        ),
        isFalse,
      );
    });

    test('MJPEG client veya legacy websocket varken JPEG encode eder', () {
      const policy = MediaEncodingPolicy();

      expect(
        policy.shouldEncodeJpeg(
          hasMjpegClients: true,
          legacyWebSocketEnabled: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldEncodeJpeg(
          hasMjpegClients: false,
          legacyWebSocketEnabled: true,
        ),
        isTrue,
      );
    });
  });

  group('FrameBudgetManager', () {
    test('motion/cry/network/client yüküne göre FPS seçer', () {
      const manager = FrameBudgetManager();

      expect(
        manager.targetFps(
          motionEnergy: 0.01,
          cryActive: false,
          networkTier: NetworkQualityTier.good,
          activeClients: 1,
        ),
        12,
      );
      expect(
        manager.targetFps(
          motionEnergy: 0.08,
          cryActive: false,
          networkTier: NetworkQualityTier.good,
          activeClients: 1,
        ),
        12,
      );
      expect(
        manager.targetFps(
          motionEnergy: 0.01,
          cryActive: false,
          networkTier: NetworkQualityTier.weak,
          activeClients: 1,
        ),
        6,
      );
      expect(
        manager.targetFps(
          motionEnergy: 0.08,
          cryActive: false,
          networkTier: NetworkQualityTier.weak,
          activeClients: 1,
        ),
        8,
      );
      expect(
        manager.targetFps(
          motionEnergy: 0.08,
          cryActive: true,
          networkTier: NetworkQualityTier.good,
          activeClients: 5,
        ),
        5,
      );
    });
  });
}
