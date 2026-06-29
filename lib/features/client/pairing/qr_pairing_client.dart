import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class QRPairingClient {
  const QRPairingClient({
    this.timeout = const Duration(seconds: 5),
  });

  final Duration timeout;

  Future<PairingSession> pair(PairingPayload payload) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(
        Uri(
          scheme: payload.httpScheme,
          host: payload.host,
          port: payload.port,
          path: MimiCamProtocolV2.pairConfirm,
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'pairingNonce': payload.pairingNonce,
        'clientName': 'Ebeveyn Cihazı',
        'deviceId': 'client_local',
      }));
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Pairing failed: ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final json = jsonDecode(body);
      if (json is! Map) throw StateError('Invalid pairing response');
      final token =
          (json['trustedClientToken'] ?? json['sessionToken'])?.toString();
      if (token == null) throw StateError('Invalid pairing response');
      return PairingSession(
        payload: payload,
        sessionToken: token,
        clientId: json['clientId']?.toString() ?? 'client_local',
        trustedClientTokenExpiresAtMs:
            json['trustedClientTokenExpiresAtMs'] is int
                ? json['trustedClientTokenExpiresAtMs'] as int
                : 0,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } finally {
      client.close(force: true);
    }
  }
}
