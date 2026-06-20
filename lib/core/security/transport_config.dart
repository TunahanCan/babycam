enum TransportMode { localHttpWs }

class TransportConfig {
  const TransportConfig();

  static const local = TransportConfig();

  TransportMode get mode => TransportMode.localHttpWs;
  String get httpScheme => 'http';
  String get wsScheme => 'ws';
  String get payloadTransport => 'http_ws';
}
