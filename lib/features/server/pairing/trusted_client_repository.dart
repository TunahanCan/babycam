import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrustedClientRecord {
  const TrustedClientRecord({
    required this.clientId,
    required this.clientName,
    required this.tokenHash,
    required this.createdAtMs,
    required this.lastSeenAtMs,
    required this.expiresAtMs,
    this.revokedAtMs,
  });

  factory TrustedClientRecord.fromJson(Map<String, Object?> json) {
    final clientId = json['clientId'];
    final clientName = json['clientName'];
    final tokenHash = json['tokenHash'];
    final createdAtMs = json['createdAtMs'];
    final lastSeenAtMs = json['lastSeenAtMs'];
    final expiresAtMs = json['expiresAtMs'];
    final revokedAtMs = json['revokedAtMs'];
    if (clientId is! String ||
        clientId.isEmpty ||
        clientName is! String ||
        tokenHash is! String ||
        tokenHash.length != 64 ||
        createdAtMs is! int ||
        lastSeenAtMs is! int ||
        expiresAtMs is! int ||
        (revokedAtMs != null && revokedAtMs is! int)) {
      throw const FormatException('Invalid trusted-client record.');
    }
    return TrustedClientRecord(
      clientId: clientId,
      clientName: clientName,
      tokenHash: tokenHash,
      createdAtMs: createdAtMs,
      lastSeenAtMs: lastSeenAtMs,
      expiresAtMs: expiresAtMs,
      revokedAtMs: revokedAtMs as int?,
    );
  }

  final String clientId;
  final String clientName;
  final String tokenHash;
  final int createdAtMs;
  final int lastSeenAtMs;
  final int expiresAtMs;
  final int? revokedAtMs;

  bool get revoked => revokedAtMs != null;
  DateTime get pairedAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get lastSeenAt => DateTime.fromMillisecondsSinceEpoch(lastSeenAtMs);

  TrustedClientRecord copyWith({
    String? tokenHash,
    int? lastSeenAtMs,
    int? expiresAtMs,
    int? revokedAtMs,
  }) =>
      TrustedClientRecord(
        clientId: clientId,
        clientName: clientName,
        tokenHash: tokenHash ?? this.tokenHash,
        createdAtMs: createdAtMs,
        lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
        expiresAtMs: expiresAtMs ?? this.expiresAtMs,
        revokedAtMs: revokedAtMs ?? this.revokedAtMs,
      );

  Map<String, Object?> toJson() => {
        'clientId': clientId,
        'clientName': clientName,
        'tokenHash': tokenHash,
        'createdAtMs': createdAtMs,
        'lastSeenAtMs': lastSeenAtMs,
        'expiresAtMs': expiresAtMs,
        if (revokedAtMs != null) 'revokedAtMs': revokedAtMs,
      };
}

abstract interface class TrustedClientRepository {
  List<TrustedClientRecord> readAll();

  Future<void> replaceAll(List<TrustedClientRecord> clients);
}

class InMemoryTrustedClientRepository implements TrustedClientRepository {
  InMemoryTrustedClientRepository(
      [Iterable<TrustedClientRecord> initial = const []])
      : _clients = List<TrustedClientRecord>.of(initial, growable: false);

  List<TrustedClientRecord> _clients;

  @override
  List<TrustedClientRecord> readAll() =>
      List<TrustedClientRecord>.of(_clients, growable: false);

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    _clients = List<TrustedClientRecord>.of(clients, growable: false);
  }
}

/// Persists only token hashes and pairing metadata; raw bearer tokens never
/// enter SharedPreferences.
class SharedPreferencesTrustedClientRepository
    implements TrustedClientRepository {
  SharedPreferencesTrustedClientRepository(
    this._preferences, {
    this.storageKey = defaultStorageKey,
    this.maxStoredRecords = 64,
  });

  static const defaultStorageKey = 'server.trusted_clients.v1';

  final SharedPreferences _preferences;
  final String storageKey;
  final int maxStoredRecords;

  @override
  List<TrustedClientRecord> readAll() {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map || decoded['version'] != 1) return const [];
      final clients = decoded['clients'];
      if (clients is! List) return const [];
      return clients
          .take(maxStoredRecords)
          .whereType<Map>()
          .map(
            (value) => TrustedClientRecord.fromJson(
              value.map(
                (key, item) => MapEntry(key.toString(), item),
              ),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    final bounded = clients.length <= maxStoredRecords
        ? clients
        : (clients.toList()
              ..sort((a, b) => b.lastSeenAtMs.compareTo(a.lastSeenAtMs)))
            .take(maxStoredRecords)
            .toList(growable: false);
    await _preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'clients': bounded.map((client) => client.toJson()).toList(),
      }),
    );
  }
}
