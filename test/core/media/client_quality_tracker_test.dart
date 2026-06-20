import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/media/client_quality_tracker.dart';

void main() {
  test('aktif clientlar arasındaki en zayıf kalite tierini seçer', () {
    var nowMs = 1000;
    final tracker = ClientQualityTracker(
      nowMs: () => nowMs,
      reportTtl: const Duration(seconds: 10),
    );

    tracker
      ..update(clientId: 'anne', tier: NetworkQualityTier.excellent, rttMs: 80)
      ..update(clientId: 'baba', tier: NetworkQualityTier.weak, rttMs: 520)
      ..update(clientId: 'tablet', tier: NetworkQualityTier.good, rttMs: 260);

    expect(
      tracker.effectiveTier(clientIds: const ['anne', 'baba', 'tablet']),
      NetworkQualityTier.weak,
    );
    expect(
      tracker.effectiveTier(clientIds: const ['anne', 'tablet']),
      NetworkQualityTier.good,
    );

    nowMs += 11000;
    expect(
      tracker.effectiveTier(clientIds: const ['anne', 'baba', 'tablet']),
      NetworkQualityTier.unknown,
    );
  });

  test('aktif olmayan client raporu canlı kaliteyi düşürmez', () {
    final tracker = ClientQualityTracker(nowMs: () => 1000);

    tracker
      ..update(clientId: 'watching', tier: NetworkQualityTier.excellent)
      ..update(clientId: 'idle', tier: NetworkQualityTier.critical);

    expect(
      tracker.effectiveTier(clientIds: const ['watching']),
      NetworkQualityTier.excellent,
    );
    expect(tracker.effectiveTier(), NetworkQualityTier.critical);
  });
}
