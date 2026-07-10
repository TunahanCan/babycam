import 'dart:async';

import '../../core/protocol/pairing_payload.dart';
import '../../core/security/transport_config.dart';
import '../../l10n/app_strings.dart';
import '../../services/mimicam_server.dart';
import '../../services/configuration_service.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/discovery/mimicam_service_discovery.dart';
import '../../services/platform/platform_runtime_contract.dart';
import 'media/media_runtime_controller.dart';
import 'media/webrtc/flutter_webrtc_server_gateway.dart';
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
    final tokenService = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        config.preferences,
      ),
    );
    final broadcastAccess = BroadcastAccessService(config.preferences);
    final webRtcGateway = FlutterWebRtcServerGateway(onLog: onLog);
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
          required String mediaTransport,
        }) =>
            runtime.startStreamSession(
              clientId,
              StreamSessionOptions(
                video: video,
                audio: audio,
                transport: mediaTransport == 'webrtc'
                    ? ServerStreamTransport.webRtc
                    : ServerStreamTransport.legacy,
              ),
            ),
        onStreamSessionStopped: (clientId) => runtime.endSession(clientId),
        tokenService: tokenService,
        transportConfig: transportConfig,
        broadcastAccess: broadcastAccess,
        serviceAdvertiser: MimiCamServiceAdvertiser(),
        webRtcGateway: webRtcGateway,
        // ServerRuntime owns the authoritative per-session media demand. The
        // HTTP server must not eagerly acquire both camera and microphone.
        startMediaOnSessionStart: false);
    final qrBuilder = ServerQrPayloadBuilder(
      tokenService: tokenService,
      transportConfig: transportConfig,
    );
    String? lastAddress;
    const platformContract = PlatformRuntimeContract();
    Future<void> publishNativeDemand(MediaResourceDemand demand) async {
      try {
        await platformContract.setMediaDemand(
          active: !demand.isEmpty,
          camera: demand.video,
          microphone: demand.audio,
        );
      } catch (_) {
        // Unsupported/test targets intentionally run without native channels.
      }
    }

    final media = startMediaOverride == null
        ? MediaRuntimeController(
            onStartVideo: server.startVideoRuntime,
            onStopVideo: server.stopVideoRuntime,
            onStartAudio: server.startAudioRuntime,
            onStopAudio: server.stopAudioRuntime,
            onDemandChanged: publishNativeDemand,
          )
        : MediaRuntimeController(
            onStart: startMediaOverride,
            onStop: server.stopMediaRuntime,
            onDemandChanged: publishNativeDemand,
          );
    final platformLifecycle = PlatformMediaLifecycleCoordinator(
      events: platformContract.events,
      pauseMedia: (reason) => runtime.pauseMediaForPlatform(reason),
      recoverMedia: (reason) => runtime.recoverMediaForPlatform(reason),
      onTelemetry: (event) =>
          onLog?.call('Platform media lifecycle: ${event.type}'),
    );
    runtime = ServerRuntime(
      mediaRuntime: media,
      platformLifecycle: platformLifecycle,
      previewSource: () => server.cameraController,
      mediaProfile: () => server.activeMediaProfile,
      onSettingsChanged: server.reloadAnalysisConfig,
      broadcastAccess: broadcastAccess,
      onMediaDemandChanged: publishNativeDemand,
      onPauseExternalMedia: server.pauseExternalMediaForPlatform,
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
