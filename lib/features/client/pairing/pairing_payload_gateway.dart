import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import 'pairing_failure.dart';

abstract interface class PairingPayloadGateway {
  Future<PairingPayload> fetch({required String host, required int port});
}

/// Adapts the server's public LAN status response into a pairing payload.
class HttpPairingPayloadGateway implements PairingPayloadGateway {
  const HttpPairingPayloadGateway({
    this.timeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now;

  final Duration timeout;
  final DateTime Function()? _now;

  @override
  Future<PairingPayload> fetch(
      {required String host, required int port}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(
            Uri(
              scheme: 'http',
              host: host,
              port: port,
              path: MiuCamProtocolV2.statusPublic,
            ),
          )
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw PairingFailure(
          PairingFailureCode.connectionUnavailable,
          statusCode: response.statusCode,
        );
      }
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const PairingFailure(PairingFailureCode.invalidServerResponse);
      }
      final json = Map<Object?, Object?>.from(decoded);
      final nonce = json['pairingNonce']?.toString().trim();
      if (nonce == null || nonce.isEmpty) {
        throw const PairingFailure(PairingFailureCode.invalidServerResponse);
      }
      final capabilities = json['capabilities'] is Map
          ? Map<String, Object?>.from(json['capabilities'] as Map)
          : <String, Object?>{
              'video': 'mjpeg',
              'audio': 'pcm16le',
              'events': 'json',
              'maxClients': 5,
            };
      return PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: host,
        port: port,
        deviceId: json['serverDeviceId']?.toString() ?? 'manual_server',
        deviceName: json['serverName']?.toString() ?? 'Manual IP Server',
        pairingNonce: nonce,
        expiresAtMs: (_now ?? DateTime.now)()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        transport: json['transport']?.toString() ?? 'http_ws',
        capabilities: capabilities,
      );
    } on PairingFailure {
      rethrow;
    } on TimeoutException {
      throw const PairingFailure(PairingFailureCode.connectionUnavailable);
    } on SocketException {
      throw const PairingFailure(PairingFailureCode.connectionUnavailable);
    } on HttpException {
      throw const PairingFailure(PairingFailureCode.connectionUnavailable);
    } on FormatException {
      throw const PairingFailure(PairingFailureCode.invalidServerResponse);
    } finally {
      client.close(force: true);
    }
  }
}
