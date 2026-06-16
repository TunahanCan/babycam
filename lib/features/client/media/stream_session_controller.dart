import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';

class StreamSessionController {
  StreamSessionController({HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  bool isActive = false;

  Future<void> start(PairingSession session) async {
    await _post(session, MimiCamProtocolV2.sessionStart);
    isActive = true;
  }

  Future<void> stop(PairingSession session) async {
    try {
      await _post(session, MimiCamProtocolV2.sessionStop);
    } finally {
      isActive = false;
    }
  }

  Future<void> _post(PairingSession session, String path) async {
    final client = _clientFactory();
    try {
      final request = await client.postUrl(_uri(session, path));
      request.headers
        ..contentType = ContentType.json
        ..set(
            HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
      request.write(jsonEncode({'clientId': session.clientId}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('$path failed: ${response.statusCode}');
      }
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
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
