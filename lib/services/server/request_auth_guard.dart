import 'dart:io';

import '../../features/server/pairing/pairing_token_service.dart';

class RequestAuthResult {
  const RequestAuthResult({required this.clientId});

  final String clientId;
}

class RequestAuthGuard {
  const RequestAuthGuard({required this.tokenService});

  final PairingTokenService tokenService;

  RequestAuthResult? trusted(HttpRequest request) {
    final token = trustedTokenFrom(request);
    if (token == null) return null;
    final record = tokenService.validateTrustedClientToken(token);
    if (record == null) return null;
    return RequestAuthResult(clientId: record.clientId);
  }

  String? trustedTokenFrom(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    return header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : null;
  }
}
