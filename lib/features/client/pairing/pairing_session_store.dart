import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';

class PairingSessionStore {
  PairingSessionStore(this._preferences);
  static const _key = 'pairing_session';
  final SharedPreferences _preferences;
  Future<void> save(PairingSession session) => _preferences.setString(_key, jsonEncode({'payload': session.payload.toJson(), 'token': session.sessionToken}));
  PairingSession? load() {
    final raw = _preferences.getString(_key);
    if (raw == null) return null;
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final payload = PairingPayload.fromJson(Map<String, Object?>.from(json['payload'] as Map));
    final token = json['token'];
    return payload != null && token is String ? PairingSession(payload: payload, sessionToken: token) : null;
  }
  Future<void> clear() => _preferences.remove(_key);
}
