import '../../core/protocol/pairing_payload.dart';
import '../../l10n/app_strings.dart';
import '../../services/babycam_server.dart';
import '../../services/configuration_service.dart';
import 'media/media_runtime_controller.dart';
import 'pairing/pairing_token_service.dart';
import 'pairing/server_qr_payload_builder.dart';
import 'server_runtime.dart';

class ServerCompositionRoot {
  static int createCount = 0;
  static ServerRuntime create({required ConfigurationService config, required AppStrings strings, void Function(String message)? onLog, Future<String> Function()? startPairingOverride, Future<void> Function()? startMediaOverride, Future<void> Function()? stopOverride}) {
    createCount++;
    final tokenService = PairingTokenService();
    final server = BabyCamServer(config: config, strings: strings, onLog: onLog ?? (_) {}, onAlert: (_) {}, tokenService: tokenService);
    final qrBuilder = ServerQrPayloadBuilder(tokenService: tokenService);
    String? lastAddress;
    final media = MediaRuntimeController(onStart: startMediaOverride ?? server.startMediaRuntime, onStop: server.stopMediaRuntime);
    return ServerRuntime(
      mediaRuntime: media,
      onStartPairing: startPairingOverride ?? () async {
        final url = await server.startPairingMode();
        final uri = Uri.parse(url);
        lastAddress = uri.host;
        final payload = qrBuilder.build(host: lastAddress ?? '127.0.0.1');
        return payload.toUriString();
      },
      onStop: stopOverride ?? server.dispose,
    );
  }

  static String buildQrUri(PairingPayload payload) => payload.toUriString();
}
