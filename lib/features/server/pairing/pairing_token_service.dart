import 'dart:async';
import 'dart:convert';

import 'package:characters/characters.dart';
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
      this.maxPairConfirmSources = 256,
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
  final int maxPairConfirmSources;
  final int maxTrustedClients;
  final Duration lastSeenPersistenceInterval;
  final SecureRandomTokenGenerator _tokenGenerator;
  final TrustedClientRepository _trustedClientRepository;
  final _nonces = <String, int>{};
  String? _publicPairingNonce;
  int? _publicPairingNonceExpiresAtMs;
  int _pairingGeneration = 0;
  final _pairConfirmAttempts = <String, List<int>>{};
  final _clients = <String, TrustedClientRecord>{};
  final _streamTokens = <String, StreamTokenRecord>{};
  final _pendingRenewalClientIdsByTokenHash = <String, String>{};
  final _pendingRevocationClientIds = <String>{};
  final _trustedClientsChanged = StreamController<void>.broadcast();
  final _trustedClientMutations = SerializedAsyncExecutor(
    closedErrorMessage: 'Trusted-client persistence queue is closed.',
  );
  Future<void> _persistenceQueue = Future<void>.value();
  Object? _lastPersistenceError;

  Object? get lastPersistenceError => _lastPersistenceError;
  int get pairingGeneration => _pairingGeneration;
  Stream<void> get trustedClientsChanged => _trustedClientsChanged.stream;
  Set<String> get pendingRevocationClientIds =>
      Set.unmodifiable(_pendingRevocationClientIds);

  String createPairingNonce() {
    pruneExpiredNonces();
    _pruneNonceCapacity();
    final nonce = _tokenGenerator.generateHex(byteCount: 32);
    _nonces[nonce] = _now().add(_nonceTtl).millisecondsSinceEpoch;
    return nonce;
  }

  /// Public discovery retries share one slot so an unauthenticated status
  /// poll cannot evict the QR currently displayed on the room phone.
  String createPublicPairingNonce() {
    final nonce = _publicPairingNonce;
    if (nonce != null && isPairingNonceActive(nonce)) return nonce;
    _publicPairingNonceExpiresAtMs =
        _now().add(_nonceTtl).millisecondsSinceEpoch;
    return _publicPairingNonce = _tokenGenerator.generateHex(byteCount: 32);
  }

  bool validateAndConsumeNonce(String nonce) {
    pruneExpiredNonces();
    final isPublic = nonce == _publicPairingNonce;
    final expiry =
        isPublic ? _publicPairingNonceExpiresAtMs : _nonces.remove(nonce);
    if (isPublic) {
      _publicPairingNonce = null;
      _publicPairingNonceExpiresAtMs = null;
    }
    if (expiry == null) return false;
    _notifyTrustedClientsChanged();
    return _now().millisecondsSinceEpoch < expiry;
  }

  bool isPairingNonceActive(String nonce) {
    final expiry = nonce == _publicPairingNonce
        ? _publicPairingNonceExpiresAtMs
        : _nonces[nonce];
    return expiry != null && _now().millisecondsSinceEpoch < expiry;
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
    // Prune all sources, not just the current address. IPv6 privacy addresses
    // otherwise leave every old rate-limit bucket in memory indefinitely.
    _pairConfirmAttempts.removeWhere((_, attempts) {
      attempts.removeWhere((attemptAtMs) => attemptAtMs <= windowStart);
      return attempts.isEmpty;
    });
    if (!_pairConfirmAttempts.containsKey(normalizedKey) &&
        _pairConfirmAttempts.length >= maxPairConfirmSources) {
      // Keep existing throttles; evicting a live bucket lets an attacker
      // cycle source addresses to reset its limit.
      return false;
    }
    final attempts = _pairConfirmAttempts.putIfAbsent(
      normalizedKey,
      () => <int>[],
    );
    if (attempts.length >= maxPairConfirmAttemptsPerWindow) return false;
    attempts.add(nowMs);
    return true;
  }

  TrustedClientToken issueTrustedClientToken({
    required String clientName,
    required String deviceId,
    String? existingTrustedClientToken,
  }) {
    final nowMs = _now().millisecondsSinceEpoch;
    final requestedClientId = deviceId.trim();
    final requestedRecord = _clients[requestedClientId];
    final provesExistingIdentity = requestedRecord != null &&
        !requestedRecord.revoked &&
        requestedRecord.expiresAtMs > nowMs &&
        existingTrustedClientToken != null &&
        requestedRecord.tokenHash == hashToken(existingTrustedClientToken);
    final existing = provesExistingIdentity ? requestedRecord : null;
    final createsNewSlot = existing == null;
    if (createsNewSlot && pairedClientCount >= maxTrustedClients) {
      throw const TrustedClientLimitException();
    }
    // A supplied device ID is a label, not proof of ownership. Reusing it
    // without the remembered secret must never rotate another device's token
    // or inherit that device's already-open streams.
    final clientId = existing?.clientId ??
        (requestedRecord == null &&
                requestedClientId.isNotEmpty &&
                requestedClientId.length <= 128 &&
                !RegExp(r'[\x00-\x1f\x7f]').hasMatch(requestedClientId)
            ? requestedClientId
            : _newClientId());
    final token = _tokenGenerator.generateHex(byteCount: 32);
    final expiresAtMs = nowMs + TrustedClientToken.lifetime.inMilliseconds;
    _clients[clientId] = TrustedClientRecord(
      clientId: clientId,
      clientName: existing?.clientName ?? _normalizeClientName(clientName),
      tokenHash: hashToken(token),
      createdAtMs: existing?.createdAtMs ?? nowMs,
      lastSeenAtMs: nowMs,
      expiresAtMs: expiresAtMs,
    );
    _persistTrustedClients();
    _notifyTrustedClientsChanged();
    return TrustedClientToken(
        clientId: clientId, token: token, expiresAtMs: expiresAtMs);
  }

  Future<TrustedClientToken> issueTrustedClientTokenPersisted({
    required String clientName,
    required String deviceId,
    String? existingTrustedClientToken,
  }) =>
      _trustedClientMutations.run(
        () => _persistTrustedClientMutation(
          () => issueTrustedClientToken(
            clientName: clientName,
            deviceId: deviceId,
            existingTrustedClientToken: existingTrustedClientToken,
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
      clientName: record.clientName,
      deviceId: record.clientId,
      existingTrustedClientToken: token,
    );
  }

  Future<TrustedClientToken?> renewTrustedClientTokenPersisted(
    String token,
  ) =>
      _trustedClientMutations.run(() async {
        final record = validateTrustedClientToken(token);
        if (record == null || record.revokedAtMs != null) return null;
        return _persistTrustedClientMutation(
          () => issueTrustedClientToken(
            clientName: record.clientName,
            deviceId: record.clientId,
            existingTrustedClientToken: token,
          ),
        );
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
          _notifyTrustedClientsChanged();
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
    final nowMs = _now().millisecondsSinceEpoch;
    return _streamTokens.values.any(
      (record) => record.clientId == clientId && record.expiresAtMs > nowMs,
    );
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
          (client) =>
              _pendingRevocationClientIds.contains(client.clientId) ||
              (!client.revoked && client.expiresAtMs > nowMs),
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
    _pendingRevocationClientIds.add(clientId);
    revokeStreamTokensForClient(clientId);
    _persistTrustedClients();
    _notifyTrustedClientsChanged();
  }

  void revokeClient(String clientId) {
    final record = _clients[clientId];
    if (record != null) {
      if (record.revoked && !_pendingRevocationClientIds.contains(clientId)) {
        return;
      }
      _clients[clientId] =
          record.copyWith(revokedAtMs: _now().millisecondsSinceEpoch);
      _pendingRevocationClientIds.add(clientId);
      revokeStreamTokensForClient(clientId);
      _persistTrustedClients();
      _notifyTrustedClientsChanged();
    }
  }

  Future<void> revokeClientPersisted(String clientId) {
    // Removing access must not wait behind a slow rename or token renewal.
    // The mutation rollback path preserves this monotonic revocation.
    revokeClient(clientId);
    return _trustedClientMutations.run(flushPersistence);
  }

  void revokeAll() {
    final nowMs = _now().millisecondsSinceEpoch;
    for (final entry in _clients.entries) {
      if (entry.value.revoked &&
          !_pendingRevocationClientIds.contains(entry.key)) {
        continue;
      }
      _clients[entry.key] = entry.value.copyWith(revokedAtMs: nowMs);
      _pendingRevocationClientIds.add(entry.key);
    }
    _streamTokens.clear();
    _persistTrustedClients();
    _notifyTrustedClientsChanged();
  }

  Future<void> revokeAllPersisted() {
    revokeAll();
    return _trustedClientMutations.run(flushPersistence);
  }

  Future<void> renameTrustedClientPersisted(
    String clientId,
    String clientName,
  ) =>
      _trustedClientMutations.run(() async {
        final record = _clients[clientId];
        if (record == null || record.revoked) return;
        final name = _normalizeClientName(clientName);
        if (name == record.clientName) return;
        final updated = record.copyWith(clientName: name);
        _clients[clientId] = updated;
        _persistTrustedClients();
        try {
          await flushPersistence();
        } on TrustedClientPersistenceException {
          final current = _clients[clientId];
          if (current?.clientName == name) {
            // Keep a concurrent revocation/last-seen update while rolling
            // back only the failed display-name change.
            _clients[clientId] = current!.copyWith(
              clientName: record.clientName,
            );
          }
          _persistTrustedClients();
          rethrow;
        } finally {
          _notifyTrustedClientsChanged();
        }
      });

  void dispose() {
    unawaited(_trustedClientsChanged.close());
  }

  void clearEphemeralState() {
    clearPairingNonces();
    _pairConfirmAttempts.clear();
    _streamTokens.clear();
    _pendingRenewalClientIdsByTokenHash.clear();
  }

  void clearPairingNonces() {
    _pairingGeneration++;
    _nonces.clear();
    _publicPairingNonce = null;
    _publicPairingNonceExpiresAtMs = null;
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
    final previousRecord = previousClients[value.clientId];
    final previousTokenHash = previousRecord?.tokenHash;
    if (previousTokenHash != null) {
      _pendingRenewalClientIdsByTokenHash[previousTokenHash] = value.clientId;
    }
    try {
      await flushPersistence();
      return value;
    } on TrustedClientPersistenceException {
      final currentRecord = _clients[value.clientId];
      if (identical(currentRecord, issuedRecord)) {
        if (previousRecord == null) {
          _clients.remove(value.clientId);
        } else {
          _clients[value.clientId] = previousRecord;
        }
      } else if (issuedRecord != null &&
          currentRecord?.tokenHash == issuedRecord.tokenHash) {
        // A concurrent last-seen update cannot make failed token rotation
        // permanent. Restore durable authority while retaining revocation and
        // activity metadata from requests that raced the repository write.
        if (previousRecord == null) {
          _clients.remove(value.clientId);
        } else {
          _clients[value.clientId] = previousRecord.copyWith(
            lastSeenAtMs: currentRecord!.lastSeenAtMs,
            revokedAtMs: currentRecord.revokedAtMs,
          );
        }
      }
      // Persist the merged authority best-effort. This snapshot also retains
      // mutations to other clients that may have completed during the failed
      // repository write.
      _persistTrustedClients();
      _notifyTrustedClientsChanged();
      rethrow;
    } finally {
      if (previousTokenHash != null &&
          _pendingRenewalClientIdsByTokenHash[previousTokenHash] ==
              value.clientId) {
        _pendingRenewalClientIdsByTokenHash.remove(previousTokenHash);
      }
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
        .then<void>((_) {
      _lastPersistenceError = null;
      var changed = false;
      for (final record in snapshot) {
        if (record.revoked &&
            _clients[record.clientId]?.revokedAtMs == record.revokedAtMs) {
          changed =
              _pendingRevocationClientIds.remove(record.clientId) || changed;
        }
      }
      final missingPending = _pendingRevocationClientIds
          .where((clientId) => !_clients.containsKey(clientId))
          .toList(growable: false);
      for (final clientId in missingPending) {
        changed = _pendingRevocationClientIds.remove(clientId) || changed;
      }
      if (changed) _notifyTrustedClientsChanged();
    }).catchError((Object error) {
      _lastPersistenceError = error;
    });
    unawaited(_persistenceQueue);
  }

  void _notifyTrustedClientsChanged() {
    if (!_trustedClientsChanged.isClosed) _trustedClientsChanged.add(null);
  }

  String _newClientId() {
    String clientId;
    do {
      clientId = 'client_${_tokenGenerator.generateHex(byteCount: 8)}';
    } while (_clients.containsKey(clientId));
    return clientId;
  }

  String _normalizeClientName(String value) {
    final name = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return name.isEmpty ? 'Client' : name.characters.take(80).toString();
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
