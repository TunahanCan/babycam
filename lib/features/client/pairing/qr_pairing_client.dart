import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/babycam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class QRPairingClient {
  Future<PairingSession> pair(PairingPayload payload) async {
    final client = HttpClient();
    try {
      final request = await client.post(payload.host, payload.port, BabyCamProtocolV2.pairConfirm);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'pairingNonce': payload.pairingNonce, 'clientName': 'Ebeveyn Cihazı', 'deviceId': 'client_local'}));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) throw StateError('Pairing failed: ${response.statusCode}');
      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body);
      if (json is! Map || json['sessionToken'] is! String) throw StateError('Invalid pairing response');
      return PairingSession(payload: payload, sessionToken: json['sessionToken'] as String);
    } finally {
      client.close(force: true);
    }
  }
}
