import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';

class NetworkQualityMonitor {
  NetworkQualityMonitor({
    this.pollInterval = const Duration(seconds: 4),
    this.timeout = const Duration(seconds: 2),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Duration pollInterval;
  final Duration timeout;
  final HttpClient Function() _clientFactory;
  final _classifier = const NetworkQualityClassifier();

  Stream<NetworkQualityUpdate> watch(PairingSession session) async* {
    var failures = 0;
    while (true) {
      final update = await _measure(session, failures);
      failures = update.snapshot.consecutiveFailures;
      yield update;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<NetworkQualityUpdate> _measure(
      PairingSession session, int previousFailures) async {
    final stopwatch = Stopwatch()..start();
    final client = _clientFactory()..connectionTimeout = timeout;
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
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _sendQualityReport(
    HttpClient client,
    PairingSession session,
    NetworkQualityTier tier,
    int rttMs,
  ) async {
    final request =
        await client.postUrl(_uri(session, MimiCamProtocolV2.qualityReport));
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
    final request = await client.getUrl(_uri(session, path));
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

  Uri _uri(PairingSession session, String path) => Uri(
        scheme: session.payload.capabilities['transport'] == 'https'
            ? 'https'
            : 'http',
        host: session.payload.host,
        port: session.payload.port,
        path: path,
      );
}
