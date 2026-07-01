import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class QRPairingClient {
  const QRPairingClient({
    this.timeout = const Duration(seconds: 5),
    Future<String> Function()? clientIdProvider,
    String? clientName,
  })  : _clientIdProvider = clientIdProvider,
        _clientName = clientName ?? 'Ebeveyn Cihazı';

  final Duration timeout;
  final Future<String> Function()? _clientIdProvider;
  final String _clientName;

  Future<PairingSession> pair(PairingPayload payload) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final deviceId = await _clientId();
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
        'clientName': _clientName,
        'deviceId': deviceId,
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
        clientId: json['clientId']?.toString() ?? deviceId,
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

  Future<String> _clientId() async {
    final provider = _clientIdProvider;
    final id = provider == null
        ? 'client_${DateTime.now().microsecondsSinceEpoch}'
        : await provider();
    final normalized = id.trim();
    if (normalized.isNotEmpty) return normalized;
    return 'client_${DateTime.now().microsecondsSinceEpoch}';
  }
}
