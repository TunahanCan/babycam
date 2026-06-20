import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../core/security/pinned_http_client_factory.dart';

class StreamSessionController {
  StreamSessionController({
    HttpClient Function(PairingSession session)? clientFactory,
    PinnedHttpClientFactory? pinnedHttpClientFactory,
  })  : _clientFactory = clientFactory,
        _pinnedHttpClientFactory =
            pinnedHttpClientFactory ?? PinnedHttpClientFactory();

  final HttpClient Function(PairingSession session)? _clientFactory;
  final PinnedHttpClientFactory _pinnedHttpClientFactory;
  bool isActive = false;
  HttpClient? _client;
  String? _clientKey;

  Future<void> start(PairingSession session) async {
    await _post(session, MimiCamProtocolV2.sessionStart);
    isActive = true;
  }

  Future<void> stop(PairingSession session) async {
    try {
      await _post(session, MimiCamProtocolV2.sessionStop);
    } finally {
      isActive = false;
      dispose();
    }
  }

  Future<void> _post(PairingSession session, String path) async {
    final client = _clientForSession(session);
    final request =
        await client.postUrl(ServerEndpointBuilder(session).http(path));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode({'clientId': session.clientId}));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('$path failed: ${response.statusCode}');
    }
    await response.drain<void>();
  }

  HttpClient _clientForSession(PairingSession session) {
    final key = '${session.httpScheme}://${session.host}:${session.port}'
        '#${session.certificateFingerprintSha256}';
    if (_client != null && _clientKey == key) return _client!;
    _client?.close(force: true);
    _clientKey = key;
    final factory = _clientFactory;
    if (factory != null) {
      _client = factory(session);
    } else if (session.httpScheme == 'https') {
      _client = _pinnedHttpClientFactory.create(
        expectedFingerprintSha256Hex: session.certificateFingerprintSha256,
        expectedHost: session.host,
        expectedPort: session.port,
      );
    } else {
      _client = HttpClient();
    }
    return _client!;
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
    _clientKey = null;
  }
}
