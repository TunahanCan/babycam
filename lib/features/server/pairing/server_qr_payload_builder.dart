import '../../../core/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/security/transport_config.dart';
import 'pairing_token_service.dart';

class ServerQrPayloadBuilder {
  ServerQrPayloadBuilder(
      {required this.tokenService,
      this.deviceId = 'server_local',
      this.deviceName = 'Bebek Odası',
      this.transportConfig = TransportConfig.local});
  final PairingTokenService tokenService;
  final String deviceId;
  final String deviceName;
  final TransportConfig transportConfig;

  PairingPayload build(
      {required String host,
      int port = MimiCamProtocol.httpPort,
      Duration ttl = const Duration(minutes: 10),
      TransportConfig? transportConfig,
      Map<String, Object?>? capabilities}) {
    final transport = transportConfig ?? this.transportConfig;
    return PairingPayload(
      schemaVersion: 1,
      host: host,
      port: port,
      deviceId: deviceId,
      deviceName: deviceName,
      pairingNonce: tokenService.createPairingNonce(),
      expiresAtMs: DateTime.now().add(ttl).millisecondsSinceEpoch,
      transport: transport.payloadTransport,
      capabilities: capabilities ??
          {
            'video': 'mjpeg',
            'audio': 'pcm16le',
            'events': 'json',
            'maxClients': PairingTokenService.defaultMaxTrustedClients,
          },
    );
  }
}
