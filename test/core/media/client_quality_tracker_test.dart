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

  test('audio underrun içeren rapor critical etkisi yapar', () {
    final tracker = ClientQualityTracker(nowMs: () => 1000);

    tracker.updateReport(const ClientQualityReport(
      clientId: 'anne',
      networkTier: NetworkQualityTier.excellent,
      createdAtMs: 1000,
      audioUnderrun: true,
      watchActive: true,
    ));

    expect(
      tracker.effectiveTier(clientIds: const ['anne']),
      NetworkQualityTier.critical,
    );
    expect(tracker.reportFor('anne')?.audioUnderrun, isTrue);
  });

  test('expanded report TTL sonrası expired olur ve remove cleanup yapar', () {
    var nowMs = 1000;
    final tracker = ClientQualityTracker(
      nowMs: () => nowMs,
      reportTtl: const Duration(seconds: 10),
    );

    tracker.updateReport(const ClientQualityReport(
      clientId: 'anne',
      networkTier: NetworkQualityTier.weak,
      createdAtMs: 1000,
      videoFrameGapMs: 2500,
      watchActive: true,
    ));

    expect(tracker.reportCount, 1);
    expect(
        tracker.worstReport(clientIds: const ['anne'])?.videoFrameGapMs, 2500);

    tracker.remove('anne');
    expect(tracker.reportCount, 0);

    tracker.updateReport(const ClientQualityReport(
      clientId: 'baba',
      networkTier: NetworkQualityTier.weak,
      createdAtMs: 1000,
    ));
    nowMs += 11000;

    expect(tracker.reportFor('baba'), isNull);
    expect(tracker.effectiveTier(clientIds: const ['baba']),
        NetworkQualityTier.unknown);
  });

  test('eski payload ve yeni payload güvenli parse edilir', () {
    final oldReport = ClientQualityReport.fromJson(
      {'tier': 'good', 'rttMs': 220},
      clientId: 'anne',
      nowMs: 1000,
    );
    final newReport = ClientQualityReport.fromJson(
      {
        'networkTier': 'excellent',
        'videoFrameGapMs': 5000,
        'wsDisconnectCount': 1,
        'watchActive': true,
      },
      clientId: 'baba',
      nowMs: 2000,
    );

    expect(oldReport.networkTier, NetworkQualityTier.good);
    expect(oldReport.rttMs, 220);
    expect(newReport.effectiveTier, NetworkQualityTier.critical);
    expect(newReport.clientId, 'baba');
  });
}
