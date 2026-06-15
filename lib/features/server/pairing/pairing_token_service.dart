import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/security/secure_random_token_generator.dart';
import '../../../core/security/trusted_client_token.dart';

class TrustedClientRecord {
  const TrustedClientRecord({required this.clientId, required this.clientName, required this.tokenHash, required this.createdAtMs, required this.lastSeenAtMs, required this.expiresAtMs, this.revokedAtMs});
  final String clientId;
  final String clientName;
  final String tokenHash;
  final int createdAtMs;
  final int lastSeenAtMs;
  final int expiresAtMs;
  final int? revokedAtMs;

  TrustedClientRecord copyWith({String? tokenHash, int? lastSeenAtMs, int? expiresAtMs, int? revokedAtMs}) => TrustedClientRecord(
        clientId: clientId,
        clientName: clientName,
        tokenHash: tokenHash ?? this.tokenHash,
        createdAtMs: createdAtMs,
        lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
        expiresAtMs: expiresAtMs ?? this.expiresAtMs,
        revokedAtMs: revokedAtMs ?? this.revokedAtMs,
      );
}

class PairingTokenService {
  PairingTokenService({DateTime Function()? now, Duration nonceTtl = const Duration(minutes: 10), SecureRandomTokenGenerator? tokenGenerator})
      : _now = now ?? DateTime.now,
        _nonceTtl = nonceTtl,
        _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator();

  final DateTime Function() _now;
  final Duration _nonceTtl;
  final SecureRandomTokenGenerator _tokenGenerator;
  final _nonces = <String, int>{};
  final _clients = <String, TrustedClientRecord>{};

  String createPairingNonce() {
    final nonce = _tokenGenerator.generateHex(byteCount: 32);
    _nonces[nonce] = _now().add(_nonceTtl).millisecondsSinceEpoch;
    return nonce;
  }

  bool validateAndConsumeNonce(String nonce) {
    final expiry = _nonces.remove(nonce);
    if (expiry == null) return false;
    return _now().millisecondsSinceEpoch <= expiry;
  }

  TrustedClientToken issueTrustedClientToken({required String clientName, required String deviceId}) {
    final nowMs = _now().millisecondsSinceEpoch;
    final clientId = deviceId.isEmpty ? 'client_${_tokenGenerator.generateHex(byteCount: 8)}' : deviceId;
    final token = _tokenGenerator.generateHex(byteCount: 32);
    final expiresAtMs = nowMs + TrustedClientToken.lifetime.inMilliseconds;
    _clients[clientId] = TrustedClientRecord(
      clientId: clientId,
      clientName: clientName,
      tokenHash: hashToken(token),
      createdAtMs: nowMs,
      lastSeenAtMs: nowMs,
      expiresAtMs: expiresAtMs,
    );
    return TrustedClientToken(clientId: clientId, token: token, expiresAtMs: expiresAtMs);
  }

  String issueSessionToken({required String clientName, required String deviceId}) => issueTrustedClientToken(clientName: clientName, deviceId: deviceId).token;

  TrustedClientToken? renewTrustedClientToken(String token) {
    final record = validateTrustedClientToken(token);
    if (record == null || record.revokedAtMs != null) return null;
    return issueTrustedClientToken(clientName: record.clientName, deviceId: record.clientId);
  }

  TrustedClientRecord? validateTrustedClientToken(String token) {
    final tokenHash = hashToken(token);
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      final record = entry.value;
      if (record.tokenHash == tokenHash && record.revokedAtMs == null && record.expiresAtMs > nowMs) {
        final updated = record.copyWith(lastSeenAtMs: nowMs);
        _clients[entry.key] = updated;
        return updated;
      }
    }
    return null;
  }

  bool validateSessionToken(String token) => validateTrustedClientToken(token) != null;
  String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();
  TrustedClientRecord? recordForClient(String clientId) => _clients[clientId];
  int get pairedClientCount => _clients.values.where((c) => c.revokedAtMs == null).length;

  void revokeSession(String token) {
    final tokenHash = hashToken(token);
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      if (entry.value.tokenHash == tokenHash) _clients[entry.key] = entry.value.copyWith(revokedAtMs: nowMs);
    }
  }

  void revokeClient(String clientId) {
    final record = _clients[clientId];
    if (record != null) _clients[clientId] = record.copyWith(revokedAtMs: _now().millisecondsSinceEpoch);
  }

  void revokeAll() {
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      _clients[entry.key] = entry.value.copyWith(revokedAtMs: nowMs);
    }
  }
}
