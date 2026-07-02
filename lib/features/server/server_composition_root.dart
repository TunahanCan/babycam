import 'dart:async';

import '../../core/protocol/pairing_payload.dart';
import '../../core/security/transport_config.dart';
import '../../l10n/app_strings.dart';
import '../../services/mimicam_server.dart';
import '../../services/configuration_service.dart';
import '../../services/monetization/broadcast_access_service.dart';
import 'media/media_runtime_controller.dart';
import 'pairing/pairing_token_service.dart';
import 'pairing/server_qr_payload_builder.dart';
import 'server_runtime.dart';

class ServerCompositionRoot {
  static int createCount = 0;
  static ServerRuntime create(
      {required ConfigurationService config,
      required AppStrings strings,
      void Function(String message)? onLog,
      Future<String> Function()? startPairingOverride,
      Future<void> Function()? startMediaOverride,
      Future<void> Function()? stopOverride,
      TransportConfig transportConfig = TransportConfig.local}) {
    createCount++;
    final tokenService = PairingTokenService();
    final broadcastAccess = BroadcastAccessService(config.preferences);
    void Function()? notifyMediaProfileChanged;
    void Function()? notifyBroadcastAccessChanged;
    late final ServerRuntime runtime;
    final server = MimiCamServer(
        config: config,
        strings: strings,
        onLog: onLog ?? (_) {},
        onAlert: (_) {},
        onMediaProfileChanged: (_) => notifyMediaProfileChanged?.call(),
        onBroadcastAccessChanged: (_) => notifyBroadcastAccessChanged?.call(),
        onStreamSessionStarted: (
          clientId, {
          required bool video,
          required bool audio,
        }) =>
            runtime.startStreamSession(
              clientId,
              StreamSessionOptions(video: video, audio: audio),
            ),
        onStreamSessionStopped: (clientId) => runtime.endSession(clientId),
        tokenService: tokenService,
        transportConfig: transportConfig,
        broadcastAccess: broadcastAccess);
    final qrBuilder = ServerQrPayloadBuilder(
      tokenService: tokenService,
      transportConfig: transportConfig,
    );
    String? lastAddress;
    final media = MediaRuntimeController(
        onStart: startMediaOverride ?? server.startMediaRuntime,
        onStop: server.stopMediaRuntime);
    runtime = ServerRuntime(
      mediaRuntime: media,
      previewSource: () => server.cameraController,
      mediaProfile: () => server.activeMediaProfile,
      onSettingsChanged: server.reloadAnalysisConfig,
      broadcastAccess: broadcastAccess,
      onStartPairing: startPairingOverride ??
          () async {
            final url = await server.startPairingMode();
            final uri = Uri.parse(url);
            lastAddress = uri.host;
            final payload = qrBuilder.build(
              host: lastAddress ?? '127.0.0.1',
              port: uri.port,
              transportConfig: transportConfig,
              capabilities: server.mediaCapabilities,
            );
            return payload.toUriString();
          },
      onStopPairing: startPairingOverride == null
          ? () async => server.stopPairingMode()
          : null,
      onStop: stopOverride ?? server.dispose,
    );
    notifyMediaProfileChanged = runtime.refreshMediaProfile;
    notifyBroadcastAccessChanged =
        () => unawaited(runtime.refreshBroadcastAccess());
    unawaited(runtime.refreshBroadcastAccess());
    return runtime;
  }

  static String buildQrUri(PairingPayload payload) => payload.toUriString();
}
