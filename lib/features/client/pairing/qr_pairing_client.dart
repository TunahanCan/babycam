import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';
import 'pairing_failure.dart';

class QRPairingClient {
  const QRPairingClient({
    this.timeout = const Duration(seconds: 5),
    Future<String> Function()? clientIdProvider,
    Future<String?> Function()? localServerDeviceIdProvider,
    String? clientName,
  })  : _clientIdProvider = clientIdProvider,
        _localServerDeviceIdProvider = localServerDeviceIdProvider,
        _clientName = clientName ?? 'Ebeveyn Cihazı';

  final Duration timeout;
  final Future<String> Function()? _clientIdProvider;
  final Future<String?> Function()? _localServerDeviceIdProvider;
  final String _clientName;

  Future<PairingSession> pair(PairingPayload payload) async {
    if (payload.isExpired) {
      throw const PairingFailure(PairingFailureCode.payloadExpired);
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final deviceId = await _clientId();
      final localServerDeviceId =
          (await _localServerDeviceIdProvider?.call())?.trim();
      final request = await client.postUrl(
        Uri(
          scheme: payload.httpScheme,
          host: payload.host,
          port: payload.port,
          path: MiuCamProtocolV2.pairConfirm,
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'pairingNonce': payload.pairingNonce,
        'clientName': _clientName,
        'deviceId': deviceId,
        if (localServerDeviceId?.isNotEmpty == true)
          'originServerDeviceId': localServerDeviceId,
      }));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<Object?, Object?>? map;
      if (body.isNotEmpty) {
        try {
          final json = jsonDecode(body);
          if (json is Map) map = Map<Object?, Object?>.from(json);
        } on FormatException {
          if (response.statusCode == HttpStatus.ok) {
            throw const PairingFailure(
              PairingFailureCode.invalidServerResponse,
            );
          }
        }
      }
      if (response.statusCode != HttpStatus.ok) {
        throw PairingFailure(
          _failureCodeFor(
            map?['code']?.toString(),
            response.statusCode,
          ),
          statusCode: response.statusCode,
          serverMessage: map?['message']?.toString(),
        );
      }
      if (map == null) {
        throw const PairingFailure(PairingFailureCode.invalidServerResponse);
      }
      final token =
          (map['trustedClientToken'] ?? map['sessionToken'])?.toString();
      if (token == null || token.isEmpty) {
        throw const PairingFailure(PairingFailureCode.invalidServerResponse);
      }
      return PairingSession(
        payload: payload,
        sessionToken: token,
        clientId: map['clientId']?.toString() ?? deviceId,
        trustedClientTokenExpiresAtMs:
            map['trustedClientTokenExpiresAtMs'] is int
                ? map['trustedClientTokenExpiresAtMs'] as int
                : 0,
        pairedAtMs: DateTime.now().millisecondsSinceEpoch,
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

  PairingFailureCode _failureCodeFor(String? rawCode, int statusCode) =>
      switch (rawCode) {
        'PAIRING_NOT_ACTIVE' => PairingFailureCode.pairingNotActive,
        'PAIRING_NONCE_INVALID_OR_EXPIRED' =>
          PairingFailureCode.nonceInvalidOrExpired,
        'PAIR_CONFIRM_RATE_LIMITED' => PairingFailureCode.rateLimited,
        'SELF_PAIRING_NOT_ALLOWED' => PairingFailureCode.selfPairingNotAllowed,
        'MAX_TRUSTED_CLIENTS_REACHED' =>
          PairingFailureCode.maxTrustedClientsReached,
        'PAIRING_REQUEST_INVALID' => PairingFailureCode.invalidServerResponse,
        _ when statusCode == HttpStatus.unauthorized =>
          PairingFailureCode.nonceInvalidOrExpired,
        _ when statusCode == HttpStatus.tooManyRequests =>
          PairingFailureCode.rateLimited,
        _ when statusCode >= HttpStatus.internalServerError =>
          PairingFailureCode.connectionUnavailable,
        _ => PairingFailureCode.rejected,
      };

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
