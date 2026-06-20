import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'client_stream_health_state.dart';

class NetworkQualityMonitor {
  NetworkQualityMonitor({
    this.pollInterval = const Duration(seconds: 4),
    this.timeout = const Duration(seconds: 2),
    this.healthState,
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final Duration pollInterval;
  final Duration timeout;
  final ClientStreamHealthState? healthState;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final _classifier = const NetworkQualityClassifier();

  Stream<NetworkQualityUpdate> watch(PairingSession session) async* {
    var failures = 0;
    final client = _createClient(session)..connectionTimeout = timeout;
    try {
      while (true) {
        final update = await _measure(client, session, failures);
        failures = update.snapshot.consecutiveFailures;
        yield update;
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<NetworkQualityUpdate> _measure(
      HttpClient client, PairingSession session, int previousFailures) async {
    final stopwatch = Stopwatch()..start();
    try {
      final status = await _getJson(
        client,
        session,
        MimiCamProtocolV2.status,
      ).timeout(timeout);
      stopwatch.stop();
      final rttMs = stopwatch.elapsedMilliseconds;
      final healthSnapshot = healthState?.snapshot();
      final tier = _worseTier(
        _classifier.classify(rttMs: rttMs),
        healthSnapshot?.healthTier ?? NetworkQualityTier.unknown,
      );
      final report = _shouldSendQualityReport(healthSnapshot, tier)
          ? await _sendQualityReport(
              client,
              session,
              tier,
              rttMs,
              consecutiveFailures: 0,
              healthSnapshot: healthSnapshot,
            ).timeout(timeout)
          : status;
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
    final request = await client.postUrl(
        ServerEndpointBuilder(session).http(MimiCamProtocolV2.qualityReport));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode(
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
    ));
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
  ) {
    if (healthState == null) return true;
    if (healthSnapshot?.watchActive ?? false) return true;
    return _severity(tier) >= _severity(NetworkQualityTier.weak);
  }

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
