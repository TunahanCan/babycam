import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/server/media_frame_policy.dart';

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

    test('minimum aralık güncellenince bütçe resetlenir', () {
      final budget =
          MediaFrameBudget(minInterval: const Duration(milliseconds: 120));

      expect(budget.shouldProcess(1000), isTrue);
      budget.updateMinInterval(const Duration(milliseconds: 250));

      expect(budget.minInterval, const Duration(milliseconds: 250));
      expect(budget.shouldProcess(1010), isTrue);
      expect(budget.shouldProcess(1200), isFalse);
      expect(budget.shouldProcess(1260), isTrue);
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
