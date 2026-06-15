import '../../../core/babycam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import 'pairing_token_service.dart';

class ServerQrPayloadBuilder {
  ServerQrPayloadBuilder({required this.tokenService, this.deviceId = 'server_local', this.deviceName = 'Bebek Odası', this.certificateFingerprintSha256 = 'pending-local-tls-fingerprint'});
  final PairingTokenService tokenService;
  final String deviceId;
  final String deviceName;
  final String certificateFingerprintSha256;

  PairingPayload build({required String host, int port = BabyCamProtocol.httpPort, Duration ttl = const Duration(minutes: 2)}) => PairingPayload(
        schemaVersion: 1,
        host: host,
        port: port,
        deviceId: deviceId,
        deviceName: deviceName,
        pairingNonce: tokenService.createPairingNonce(),
        expiresAtMs: DateTime.now().add(ttl).millisecondsSinceEpoch,
        certificateFingerprintSha256: certificateFingerprintSha256,
        capabilities: const {'video': 'mjpeg', 'audio': 'pcm16le', 'events': 'json', 'transport': 'https'},
      );
}
