import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class PairingSessionStore {
  PairingSessionStore(
    this._preferences, {
    SecureTokenStore? secureTokens,
  }) : _secureTokens = secureTokens ?? const FlutterSecureTokenStore();

  static const _key = 'pairing_session';
  static const _tokenKey = 'pairing_session_token';

  final SharedPreferences _preferences;
  final SecureTokenStore _secureTokens;

  Future<void> save(PairingSession session) async {
    await _secureTokens.write(key: _tokenKey, value: session.sessionToken);
    await _writeMetadata(session);
  }

  Future<PairingSession?> load() async {
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
        clientId: json['clientId']?.toString() ?? 'client_local',
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
    await _preferences.remove(_key);
    await _secureTokens.delete(key: _tokenKey);
  }

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
    await clear();
    return null;
  }
}

abstract interface class SecureTokenStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureTokenStore implements SecureTokenStore {
  const FlutterSecureTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
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
