import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../core/security/pinned_http_client_factory.dart';

class NetworkQualityMonitor {
  NetworkQualityMonitor({
    this.pollInterval = const Duration(seconds: 4),
    this.timeout = const Duration(seconds: 2),
    HttpClient Function(PairingSession session)? clientFactory,
    PinnedHttpClientFactory? pinnedHttpClientFactory,
  })  : _clientFactory = clientFactory,
        _pinnedHttpClientFactory =
            pinnedHttpClientFactory ?? PinnedHttpClientFactory();

  final Duration pollInterval;
  final Duration timeout;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final PinnedHttpClientFactory _pinnedHttpClientFactory;
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
      final tier = _classifier.classify(rttMs: rttMs);
      final report = await _sendQualityReport(
        client,
        session,
        tier,
        rttMs,
      ).timeout(timeout);
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
    int rttMs,
  ) async {
    final request = await client.postUrl(
        ServerEndpointBuilder(session).http(MimiCamProtocolV2.qualityReport));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode({
      'tier': tier.name,
      'rttMs': rttMs,
      'clientId': session.clientId,
    }));
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
    if (session.httpScheme != 'https') return HttpClient();
    return _pinnedHttpClientFactory.create(
      expectedFingerprintSha256Hex: session.certificateFingerprintSha256,
      expectedHost: session.host,
      expectedPort: session.port,
    );
  }
}
