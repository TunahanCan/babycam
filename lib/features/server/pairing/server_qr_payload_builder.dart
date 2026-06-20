import '../../../core/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/security/transport_security_config.dart';
import 'pairing_token_service.dart';

class ServerQrPayloadBuilder {
  ServerQrPayloadBuilder(
      {required this.tokenService,
      this.deviceId = 'server_local',
      this.deviceName = 'Bebek Odası',
      this.certificateFingerprintSha256 = '',
      this.transportSecurityConfig = TransportSecurityConfig.secureDefault});
  final PairingTokenService tokenService;
  final String deviceId;
  final String deviceName;
  final String certificateFingerprintSha256;
  final TransportSecurityConfig transportSecurityConfig;

  PairingPayload build(
      {required String host,
      int port = MimiCamProtocol.httpPort,
      Duration ttl = const Duration(minutes: 10),
      String? certificateFingerprintSha256,
      TransportSecurityConfig? transportSecurityConfig,
      Map<String, Object?>? capabilities}) {
    final security = transportSecurityConfig ?? this.transportSecurityConfig;
    return PairingPayload(
      schemaVersion: 1,
      host: host,
      port: port,
      deviceId: deviceId,
      deviceName: deviceName,
      pairingNonce: tokenService.createPairingNonce(),
      expiresAtMs: DateTime.now().add(ttl).millisecondsSinceEpoch,
      certificateFingerprintSha256:
          certificateFingerprintSha256 ?? this.certificateFingerprintSha256,
      transport: security.toPayloadTransport(),
      capabilities: capabilities ??
          {
            'video': 'mjpeg',
            'audio': 'pcm16le',
            'events': 'json',
            'transport': security.httpScheme,
          },
    );
  }
}
