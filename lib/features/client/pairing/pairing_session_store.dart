import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/protocol/device_feature_models.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/security/miucam_secure_storage.dart';

class ChildProfileLimitException implements Exception {
  const ChildProfileLimitException();

  static const code = 'MAX_CHILD_PROFILES_REACHED';

  @override
  String toString() => code;
}

class PairingSessionStore {
  PairingSessionStore(
    this._preferences, {
    SecureTokenStore? secureTokens,
  }) : _secureTokens = secureTokens ?? const FlutterSecureTokenStore();

  static const maxChildProfiles = 4;
  static const _key = 'pairing_session';
  static const _tokenKey = 'pairing_session_token';
  static const _childrenKey = 'pairing_children';
  static const _selectedChildIdKey = 'pairing_selected_child_id';
  static const _childTokenPrefix = 'pairing_child_token.';

  final SharedPreferences _preferences;
  final SecureTokenStore _secureTokens;

  Future<void> save(PairingSession session) => saveChild(session);

  /// Checks storage capacity before the room issues a new trusted token.
  /// Re-pairing a known room replaces that room's profile and is always safe.
  Future<void> ensureCanSavePayload(PairingPayload payload) async {
    final existing = await _readProfiles(migrateLegacy: false);
    final id = _childIdForPayload(payload);
    final replacing = existing.any((profile) => profile.id == id);
    if (!replacing && existing.length >= maxChildProfiles) {
      throw const ChildProfileLimitException();
    }
  }

  Future<void> saveChild(
    PairingSession session, {
    bool selected = true,
  }) async {
    final existing = await _readProfiles(migrateLegacy: false);
    final id = _childIdForPayload(session.payload);
    final replacing = existing.any((profile) => profile.id == id);
    if (!replacing && existing.length >= maxChildProfiles) {
      throw const ChildProfileLimitException();
    }
    final shouldSelect = selected || existing.isEmpty;
    final profile = ChildProfile.fromSession(
      session,
      selected: shouldSelect,
      lastSeenAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final next = <ChildProfile>[
      for (final child in existing)
        if (child.id != id)
          shouldSelect ? child.copyWith(selected: false) : child,
      profile,
    ];
    await _secureTokens.write(
      key: _childTokenKey(id),
      value: session.sessionToken,
    );
    await _writeProfiles(next);
    if (shouldSelect) {
      await _preferences.setString(_selectedChildIdKey, id);
      await _secureTokens.write(key: _tokenKey, value: session.sessionToken);
      await _writeMetadata(session);
    }
  }

  Future<PairingSession?> load() => loadSelected();

  Future<PairingSession?> loadSelected() async {
    final profiles = await _readProfiles(migrateLegacy: true);
    if (profiles.isEmpty) return _loadLegacySession();
    final selectedId = _preferences.getString(_selectedChildIdKey);
    final selected = profiles.firstWhere(
      (profile) => profile.id == selectedId || profile.selected,
      orElse: () => profiles.first,
    );
    final token = await _secureTokens.read(key: _childTokenKey(selected.id)) ??
        await _secureTokens.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;
    final session = selected.toSession(sessionToken: token);
    await _secureTokens.write(key: _tokenKey, value: token);
    await _writeMetadata(session);
    return session;
  }

  Future<List<ChildProfile>> loadChildren() async =>
      _readProfiles(migrateLegacy: true);

  Future<void> selectChild(String childId) async {
    final profiles = await _readProfiles(migrateLegacy: true);
    final selected = profiles.where((profile) => profile.id == childId);
    if (selected.isEmpty) return;
    final next = [
      for (final profile in profiles)
        profile.copyWith(selected: profile.id == childId),
    ];
    await _writeProfiles(next);
    await _preferences.setString(_selectedChildIdKey, childId);
    final token = await _secureTokens.read(key: _childTokenKey(childId));
    if (token != null && token.isNotEmpty) {
      await _secureTokens.write(key: _tokenKey, value: token);
      await _writeMetadata(selected.first.toSession(sessionToken: token));
    }
  }

  Future<void> removeChild(String childId) async {
    final profiles = await _readProfiles(migrateLegacy: false);
    final remaining = [
      for (final profile in profiles)
        if (profile.id != childId) profile,
    ];
    await _secureTokens.delete(key: _childTokenKey(childId));
    if (remaining.isEmpty) {
      await _preferences.remove(_childrenKey);
      await _preferences.remove(_selectedChildIdKey);
      await _clearLegacy();
      return;
    }
    final selectedId = _preferences.getString(_selectedChildIdKey);
    final removedSelected = selectedId == childId ||
        profiles.any((p) => p.id == childId && p.selected);
    final nextSelected = removedSelected ? remaining.first.id : selectedId;
    final next = [
      for (final profile in remaining)
        profile.copyWith(selected: profile.id == nextSelected),
    ];
    await _writeProfiles(next);
    if (nextSelected != null) {
      await _preferences.setString(_selectedChildIdKey, nextSelected);
      await selectChild(nextSelected);
    }
  }

  Future<PairingSession?> _loadLegacySession() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _clearAndReturnNull();
      final json = Map<Object?, Object?>.from(decoded);
      final payloadJson = json['payload'];
      if (payloadJson is! Map) return _clearAndReturnNull();
      final payload = PairingPayload.fromJson(
        Map<String, Object?>.from(payloadJson),
      );
      if (payload == null) return _clearAndReturnNull();

      var token = await _secureTokens.read(key: _tokenKey);
      final legacyToken = json['token'];
      if ((token == null || token.isEmpty) &&
          legacyToken is String &&
          legacyToken.isNotEmpty) {
        token = legacyToken;
        await _secureTokens.write(key: _tokenKey, value: legacyToken);
      }
      if (token == null || token.isEmpty) return _clearAndReturnNull();

      final session = PairingSession(
        payload: payload,
        sessionToken: token,
        clientId: json['clientId']?.toString() ?? 'client_unknown',
        trustedClientTokenExpiresAtMs:
            json['trustedClientTokenExpiresAtMs'] is int
                ? json['trustedClientTokenExpiresAtMs'] as int
                : 0,
        pairedAtMs: json['pairedAtMs'] is int ? json['pairedAtMs'] as int : 0,
      );
      if (legacyToken is String) await _writeMetadata(session);
      return session;
    } catch (_) {
      return _clearAndReturnNull();
    }
  }

  Future<void> clear() async {
    final profiles = await _readProfiles(migrateLegacy: false);
    for (final profile in profiles) {
      await _secureTokens.delete(key: _childTokenKey(profile.id));
    }
    await _preferences.remove(_childrenKey);
    await _preferences.remove(_selectedChildIdKey);
    await _clearLegacy();
  }

  Future<List<ChildProfile>> _readProfiles(
      {required bool migrateLegacy}) async {
    final raw = _preferences.getString(_childrenKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Iterable) {
          return decoded
              .map(ChildProfile.fromJson)
              .whereType<ChildProfile>()
              .toList(growable: false);
        }
      } catch (_) {
        await _preferences.remove(_childrenKey);
      }
    }
    if (!migrateLegacy) return const [];
    final legacy = await _loadLegacySession();
    if (legacy == null) return const [];
    await saveChild(legacy);
    return _readProfiles(migrateLegacy: false);
  }

  Future<void> _writeProfiles(List<ChildProfile> profiles) =>
      _preferences.setString(
        _childrenKey,
        jsonEncode([for (final profile in profiles) profile.toJson()]),
      );

  Future<void> _writeMetadata(PairingSession session) => _preferences.setString(
        _key,
        jsonEncode({
          'payload': session.payload.toJson(),
          'clientId': session.clientId,
          'trustedClientTokenExpiresAtMs':
              session.trustedClientTokenExpiresAtMs,
          'pairedAtMs': session.pairedAtMs,
        }),
      );

  Future<PairingSession?> _clearAndReturnNull() async {
    await _clearLegacy();
    return null;
  }

  Future<void> _clearLegacy() async {
    await _preferences.remove(_key);
    await _secureTokens.delete(key: _tokenKey);
  }

  String _childTokenKey(String childId) => '$_childTokenPrefix$childId';

  String _childIdForPayload(PairingPayload payload) {
    final serverDeviceId = payload.deviceId.trim();
    return serverDeviceId.isNotEmpty
        ? serverDeviceId
        : '${payload.host}:${payload.port}';
  }
}

abstract interface class SecureTokenStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureTokenStore implements SecureTokenStore {
  const FlutterSecureTokenStore({
    FlutterSecureStorage storage = miucamSecureStorage,
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
