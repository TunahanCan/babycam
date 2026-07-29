import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/async/serialized_async_executor.dart';
import '../../../core/security/secure_random_token_generator.dart';
import '../../../core/security/trusted_client_token.dart';
import 'trusted_client_repository.dart';

export 'trusted_client_repository.dart'
    show
        InMemoryTrustedClientRepository,
        SharedPreferencesTrustedClientRepository,
        TrustedClientRecord,
        TrustedClientRepository;

class StreamAccessToken {
  const StreamAccessToken({
    required this.clientId,
    required this.token,
    required this.expiresAtMs,
  });

  final String clientId;
  final String token;
  final int expiresAtMs;
}

class StreamTokenRecord {
  const StreamTokenRecord({
    required this.clientId,
    required this.tokenHash,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  final String clientId;
  final String tokenHash;
  final int createdAtMs;
  final int expiresAtMs;
}

class TrustedClientLimitException implements Exception {
  const TrustedClientLimitException();

  static const code = 'MAX_TRUSTED_CLIENTS_REACHED';
  static const userMessage =
      'En fazla 5 cihaz eşleştirilebilir. Önce eski bir cihazı kaldırın.';

  @override
  String toString() => '$code: $userMessage';
}

class TrustedClientPersistenceException implements Exception {
  const TrustedClientPersistenceException(this.cause);

  final Object cause;

  static const code = 'TRUSTED_CLIENT_PERSISTENCE_FAILED';

  @override
  String toString() => '$code: $cause';
}

class PairingTokenService {
  PairingTokenService(
      {DateTime Function()? now,
      Duration nonceTtl = const Duration(minutes: 10),
      Duration streamTokenTtl = const Duration(seconds: 90),
      this.maxActiveNonces = defaultMaxActiveNonces,
      this.pairConfirmRateLimitWindow = const Duration(minutes: 1),
      this.maxPairConfirmAttemptsPerWindow =
          defaultMaxPairConfirmAttemptsPerWindow,
      this.maxTrustedClients = defaultMaxTrustedClients,
      this.lastSeenPersistenceInterval = const Duration(minutes: 1),
      TrustedClientRepository? trustedClientRepository,
      SecureRandomTokenGenerator? tokenGenerator})
      : _now = now ?? DateTime.now,
        _nonceTtl = nonceTtl,
        _streamTokenTtl = streamTokenTtl,
        _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator(),
        _trustedClientRepository =
            trustedClientRepository ?? InMemoryTrustedClientRepository() {
    final nowMs = _now().millisecondsSinceEpoch;
    for (final record in _trustedClientRepository.readAll()) {
      if (record.expiresAtMs > nowMs) _clients[record.clientId] = record;
    }
  }

  static const defaultMaxTrustedClients = 5;
  static const defaultMaxActiveNonces = 64;
  static const defaultMaxPairConfirmAttemptsPerWindow = 12;

  final DateTime Function() _now;
  final Duration _nonceTtl;
  final Duration _streamTokenTtl;
  final int maxActiveNonces;
  final Duration pairConfirmRateLimitWindow;
  final int maxPairConfirmAttemptsPerWindow;
  final int maxTrustedClients;
  final Duration lastSeenPersistenceInterval;
  final SecureRandomTokenGenerator _tokenGenerator;
  final TrustedClientRepository _trustedClientRepository;
  final _nonces = <String, int>{};
  final _pairConfirmAttempts = <String, List<int>>{};
  final _clients = <String, TrustedClientRecord>{};
  final _streamTokens = <String, StreamTokenRecord>{};
  final _pendingRenewalClientIdsByTokenHash = <String, String>{};
  final _trustedClientMutations = SerializedAsyncExecutor(
    closedErrorMessage: 'Trusted-client persistence queue is closed.',
  );
  Future<void> _persistenceQueue = Future<void>.value();
  Object? _lastPersistenceError;

  Object? get lastPersistenceError => _lastPersistenceError;

  String createPairingNonce() {
    pruneExpiredNonces();
    _pruneNonceCapacity();
    final nonce = _tokenGenerator.generateHex(byteCount: 32);
    _nonces[nonce] = _now().add(_nonceTtl).millisecondsSinceEpoch;
    return nonce;
  }

  bool validateAndConsumeNonce(String nonce) {
    pruneExpiredNonces();
    final expiry = _nonces.remove(nonce);
    if (expiry == null) return false;
    return _now().millisecondsSinceEpoch <= expiry;
  }

  void pruneExpiredNonces() {
    final nowMs = _now().millisecondsSinceEpoch;
    _nonces.removeWhere((_, expiresAtMs) => expiresAtMs <= nowMs);
  }

  int get activeNonceCount {
    pruneExpiredNonces();
    return _nonces.length;
  }

  bool consumePairConfirmAttempt(String key) {
    final normalizedKey = key.trim().isEmpty ? 'unknown' : key.trim();
    final nowMs = _now().millisecondsSinceEpoch;
    final windowStart = nowMs - pairConfirmRateLimitWindow.inMilliseconds;
    final attempts = _pairConfirmAttempts.putIfAbsent(
      normalizedKey,
      () => <int>[],
    );
    attempts.removeWhere((attemptAtMs) => attemptAtMs < windowStart);
    if (attempts.length >= maxPairConfirmAttemptsPerWindow) return false;
    attempts.add(nowMs);
    _pairConfirmAttempts.removeWhere((_, values) => values.isEmpty);
    return true;
  }

  TrustedClientToken issueTrustedClientToken(
      {required String clientName, required String deviceId}) {
    final nowMs = _now().millisecondsSinceEpoch;
    final clientId = deviceId.isEmpty
        ? 'client_${_tokenGenerator.generateHex(byteCount: 8)}'
        : deviceId;
    final existing = _clients[clientId];
    final createsNewSlot = existing == null || existing.revokedAtMs != null;
    if (createsNewSlot && pairedClientCount >= maxTrustedClients) {
      throw const TrustedClientLimitException();
    }
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
    _persistTrustedClients();
    return TrustedClientToken(
        clientId: clientId, token: token, expiresAtMs: expiresAtMs);
  }

  Future<TrustedClientToken> issueTrustedClientTokenPersisted({
    required String clientName,
    required String deviceId,
  }) =>
      _trustedClientMutations.run(
        () => _persistTrustedClientMutation(
          () => issueTrustedClientToken(
            clientName: clientName,
            deviceId: deviceId,
          ),
        ),
      );

  String issueSessionToken(
          {required String clientName, required String deviceId}) =>
      issueTrustedClientToken(clientName: clientName, deviceId: deviceId).token;

  TrustedClientToken? renewTrustedClientToken(String token) {
    final record = validateTrustedClientToken(token);
    if (record == null || record.revokedAtMs != null) return null;
    return issueTrustedClientToken(
        clientName: record.clientName, deviceId: record.clientId);
  }

  Future<TrustedClientToken?> renewTrustedClientTokenPersisted(
    String token,
  ) =>
      _trustedClientMutations.run(() async {
        final record = validateTrustedClientToken(token);
        if (record == null || record.revokedAtMs != null) return null;
        final tokenHash = hashToken(token);
        _pendingRenewalClientIdsByTokenHash[tokenHash] = record.clientId;
        try {
          return await _persistTrustedClientMutation(
            () => issueTrustedClientToken(
              clientName: record.clientName,
              deviceId: record.clientId,
            ),
          );
        } finally {
          if (_pendingRenewalClientIdsByTokenHash[tokenHash] ==
              record.clientId) {
            _pendingRenewalClientIdsByTokenHash.remove(tokenHash);
          }
        }
      });

  TrustedClientRecord? validateTrustedClientToken(String token) {
    final tokenHash = hashToken(token);
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      final record = entry.value;
      if (record.tokenHash == tokenHash &&
          record.revokedAtMs == null &&
          record.expiresAtMs > nowMs) {
        if (nowMs - record.lastSeenAtMs >=
            lastSeenPersistenceInterval.inMilliseconds) {
          final updated = record.copyWith(lastSeenAtMs: nowMs);
          _clients[entry.key] = updated;
          _persistTrustedClients();
          return updated;
        }
        return record;
      }
    }
    return null;
  }

  bool validateSessionToken(String token) =>
      validateTrustedClientToken(token) != null;

  StreamAccessToken issueStreamToken({required String clientId}) {
    final nowMs = _now().millisecondsSinceEpoch;
    final token = _tokenGenerator.generateHex(byteCount: 32);
    final tokenHash = hashToken(token);
    final expiresAtMs = nowMs + _streamTokenTtl.inMilliseconds;
    _streamTokens[tokenHash] = StreamTokenRecord(
      clientId: clientId,
      tokenHash: tokenHash,
      createdAtMs: nowMs,
      expiresAtMs: expiresAtMs,
    );
    return StreamAccessToken(
      clientId: clientId,
      token: token,
      expiresAtMs: expiresAtMs,
    );
  }

  StreamTokenRecord? validateStreamToken(String token) {
    final tokenHash = hashToken(token);
    final record = _streamTokens[tokenHash];
    final nowMs = _now().millisecondsSinceEpoch;
    if (record == null || record.expiresAtMs <= nowMs) {
      _streamTokens.remove(tokenHash);
      return null;
    }
    return record;
  }

  Set<String> pruneExpiredStreamTokens() {
    final nowMs = _now().millisecondsSinceEpoch;
    final expiredClientIds = <String>{};
    _streamTokens.removeWhere((_, record) {
      final expired = record.expiresAtMs <= nowMs;
      if (expired) expiredClientIds.add(record.clientId);
      return expired;
    });
    return expiredClientIds;
  }

  bool hasValidStreamTokenForClient(String clientId) {
    pruneExpiredStreamTokens();
    return _streamTokens.values.any((record) => record.clientId == clientId);
  }

  void revokeStreamTokensForClient(String clientId) {
    _streamTokens.removeWhere((_, record) => record.clientId == clientId);
  }

  void revokeStreamToken(String token) {
    _streamTokens.remove(hashToken(token));
  }

  String hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();
  TrustedClientRecord? recordForClient(String clientId) => _clients[clientId];
  List<TrustedClientRecord> get trustedClients {
    final nowMs = _now().millisecondsSinceEpoch;
    final clients = _clients.values
        .where(
          (client) => client.revokedAtMs == null && client.expiresAtMs > nowMs,
        )
        .toList(growable: false)
      ..sort((a, b) => b.lastSeenAtMs.compareTo(a.lastSeenAtMs));
    return List.unmodifiable(clients);
  }

  int get pairedClientCount => _clients.values
      .where(
        (client) =>
            client.revokedAtMs == null &&
            client.expiresAtMs > _now().millisecondsSinceEpoch,
      )
      .length;

  void revokeSession(String token) {
    final tokenHash = hashToken(token);
    final nowMs = _now().millisecondsSinceEpoch;
    String? clientId = _pendingRenewalClientIdsByTokenHash[tokenHash];
    for (final entry in _clients.entries) {
      if (entry.value.tokenHash == tokenHash) {
        clientId = entry.key;
        break;
      }
    }
    if (clientId == null) return;
    final record = _clients[clientId];
    if (record == null) return;
    _clients[clientId] = record.copyWith(revokedAtMs: nowMs);
    revokeStreamTokensForClient(clientId);
    _persistTrustedClients();
  }

  void revokeClient(String clientId) {
    final record = _clients[clientId];
    if (record != null) {
      _clients[clientId] =
          record.copyWith(revokedAtMs: _now().millisecondsSinceEpoch);
      revokeStreamTokensForClient(clientId);
      _persistTrustedClients();
    }
  }

  Future<void> revokeClientPersisted(String clientId) =>
      _trustedClientMutations.run(() async {
        revokeClient(clientId);
        await flushPersistence();
      });

  void revokeAll() {
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      _clients[entry.key] = entry.value.copyWith(revokedAtMs: nowMs);
    }
    _streamTokens.clear();
    _persistTrustedClients();
  }

  Future<void> revokeAllPersisted() => _trustedClientMutations.run(() async {
        revokeAll();
        await flushPersistence();
      });

  void clearEphemeralState() {
    _nonces.clear();
    _pairConfirmAttempts.clear();
    _streamTokens.clear();
    _pendingRenewalClientIdsByTokenHash.clear();
  }

  Future<void> flushPersistence() async {
    await _persistenceQueue;
    final error = _lastPersistenceError;
    if (error != null) throw TrustedClientPersistenceException(error);
  }

  Future<TrustedClientToken> _persistTrustedClientMutation(
    TrustedClientToken Function() mutation,
  ) async {
    final previousClients = Map<String, TrustedClientRecord>.of(_clients);
    final value = mutation();
    final issuedRecord = _clients[value.clientId];
    try {
      await flushPersistence();
      return value;
    } on TrustedClientPersistenceException {
      final previousRecord = previousClients[value.clientId];
      final currentRecord = _clients[value.clientId];
      if (identical(currentRecord, issuedRecord)) {
        if (previousRecord == null) {
          _clients.remove(value.clientId);
        } else {
          _clients[value.clientId] = previousRecord;
        }
      } else if (issuedRecord != null &&
          currentRecord?.tokenHash == issuedRecord.tokenHash &&
          currentRecord?.revokedAtMs != null) {
        // Revocation is monotonic authority. If it raced the failed write,
        // restore the old durable token only in revoked form; never resurrect
        // it by replacing the whole client map with a stale snapshot.
        if (previousRecord == null) {
          _clients.remove(value.clientId);
        } else {
          _clients[value.clientId] = previousRecord.copyWith(
            revokedAtMs: currentRecord!.revokedAtMs,
          );
        }
      }
      // Persist the merged authority best-effort. This snapshot also retains
      // mutations to other clients that may have completed during the failed
      // repository write.
      _persistTrustedClients();
      rethrow;
    }
  }

  void _persistTrustedClients() {
    final snapshot = List<TrustedClientRecord>.of(
      _clients.values,
      growable: false,
    );
    _persistenceQueue = _persistenceQueue
        .catchError((_) {})
        .then((_) => _trustedClientRepository.replaceAll(snapshot))
        .then<void>((_) => _lastPersistenceError = null)
        .catchError((Object error) {
      _lastPersistenceError = error;
    });
    unawaited(_persistenceQueue);
  }

  void _pruneNonceCapacity() {
    if (_nonces.length < maxActiveNonces) return;
    final overflow = _nonces.length - maxActiveNonces + 1;
    if (overflow <= 0) return;
    final oldest = _nonces.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final entry in oldest.take(overflow)) {
      _nonces.remove(entry.key);
    }
  }
}
