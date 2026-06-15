import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/babycam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class QRPairingClient {
  Future<PairingSession> pair(PairingPayload payload) async {
    final client = HttpClient();
    client.badCertificateCallback = (certificate, host, port) {
      // TODO: validate certificate.der SHA-256 against payload.certificateFingerprintSha256
      // once platform-compatible self-signed certificate generation is wired.
      return payload.certificateFingerprintSha256.isNotEmpty;
    };
    try {
      final request = await client.postUrl(
        Uri(
          scheme: 'https',
          host: payload.host,
          port: payload.port,
          path: BabyCamProtocolV2.pairConfirm,
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'pairingNonce': payload.pairingNonce,
        'clientName': 'Ebeveyn Cihazı',
        'deviceId': 'client_local',
      }));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Pairing failed: ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body);
      if (json is! Map) throw StateError('Invalid pairing response');
      final token = (json['trustedClientToken'] ?? json['sessionToken'])?.toString();
      if (token == null) throw StateError('Invalid pairing response');
      return PairingSession(
        payload: payload,
        sessionToken: token,
        clientId: json['clientId']?.toString() ?? 'client_local',
        trustedClientTokenExpiresAtMs: json['trustedClientTokenExpiresAtMs'] is int ? json['trustedClientTokenExpiresAtMs'] as int : 0,
      );
    } finally {
      client.close(force: true);
    }
  }
}
