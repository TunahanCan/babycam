import 'dart:convert';

import 'mimicam_protocol.dart';

class PairingPayload {
  const PairingPayload(
      {required this.schemaVersion,
      this.scheme = 'mimicam',
      required this.host,
      required this.port,
      required this.deviceId,
      required this.deviceName,
      required this.pairingNonce,
      required this.expiresAtMs,
      this.transport = 'http_ws',
      required this.capabilities});
  final int schemaVersion;
  final String scheme;
  final String host;
  final int port;
  final String deviceId;
  final String deviceName;
  final String pairingNonce;
  final int expiresAtMs;
  final String transport;
  final Map<String, Object?> capabilities;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;
  String get httpScheme => 'http';
  String get wsScheme => 'ws';

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'scheme': scheme,
        'host': host,
        'port': port,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'pairingNonce': pairingNonce,
        'expiresAtMs': expiresAtMs,
        'transport': transport,
        'capabilities': capabilities
      };

  static PairingPayload? fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final scheme = json['scheme'] ?? 'mimicam';
    final host = json['host'];
    final port = json['port'];
    final deviceId = json['deviceId'];
    final deviceName = json['deviceName'];
    final pairingNonce = json['pairingNonce'];
    final expiresAtMs = json['expiresAtMs'];
    final transport = json['transport'] ?? 'http_ws';
    final capabilities = json['capabilities'];
    if (schemaVersion is! int ||
        schemaVersion != MimiCamProtocolV2.schemaVersion ||
        scheme is! String ||
        host is! String ||
        port is! int ||
        deviceId is! String ||
        deviceName is! String ||
        pairingNonce is! String ||
        expiresAtMs is! int ||
        transport is! String ||
        capabilities is! Map) {
      return null;
    }
    return PairingPayload(
        schemaVersion: schemaVersion,
        scheme: scheme,
        host: host,
        port: port,
        deviceId: deviceId,
        deviceName: deviceName,
        pairingNonce: pairingNonce,
        expiresAtMs: expiresAtMs,
        transport: transport,
        capabilities: Map<String, Object?>.from(capabilities));
  }

  String toUriString() =>
      Uri(scheme: 'mimicam', host: 'pair', queryParameters: {
        'payload': base64UrlEncode(utf8.encode(jsonEncode(toJson())))
      }).toString();

  static PairingPayload? parseUri(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'mimicam' || uri.host != 'pair') return null;
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
