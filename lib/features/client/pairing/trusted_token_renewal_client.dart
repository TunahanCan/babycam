import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';

class TrustedTokenRenewalClient {
  TrustedTokenRenewalClient({
    this.timeout = const Duration(seconds: 5),
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final Duration timeout;
  final HttpClient Function(PairingSession session)? _clientFactory;

  Future<PairingSession?> renew(PairingSession session) async {
    final client = _createClient(session);
    try {
      final request = await client.postUrl(
        ServerEndpointBuilder(session).http(MimiCamProtocolV2.authRenew),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.unauthorized) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Token renew failed: ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final json = jsonDecode(body);
      if (json is! Map) throw StateError('Invalid renew response');
      final token = json['trustedClientToken']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('Invalid renew response');
      }
      return session.copyWith(
        sessionToken: token,
        clientId: json['clientId']?.toString() ?? session.clientId,
        trustedClientTokenExpiresAtMs: json['expiresAtMs'] is int
            ? json['expiresAtMs'] as int
            : session.trustedClientTokenExpiresAtMs,
      );
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _createClient(PairingSession session) {
    final factory = _clientFactory;
    if (factory != null) return factory(session);
    return HttpClient()..connectionTimeout = timeout;
  }
}
