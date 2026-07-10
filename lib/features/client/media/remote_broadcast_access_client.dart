import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../services/monetization/broadcast_access_service.dart';

/// Reads the room server's authoritative trial/entitlement state before a
/// client-side deadline is allowed to stop a live stream.
class RemoteBroadcastAccessClient {
  RemoteBroadcastAccessClient({
    this.timeout = const Duration(milliseconds: 1200),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Duration timeout;
  final HttpClient Function() _clientFactory;

  Future<BroadcastAccessSnapshot?> snapshot(PairingSession session) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(
            ServerEndpointBuilder(session).http(MimiCamProtocolV2.status),
          )
          .timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Broadcast access status failed: ${response.statusCode}',
          uri: request.uri,
        );
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Invalid room status response.');
      }
      final access = decoded['broadcastAccess'];
      if (access is! Map) return null;
      return BroadcastAccessSnapshot.fromJson(
        Map<Object?, Object?>.from(access),
      );
    } finally {
      client.close(force: true);
    }
  }
}
