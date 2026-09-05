import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/async/serialized_async_executor.dart';
import '../../core/feature_flags.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../core/security/transport_config.dart';
import '../../l10n/app_strings.dart';
import '../../services/miucam_server.dart';
import '../../services/configuration_service.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/discovery/miucam_discovery_identity.dart';
import '../../services/discovery/miucam_service_discovery.dart';
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
      bool broadcastPaywallEnabled = MiuCamFeatureFlags.broadcastPaywallEnabled,
      TransportConfig transportConfig = TransportConfig.local,
      Duration mediaOperationTimeout = const Duration(seconds: 8)}) {
    createCount++;
    final tokenService = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        config.preferences,
      ),
    );
    final BroadcastAccessService? broadcastAccess = broadcastPaywallEnabled
        ? BroadcastAccessService(config.preferences)
        : null;
    final discoveryIdentity =
        PersistentMiuCamDiscoveryIdentity(config.preferences);
    final serverDeviceId = discoveryIdentity.getOrCreate();
    final webRtcGateway = FlutterWebRtcServerGateway(onLog: onLog);
    void Function()? notifyMediaProfileChanged;
    void Function()? notifyBroadcastAccessChanged;
    const platformContract = PlatformRuntimeContract();
    var nativeMediaDemand = MediaResourceDemand.none;
    var nativePlaybackDemand = false;
    final nativeDemandOperations = SerializedAsyncExecutor();

    Future<void> publishNativeDemand() {
      return nativeDemandOperations.run(() async {
        final demand = nativeMediaDemand;
        final playback = nativePlaybackDemand;
        try {
          await platformContract
              .setMediaDemand(
                active: !demand.isEmpty || playback,
                camera: demand.video,
                microphone: demand.audio,
                playback: playback,
                nativeCameraCapture: demand.serviceVideoCapture,
                nativeMicrophoneCapture: demand.serviceAudioCapture,
              )
              .timeout(mediaOperationTimeout);
        } catch (_) {
          // Unsupported/test targets intentionally have no native channel.
        }
      });
    }

    Future<void> publishRuntimeDemand(MediaResourceDemand demand) {
      nativeMediaDemand = demand;
      return publishNativeDemand();
    }

    Future<void> publishPlaybackDemand(bool active) {
      nativePlaybackDemand = active;
      return publishNativeDemand();
    }

    Future<void> stopServerRuntime(MiuCamServer server) async {
      try {
        await server.dispose();
      } finally {
        tokenService.dispose();
        // Media demand may already be empty. Release the independent HTTP/WS
        // host lease only after the Dart server has closed its sockets.
        await platformContract.setServerDemand(active: false);
      }
    }

    final nativeMediaSource = defaultTargetPlatform == TargetPlatform.android &&
            startMediaOverride == null
        ? AndroidServiceMediaSource(
            jpegQuality: 68,
            maxVideoFps: 8,
            nativeOperationTimeout: mediaOperationTimeout,
          )
        : null;
    late final ServerRuntime runtime;
    final server = MiuCamServer(
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
        audioAnalysisDemand: () => runtime.currentState.cryAnalyzerActive,
        videoAnalysisDemand: () => runtime.currentState.motionAnalyzerActive,
        onPlaybackDemandChanged: publishPlaybackDemand,
        tokenService: tokenService,
        transportConfig: transportConfig,
        broadcastAccess: broadcastAccess,
        mediaSource: nativeMediaSource,
        serverDeviceIdProvider: () => serverDeviceId,
        serviceAdvertiser: MiuCamServiceAdvertiser(
          deviceIdProvider: () => serverDeviceId,
        ),
        webRtcGateway: webRtcGateway,
        mediaLifecycleOperationTimeout: mediaOperationTimeout,
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
            operationTimeout: mediaOperationTimeout,
          )
        : MediaRuntimeController(
            onStart: startMediaOverride,
            onStop: server.stopMediaRuntime,
            operationTimeout: mediaOperationTimeout,
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
      mediaOperationTimeout: mediaOperationTimeout,
      platformLifecycle: platformLifecycle,
      previewSource: () => nativeMediaSource ?? server.cameraController,
      mediaProfile: () => server.activeMediaProfile,
      onSettingsChanged: server.reloadAnalysisConfig,
      broadcastAccess: broadcastAccess,
      broadcastAccessChanges: broadcastAccess?.changes,
      onMediaDemandChanged: publishRuntimeDemand,
      onVideoEncodingDemandChanged: nativeMediaSource == null
          ? null
          : (enabled) async {
              try {
                await nativeMediaSource.setVideoEncodingDemand(enabled);
              } catch (error) {
                // Capture ownership and alert analysis remain functional if a
                // stale platform channel rejects this optimization update.
                onLog?.call('Native JPEG demand could not be updated: $error');
              }
            },
      onPauseExternalMedia: server.pauseExternalMediaForPlatform,
      onRecoverExternalMedia: server.recoverExternalMediaForPlatform,
      trustedClients: () => server.trustedClients,
      trustedClientsChanged: server.trustedClientsChanged,
      activeWatchClientIds: () => server.activeWatchClientIds,
      isPairingNonceActive: tokenService.isPairingNonceActive,
      onRenameTrustedClient: server.renameTrustedClient,
      maxTrustedClients: tokenService.maxTrustedClients,
      maxActiveWatchClients: server.maxActiveWatchClients,
      onRevokeTrustedClient: server.revokeTrustedClient,
      onRevokeAllTrustedClients: server.revokeAllTrustedClients,
      onStartPairing: startPairingOverride ??
          () async {
            // Publish server ownership before advertising. Android acquires its
            // host lease; iOS combines this with microphone demand when
            // reporting whether background service can actually continue.
            await platformContract.setServerDemand(active: true);
            try {
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
            } catch (_) {
              await platformContract.setServerDemand(active: false);
              rethrow;
            }
          },
      onStopPairing: startPairingOverride == null
          ? () async => server.stopPairingMode()
          : null,
      onStop: stopOverride ?? () => stopServerRuntime(server),
    );
    notifyMediaProfileChanged = runtime.refreshMediaProfile;
    notifyBroadcastAccessChanged =
        () => unawaited(runtime.refreshBroadcastAccess());
    unawaited(runtime.refreshBroadcastAccess());
    return runtime;
  }

  static String buildQrUri(PairingPayload payload) => payload.toUriString();
}
