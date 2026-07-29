import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../services/platform/battery_snapshot_provider.dart';
import 'client_stream_health_state.dart';

class NetworkQualityMonitor {
  NetworkQualityMonitor({
    this.pollInterval = const Duration(seconds: 4),
    this.livePollInterval = const Duration(seconds: 1),
    this.qualityReportInterval = const Duration(seconds: 4),
    this.timeout = const Duration(milliseconds: 1200),
    this.healthState,
    BatterySnapshotProvider? batteryProvider,
    HttpClient Function(PairingSession session)? clientFactory,
  })  : _batteryProvider = CachedBatterySnapshotProvider(
          batteryProvider ?? BatteryPlusSnapshotProvider(),
          ttl: const Duration(seconds: 30),
        ),
        _clientFactory = clientFactory;

  final Duration pollInterval;
  final Duration livePollInterval;
  final Duration qualityReportInterval;
  final Duration timeout;
  final ClientStreamHealthState? healthState;
  final BatterySnapshotProvider _batteryProvider;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final _classifier = const NetworkQualityClassifier();

  Stream<NetworkQualityUpdate> watch(PairingSession session) async* {
    var failures = 0;
    final reportSchedule = _QualityReportSchedule();
    late final HttpClient client;
    try {
      client = _createClient(session)..connectionTimeout = timeout;
    } catch (_) {
      yield _offlineUpdate(previousFailures: failures);
      return;
    }
    try {
      while (true) {
        final update = await _measure(
          client,
          session,
          failures,
          reportSchedule,
        );
        failures = update.snapshot.consecutiveFailures;
        yield update;
        await Future<void>.delayed(
          (healthState?.watchActive ?? false) ? livePollInterval : pollInterval,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  NetworkQualityUpdate _offlineUpdate({required int previousFailures}) {
    final failures = previousFailures + 1;
    return NetworkQualityUpdate(
      snapshot: NetworkQualitySnapshot(
        tier: _classifier.classify(consecutiveFailures: failures),
        measuredAtMs: DateTime.now().millisecondsSinceEpoch,
        consecutiveFailures: failures,
      ),
    );
  }

  Future<NetworkQualityUpdate> _measure(
    HttpClient client,
    PairingSession session,
    int previousFailures,
    _QualityReportSchedule reportSchedule,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final status = await _getJson(
        client,
        session,
        MiuCamProtocolV2.status,
      ).timeout(timeout);
      stopwatch.stop();
      final rttMs = stopwatch.elapsedMilliseconds;
      final healthSnapshot = healthState?.snapshot();
      final tier = _worseTier(
        _classifier.classify(rttMs: rttMs),
        healthSnapshot?.healthTier ?? NetworkQualityTier.unknown,
      );
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final fingerprint = _qualityEventFingerprint(healthSnapshot);
      final shouldReport = _shouldSendQualityReport(
        healthSnapshot,
        tier,
        reportSchedule,
        nowMs: nowMs,
        eventFingerprint: fingerprint,
      );
      final report = shouldReport
          ? await _sendQualityReport(
              client,
              session,
              tier,
              rttMs,
              consecutiveFailures: 0,
              healthSnapshot: healthSnapshot,
            ).timeout(timeout)
          : status;
      if (shouldReport) {
        reportSchedule.record(
          nowMs: nowMs,
          tier: tier,
          eventFingerprint: fingerprint,
        );
      }
      return NetworkQualityUpdate(
        snapshot: NetworkQualitySnapshot(
          tier: tier,
          rttMs: rttMs,
          measuredAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
        serverProfile: MediaQualityProfile.fromJson(
              report['mediaProfile'],
            ) ??
            MediaQualityProfile.fromJson(status['mediaProfile']),
      );
    } catch (_) {
      stopwatch.stop();
      final failures = previousFailures + 1;
      final tier = _classifier.classify(consecutiveFailures: failures);
      return NetworkQualityUpdate(
        snapshot: NetworkQualitySnapshot(
          tier: tier,
          measuredAtMs: DateTime.now().millisecondsSinceEpoch,
          consecutiveFailures: failures,
        ),
      );
    }
  }

  Future<Map<String, Object?>> _sendQualityReport(
    HttpClient client,
    PairingSession session,
    NetworkQualityTier tier,
    int rttMs, {
    required int consecutiveFailures,
    ClientQualitySnapshot? healthSnapshot,
  }) async {
    final battery = await _batteryProvider.snapshot();
    final reportBody = Map<String, Object?>.from(
      healthSnapshot?.toQualityReportJson(
            clientId: session.clientId,
            networkTier: tier,
            rttMs: rttMs,
            consecutiveFailures: consecutiveFailures,
          ) ??
          {
            'tier': tier.name,
            'networkTier': tier.name,
            'rttMs': rttMs,
            'consecutiveFailures': consecutiveFailures,
            'clientId': session.clientId,
            'skippedFrames': 0,
            'skippedVideoFrames': 0,
            'skippedAudioChunks': 0,
            'watchActive': false,
            'createdAtMs': DateTime.now().millisecondsSinceEpoch,
          },
    );
    reportBody['battery'] = battery.toJson();
    final request = await client.postUrl(
        ServerEndpointBuilder(session).http(MiuCamProtocolV2.qualityReport));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode(reportBody));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Quality report failed: ${response.statusCode}');
    }
    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body);
    if (json is! Map) throw StateError('Invalid quality report response');
    return Map<String, Object?>.from(json);
  }

  Future<Map<String, Object?>> _getJson(
    HttpClient client,
    PairingSession session,
    String path,
  ) async {
    final request =
        await client.getUrl(ServerEndpointBuilder(session).http(path));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.sessionToken}',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Status failed: ${response.statusCode}');
    }
    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body);
    if (json is! Map) throw StateError('Invalid status response');
    return Map<String, Object?>.from(json);
  }

  HttpClient _createClient(PairingSession session) {
    final factory = _clientFactory;
    if (factory != null) return factory(session);
    return HttpClient();
  }

  bool _shouldSendQualityReport(
    ClientQualitySnapshot? healthSnapshot,
    NetworkQualityTier tier,
    _QualityReportSchedule schedule, {
    required int nowMs,
    required int eventFingerprint,
  }) {
    final eligible = healthState == null ||
        (healthSnapshot?.watchActive ?? false) ||
        _severity(tier) >= _severity(NetworkQualityTier.weak);
    if (!eligible) return false;
    if (schedule.lastSentAtMs == null || schedule.lastTier != tier) return true;
    if (schedule.lastEventFingerprint != eventFingerprint &&
        _severity(tier) >= _severity(NetworkQualityTier.weak)) {
      return true;
    }
    return nowMs - schedule.lastSentAtMs! >=
        qualityReportInterval.inMilliseconds;
  }

  int _qualityEventFingerprint(ClientQualitySnapshot? snapshot) => Object.hash(
        snapshot?.streamTimedOut,
        snapshot?.audioUnderrun,
        snapshot?.skippedVideoFrames,
        snapshot?.skippedAudioChunks,
        snapshot?.wsDisconnectCount,
        snapshot?.reconnectCount,
      );

  NetworkQualityTier _worseTier(
    NetworkQualityTier current,
    NetworkQualityTier next,
  ) =>
      _severity(next) > _severity(current) ? next : current;

  int _severity(NetworkQualityTier tier) => switch (tier) {
        NetworkQualityTier.offline => 5,
        NetworkQualityTier.critical => 4,
        NetworkQualityTier.weak => 3,
        NetworkQualityTier.good => 2,
        NetworkQualityTier.excellent => 1,
        NetworkQualityTier.unknown => 0,
      };
}

class _QualityReportSchedule {
  int? lastSentAtMs;
  NetworkQualityTier? lastTier;
  int? lastEventFingerprint;

  void record({
    required int nowMs,
    required NetworkQualityTier tier,
    required int eventFingerprint,
  }) {
    lastSentAtMs = nowMs;
    lastTier = tier;
    lastEventFingerprint = eventFingerprint;
  }
}
