import 'dart:convert';

import '../network/lan_endpoint.dart';
import 'miucam_protocol.dart';

class PairingPayload {
  static const maxEncodedUriLength = 16384;
  const PairingPayload(
      {required this.schemaVersion,
      this.scheme = 'miucam',
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

  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= expiresAtMs;
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
    final scheme = json['scheme'] ?? 'miucam';
    final host = json['host'];
    final port = json['port'];
    final deviceId = json['deviceId'];
    final deviceName = json['deviceName'];
    final pairingNonce = json['pairingNonce'];
    final expiresAtMs = json['expiresAtMs'];
    final transport = json['transport'] ?? 'http_ws';
    final capabilities = json['capabilities'];
    if (schemaVersion is! int ||
        schemaVersion != MiuCamProtocolV2.schemaVersion ||
        scheme != 'miucam' ||
        host is! String ||
        port is! int ||
        deviceId is! String ||
        deviceName is! String ||
        pairingNonce is! String ||
        expiresAtMs is! int ||
        transport != 'http_ws' ||
        capabilities is! Map) {
      return null;
    }
    // Unsupported secure transport claims must never silently become HTTP.
    // Reject malformed endpoints before constructing a network request, while
    // retaining hostname and scoped IPv6 support for older local networks.
    final endpoint = LanEndpoint.parse(host, defaultPort: port);
    if (host.length > 512 ||
        RegExp(r'[\x00-\x20\x7f/?#@\\]').hasMatch(host) ||
        endpoint == null ||
        endpoint.port != port ||
        normalizeLanHost(endpoint.host) != normalizeLanHost(host) ||
        deviceId.isEmpty ||
        deviceId.length > 128 ||
        deviceName.length > 1024 ||
        pairingNonce.isEmpty ||
        pairingNonce.length > 256 ||
        expiresAtMs < 0 ||
        expiresAtMs > 8640000000000000 ||
        capabilities.length > 32 ||
        capabilities.keys.any((key) => key is! String)) {
      return null;
    }
    return PairingPayload(
        schemaVersion: schemaVersion,
        scheme: scheme as String,
        host: host,
        port: port,
        deviceId: deviceId,
        deviceName: deviceName,
        pairingNonce: pairingNonce,
        expiresAtMs: expiresAtMs,
        transport: transport as String,
        capabilities: Map<String, Object?>.from(capabilities));
  }

  String toUriString() => Uri(scheme: 'miucam', host: 'pair', queryParameters: {
        'payload': base64UrlEncode(utf8.encode(jsonEncode(toJson())))
      }).toString();

  static PairingPayload? parseUri(
    String value, {
    bool allowExpired = false,
  }) {
    if (value.length > maxEncodedUriLength) return null;
    try {
      final uri = Uri.parse(value);
      if (uri.scheme != 'miucam' || uri.host != 'pair') return null;
      final payload = uri.queryParameters['payload'];
      if (payload == null) return null;
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (decoded is! Map<String, Object?>) return null;
      final parsed = fromJson(decoded);
      if (parsed == null || (!allowExpired && parsed.isExpired)) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
}
