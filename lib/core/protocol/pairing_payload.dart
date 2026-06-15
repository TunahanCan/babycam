import 'dart:convert';

import 'babycam_protocol.dart';

class PairingPayload {
  const PairingPayload({required this.schemaVersion, required this.host, required this.port, required this.deviceId, required this.deviceName, required this.pairingNonce, required this.expiresAtMs, required this.capabilities});
  final int schemaVersion;
  final String host;
  final int port;
  final String deviceId;
  final String deviceName;
  final String pairingNonce;
  final int expiresAtMs;
  final Map<String, Object?> capabilities;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;

  Map<String, Object?> toJson() => {'schemaVersion': schemaVersion, 'host': host, 'port': port, 'deviceId': deviceId, 'deviceName': deviceName, 'pairingNonce': pairingNonce, 'expiresAtMs': expiresAtMs, 'capabilities': capabilities};

  static PairingPayload? fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final host = json['host'];
    final port = json['port'];
    final deviceId = json['deviceId'];
    final deviceName = json['deviceName'];
    final pairingNonce = json['pairingNonce'];
    final expiresAtMs = json['expiresAtMs'];
    final capabilities = json['capabilities'];
    if (schemaVersion != BabyCamProtocolV2.schemaVersion || host is! String || port is! int || deviceId is! String || deviceName is! String || pairingNonce is! String || expiresAtMs is! int || capabilities is! Map) return null;
    return PairingPayload(schemaVersion: schemaVersion, host: host, port: port, deviceId: deviceId, deviceName: deviceName, pairingNonce: pairingNonce, expiresAtMs: expiresAtMs, capabilities: Map<String, Object?>.from(capabilities));
  }

  String toUriString() => Uri(scheme: 'babycam', host: 'pair', queryParameters: {'payload': base64UrlEncode(utf8.encode(jsonEncode(toJson())))}).toString();

  static PairingPayload? parseUri(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'babycam' || uri.host != 'pair') return null;
      final payload = uri.queryParameters['payload'];
      if (payload == null) return null;
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (decoded is! Map<String, Object?>) return null;
      final parsed = fromJson(decoded);
      if (parsed == null || parsed.isExpired) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
}
