import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/security/pinned_http_client_factory.dart';

const _fingerprintMismatchMessage =
    'Server güvenlik parmak izi eşleşmedi. QR’ı yenileyip tekrar deneyin.';

class QRPairingClient {
  QRPairingClient({PinnedHttpClientFactory? pinnedHttpClientFactory})
      : _pinnedHttpClientFactory =
            pinnedHttpClientFactory ?? PinnedHttpClientFactory();

  final PinnedHttpClientFactory _pinnedHttpClientFactory;

  Future<PairingSession> pair(PairingPayload payload) async {
    final client = _clientForPayload(payload);
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
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Pairing failed: ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join();
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
    } on HandshakeException catch (_) {
      throw StateError(_fingerprintMismatchMessage);
    } on TlsException catch (_) {
      throw StateError(_fingerprintMismatchMessage);
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _clientForPayload(PairingPayload payload) {
    if (payload.httpScheme != 'https') return HttpClient();
    return _pinnedHttpClientFactory.create(
      expectedFingerprintSha256Hex: payload.certificateFingerprintSha256,
      expectedHost: payload.host,
      expectedPort: payload.port,
    );
  }
}
