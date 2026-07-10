import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/protocol/pairing_payload.dart';
import '../../core/security/transport_config.dart';
import '../../l10n/app_strings.dart';
import '../../services/mimicam_server.dart';
import '../../services/configuration_service.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/discovery/mimicam_discovery_identity.dart';
import '../../services/discovery/mimicam_service_discovery.dart';
import '../../services/platform/platform_runtime_contract.dart';
import '../../services/platform/android_service_media_source.dart';
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
    final discoveryIdentity =
        PersistentMimiCamDiscoveryIdentity(config.preferences);
    final serverDeviceId = discoveryIdentity.getOrCreate();
    final webRtcGateway = FlutterWebRtcServerGateway(onLog: onLog);
    void Function()? notifyMediaProfileChanged;
    void Function()? notifyBroadcastAccessChanged;
    const platformContract = PlatformRuntimeContract();
    var nativeMediaDemand = MediaResourceDemand.none;
    var nativePlaybackDemand = false;
    Future<void> nativeDemandTail = Future<void>.value();

    Future<void> publishNativeDemand() {
      final operation = nativeDemandTail.then<void>((_) async {
        final demand = nativeMediaDemand;
        final playback = nativePlaybackDemand;
        try {
          await platformContract.setMediaDemand(
            active: !demand.isEmpty || playback,
            camera: demand.video,
            microphone: demand.audio,
            playback: playback,
            nativeCameraCapture: demand.serviceVideoCapture,
            nativeMicrophoneCapture: demand.serviceAudioCapture,
          );
        } catch (_) {
          // Unsupported/test targets intentionally have no native channel.
        }
      });
      nativeDemandTail = operation.then<void>((_) {}, onError: (_) {});
      return operation;
    }

    Future<void> publishRuntimeDemand(MediaResourceDemand demand) {
      nativeMediaDemand = demand;
      return publishNativeDemand();
    }

    Future<void> publishPlaybackDemand(bool active) {
      nativePlaybackDemand = active;
      return publishNativeDemand();
    }

    final nativeMediaSource = defaultTargetPlatform == TargetPlatform.android &&
            startMediaOverride == null
        ? AndroidServiceMediaSource(
            jpegQuality: 68,
            maxVideoFps: 8,
          )
        : null;
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
        onWebRtcCaptureStarting: (clientId) =>
            runtime.activateExternalCapture(clientId),
        onWebRtcCaptureEnded: (clientId) =>
            runtime.deactivateExternalCapture(clientId),
        onAlertClientConnected: (clientId) => runtime
            .enableNotificationsForClient(clientId, cry: true, motion: true),
        onAlertClientDisconnected: (clientId) =>
            runtime.disableNotificationsForClient(clientId),
        onPlaybackDemandChanged: publishPlaybackDemand,
        tokenService: tokenService,
        transportConfig: transportConfig,
        broadcastAccess: broadcastAccess,
        mediaSource: nativeMediaSource,
        serverDeviceIdProvider: () => serverDeviceId,
        serviceAdvertiser: MimiCamServiceAdvertiser(
          deviceIdProvider: () => serverDeviceId,
        ),
        webRtcGateway: webRtcGateway,
        // ServerRuntime owns the authoritative per-session media demand. The
        // HTTP server must not eagerly acquire both camera and microphone.
        startMediaOnSessionStart: false);
    String? lastAddress;

    final media = startMediaOverride == null
        ? MediaRuntimeController(
            onStartVideo: server.startVideoRuntime,
            onStopVideo: server.stopVideoRuntime,
            onStartAudio: server.startAudioRuntime,
            onStopAudio: server.stopAudioRuntime,
          )
        : MediaRuntimeController(
            onStart: startMediaOverride,
            onStop: server.stopMediaRuntime,
          );
    final platformLifecycle = PlatformMediaLifecycleCoordinator(
      events: platformContract.events,
      pauseMedia: (reason) => runtime.pauseMediaForPlatform(reason),
      recoverMedia: (reason) => runtime.recoverMediaForPlatform(reason),
      onAudioOutputLost: (event) => server.handleAudioOutputLost(event.type),
      onTelemetry: (event) =>
          onLog?.call('Platform media lifecycle: ${event.type}'),
    );
    runtime = ServerRuntime(
      mediaRuntime: media,
      platformLifecycle: platformLifecycle,
      previewSource: () => nativeMediaSource ?? server.cameraController,
      mediaProfile: () => server.activeMediaProfile,
      onSettingsChanged: server.reloadAnalysisConfig,
      broadcastAccess: broadcastAccess,
      onMediaDemandChanged: publishRuntimeDemand,
      onPauseExternalMedia: server.pauseExternalMediaForPlatform,
      onStartPairing: startPairingOverride ??
          () async {
            final url = await server.startPairingMode();
            final uri = Uri.parse(url);
            lastAddress = uri.host;
            final payload = ServerQrPayloadBuilder(
              tokenService: tokenService,
              deviceId: await serverDeviceId,
              transportConfig: transportConfig,
            ).build(
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
