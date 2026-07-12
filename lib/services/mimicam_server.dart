import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../analysis/alert/alert_config.dart';
import '../analysis/alert/alert_engine.dart';
import '../analysis/alert/alert_event.dart';
import '../analysis/alert/alert_severity.dart';
import '../analysis/alert/alert_type.dart';
import '../analysis/alert/episode_notification_aggregator.dart';
import '../analysis/audio/audio_analysis_result.dart';
import '../analysis/audio/audio_analysis_config.dart';
import '../analysis/audio/audio_chunk.dart';
import '../analysis/audio/cry_audio_analyzer_v2.dart';
import '../analysis/video/motion_analysis_result.dart';
import '../analysis/video/luma_frame.dart';
import '../analysis/video/motion_analysis_config.dart';
import '../analysis/video/motion_analyzer_v2.dart';
import '../core/media/camera_permission_gateway.dart';
import '../core/media/adaptive_media_profile.dart';
import '../core/media/client_quality_tracker.dart';
import '../core/media/media_session_telemetry.dart';
import '../core/mimicam_protocol.dart';
import '../core/network/local_network_guard.dart';
import '../core/protocol/device_feature_models.dart';
import '../core/protocol/mimicam_protocol.dart' as protocol_v2;
import '../core/protocol/webrtc_signaling.dart';
import '../core/security/transport_config.dart';
import '../features/server/pairing/pairing_token_service.dart';
import '../features/server/media/mjpeg_stream_service.dart';
import '../features/server/media/microphone_capture_service.dart';
import '../features/server/media/server_media_source.dart';
import '../features/server/media/wav_audio_stream_service.dart';
import '../features/server/media/webrtc/webrtc_server_gateway.dart';
import '../l10n/app_strings.dart';
import 'configuration_service.dart';
import 'monetization/broadcast_access_service.dart';
import 'discovery/mimicam_service_discovery.dart';
import 'server/active_client_registry.dart';
import 'server/alert_protocol_adapter.dart';
import 'server/baby_monitor_feature_services.dart';
import 'server/baby_monitor_feature_controller.dart';
import 'server/best_effort_operation_collector.dart';
import 'server/camera_jpeg_worker.dart';
import 'server/jpeg_byte_budget_controller.dart';
import 'server/media_analysis_coordinator.dart';
import 'server/media_frame_policy.dart';
import 'server/media_analysis_metrics.dart';
import 'server/media_profile_apply_queue.dart';
import 'server/media_quality_selector.dart';
import 'server/media_resource_governor.dart';
import 'server/pcm16_frame_assembler.dart';
import 'server/request_auth_guard.dart';
import 'server/room_audio_coordinator.dart';
import 'server/server_device_identity_resolver.dart';
import 'server/server_resource_policy_coordinator.dart';
import 'server/server_session_operation_queue.dart';
import 'server/stream_backpressure_gate.dart';
import 'server/test_dashboard_assets.dart';
import 'server/wav_pcm16.dart';
import 'platform/device_capability_probe.dart';
import 'platform/battery_snapshot_provider.dart';
import 'platform/foreground_service_controller.dart';
import 'platform/device_resource_snapshot_provider.dart';
import 'network_address_provider.dart';

part 'server/mimicam_server_test_endpoints.dart';

class MimiCamServer {
  MimiCamServer({
    required this.config,
    required this.strings,
    required this.onLog,
    required this.onAlert,
    this.enableLegacyWebSocketMediaPackets = false,
    this.enableAudioAutoCalibration = true,
    this.onMediaProfileChanged,
    this.onStreamSessionStarted,
    this.onStreamSessionStopped,
    this.onWebRtcCaptureStarting,
    this.onWebRtcCaptureEnded,
    this.onAlertClientConnected,
    this.onAlertClientDisconnected,
    this.onPlaybackDemandChanged,
    DeviceCapabilityTier? deviceTier,
    PairingTokenService? tokenService,
    this.transportConfig = TransportConfig.local,
    this.localNetworkGuard = const LocalNetworkGuard(),
    this.maxActiveWatchClients = 5,
    this.startMediaOnSessionStart = true,
    this.mediaSource,
    MediaPermissionGateway? mediaPermissions,
    this.httpPort = MimiCamProtocol.httpPort,
    ComfortAudioService? comfortAudioService,
    NightLightController? nightLightController,
    TalkSessionRegistry? talkSessions,
    BabyMonitorFeatureController? featureController,
    MimiCamServiceAdvertiser? serviceAdvertiser,
    MimiCamDiscoveryDeviceIdProvider? serverDeviceIdProvider,
    BatterySnapshotProvider? batteryProvider,
    BroadcastAccessService? broadcastAccess,
    DeviceResourceSnapshotProvider? deviceResourceProvider,
    MediaResourceGovernor? mediaResourceGovernor,
    MediaSessionTelemetry? mediaTelemetry,
    this.webRtcGateway,
    this.onBroadcastAccessChanged,
  })  : tokenService = tokenService ?? PairingTokenService(),
        mediaPermissions =
            mediaPermissions ?? const CameraMediaPermissionGateway(),
        _features = featureController ??
            BabyMonitorFeatureController(
              comfortAudio: comfortAudioService,
              nightLight: nightLightController,
              talkSessions: talkSessions,
            ),
        _serviceAdvertiser = serviceAdvertiser,
        _serverDeviceIdentityResolver = ServerDeviceIdentityResolver(
          serverDeviceIdProvider ?? (() => 'server_local'),
        ),
        _batteryProvider = CachedBatterySnapshotProvider(
          batteryProvider ?? BatteryPlusSnapshotProvider(),
        ),
        _broadcastAccess = broadcastAccess,
        _deviceResourceProvider = CachedDeviceResourceSnapshotProvider(
          deviceResourceProvider ??
              const MethodChannelDeviceResourceSnapshotProvider(),
        ),
        _mediaTelemetry = mediaTelemetry ?? MediaSessionTelemetry.shared,
        _deviceTier = deviceTier ?? DeviceCapabilityProbe.detectTier() {
    _activeMediaProfile = MediaQualityProfile.forDeviceTier(_deviceTier);
    _effectiveLocalNetworkGuard = localNetworkGuard;
    _frameBudget.updateMinInterval(_activeMediaProfile.frameInterval);
    _activeClientRegistry = ActiveClientRegistry(
      tokenService: this.tokenService,
      maxActiveClients: maxActiveWatchClients,
    );
    _authGuard = RequestAuthGuard(tokenService: this.tokenService);
    _resourcePolicyCoordinator = ServerResourcePolicyCoordinator(
      governor: mediaResourceGovernor ?? const MediaResourceGovernor(),
      monitoringRequired: _isResourceMonitoringRequired,
      refreshProfile: _refreshResourceProfile,
      onMonitoringIdle: () {
        _resourcePolicyCoordinator.resetDecision();
        _resourceDecision = MediaResourceGovernorDecision.normal;
      },
      onWatchdogError: (error) {
        onLog('Resource watchdog could not apply a profile: $error');
      },
    );
    _videoStreamService = MjpegStreamService(
      onClientDetached: _activeClientRegistry.detachStream,
      telemetry: _mediaTelemetry,
    );
    _audioStreamService = WavAudioStreamService(
      sampleRate: _audioSampleRate,
      channels: _audioChannels,
      bitsPerSample: _audioBitsPerSample,
      onClientDetached: _activeClientRegistry.detachStream,
      telemetry: _mediaTelemetry,
    );
    final routes = _buildRoutes();
    _routeTable = Map<String, _RouteSpec>.unmodifiable({
      for (final route in routes) route.path: route,
    });
    if (_routeTable.length != routes.length) {
      throw StateError('Duplicate MimiCam HTTP route path.');
    }
    final peerLifecycle = webRtcGateway;
    if (peerLifecycle is WebRtcPeerLifecycleSource) {
      _webRtcPeerSubscription =
          (peerLifecycle as WebRtcPeerLifecycleSource).peerEvents.listen(
        _handleWebRtcPeerLifecycleEvent,
        onError: (Object error, StackTrace _) {
          onLog('WebRTC peer lifecycle stream failed: $error');
        },
      );
    }
    _features.roomAudio.bindOutputDemandCallback(onPlaybackDemandChanged);
    _roomAudioModeSubscription = _features.roomAudio.modeChanges.listen(
      _handleRoomAudioModeChanged,
      onError: (Object error, StackTrace _) {
        onLog('Room audio lifecycle stream failed: $error');
      },
    );
    final injectedLumaSource = mediaSource;
    if (injectedLumaSource case ServerLumaFrameSource lumaSource) {
      _injectedLumaSubscription = lumaSource.lumaFrames.listen(
        _handleInjectedLumaFrame,
        onError: (Object error, StackTrace _) {
          onLog('Native luma analysis stream failed: $error');
        },
      );
    }
  }

  final bool enableLegacyWebSocketMediaPackets;
  final bool enableAudioAutoCalibration;

  final ConfigurationService config;
  final AppStrings strings;
  final void Function(String message) onLog;
  final void Function(String message) onAlert;
  final void Function(MediaQualityProfile profile)? onMediaProfileChanged;
  final void Function(BroadcastAccessSnapshot snapshot)?
      onBroadcastAccessChanged;
  final FutureOr<void> Function(
    String clientId, {
    required bool video,
    required bool audio,
    required String mediaTransport,
  })? onStreamSessionStarted;
  final FutureOr<void> Function(String clientId)? onStreamSessionStopped;
  final FutureOr<void> Function(String clientId)? onWebRtcCaptureStarting;
  final FutureOr<void> Function(String clientId)? onWebRtcCaptureEnded;
  final FutureOr<void> Function(String clientId)? onAlertClientConnected;
  final FutureOr<void> Function(String clientId)? onAlertClientDisconnected;
  final FutureOr<void> Function(bool active)? onPlaybackDemandChanged;
  final PairingTokenService tokenService;
  final MediaPermissionGateway mediaPermissions;
  final TransportConfig transportConfig;
  final LocalNetworkGuard localNetworkGuard;
  late LocalNetworkGuard _effectiveLocalNetworkGuard;
  final int maxActiveWatchClients;
  final bool startMediaOnSessionStart;
  final ServerMediaSource? mediaSource;
  final int httpPort;
  final WebRtcServerGateway? webRtcGateway;
  MediaAnalysisCoordinator? _analysisCoordinator;
  MediaAnalysisMetrics? _analysisMetrics;
  StreamSubscription<AlertEvent>? _alertSubscription;
  StreamSubscription<WebRtcPeerLifecycleEvent>? _webRtcPeerSubscription;
  StreamSubscription<RoomAudioMode>? _roomAudioModeSubscription;
  StreamSubscription<LumaFrame>? _injectedLumaSubscription;
  final _webSockets = <WebSocket>{};
  final _webSocketClientIds = <WebSocket, String>{};
  final _eventClientSocketCounts = <String, int>{};
  late final ActiveClientRegistry _activeClientRegistry;
  late final RequestAuthGuard _authGuard;
  final _microphoneCapture = MicrophoneCaptureService(
    sampleRate: _audioSampleRate,
    channels: _audioChannels,
  );
  final BabyMonitorFeatureController _features;
  final MimiCamServiceAdvertiser? _serviceAdvertiser;
  final ServerDeviceIdentityResolver _serverDeviceIdentityResolver;
  final BatterySnapshotProvider _batteryProvider;
  final BroadcastAccessService? _broadcastAccess;
  final DeviceResourceSnapshotProvider _deviceResourceProvider;
  late final ServerResourcePolicyCoordinator _resourcePolicyCoordinator;
  final MediaSessionTelemetry _mediaTelemetry;
  Timer? _broadcastAccessTimer;
  int _broadcastAccessTimerGeneration = 0;
  BatterySnapshot _serverBattery = BatterySnapshot.unknown();
  final _clientBatterySnapshots = <String, BatterySnapshot>{};
  late final MjpegStreamService _videoStreamService;
  late final WavAudioStreamService _audioStreamService;
  late final Map<String, _RouteSpec> _routeTable;
  final _sessionOperations = ServerSessionOperationQueue();

  CameraController? cameraController;
  DeviceCapabilityTier get deviceTier => _deviceTier;
  MediaQualityProfile get activeMediaProfile => _activeMediaProfile;
  Map<String, Object?> get mediaCapabilities => _mediaCapabilities();
  Future<String> get serverDeviceId => _serverDeviceIdentityResolver.resolve();

  Future<void> handleAudioOutputLost(String reason) async {
    await _features.handleAudioOutputLost(reason);
    _updateResourceWatchdog();
  }

  HttpServer? _httpServer;
  Future<String>? _pairingStartOperation;
  bool _httpServerListening = false;
  bool _pairingModeActive = false;
  bool _disposed = false;
  bool _wakelockEnabled = false;
  Future<void>? _mediaStart;
  bool _videoCaptureDesired = false;
  final _standaloneSessionDemands = <String, ({bool video, bool audio})>{};
  final _sessionMediaDemands = <String, ({bool video, bool audio})>{};
  final _sessionMediaTransports = <String, String>{};
  final _runtimeSessionClients = <String>{};
  Uint8List? _latestJpeg;
  int? _lastCameraFrameAtMs;
  int? _lastVideoFrameEncodedAtMs;
  int? _lastAlertBroadcastAtMs;
  int? _videoProbeEncodeUntilMs;
  int _videoFramesEncoded = 0;
  int _videoFramesDroppedBeforeEncode = 0;
  int _videoFramesSkippedByPolicy = 0;
  int _videoFramesCaptured = 0;
  int _videoTraceSequence = 0;
  bool _jpegEncodeInFlight = false;
  _CameraEncodeRequest? _pendingCameraEncode;
  int _cameraEncodeGeneration = 0;
  int _alertsBroadcast = 0;
  int _alertWebSocketDeliveries = 0;
  int _lastJpegBytes = 0;
  int _lastAlertDeliveredWebSocketClients = 0;
  int _lastAudioDebugLog = 0;
  int _selfAudioSuppressedChunks = 0;
  final _frameBudget = MediaFrameBudget();
  final _frameBudgetManager = const FrameBudgetManager();
  final _encodingPolicy = const MediaEncodingPolicy();
  final _jpegByteBudgetController = JpegByteBudgetController();
  final _cameraJpegWorker = CameraJpegWorker();
  final _mediaQualitySelector = MediaQualitySelector();
  final _mediaProfileApplyQueue = MediaProfileApplyQueue();
  final _mediaProfileCameraRestartPolicy =
      const MediaProfileCameraRestartPolicy();
  final DeviceCapabilityTier _deviceTier;
  late MediaQualityProfile _activeMediaProfile;
  int _mediaProfileApplyFailureCount = 0;
  Object? _lastMediaProfileApplyError;
  int? _lastMediaProfileApplyErrorAtMs;
  DeviceResourceSnapshot _deviceResources = DeviceResourceSnapshot.unknown();
  MediaResourceGovernorDecision _resourceDecision =
      MediaResourceGovernorDecision.normal;
  Uint8List? _lastMotionSample;
  double _lastMotionEnergy = 0;
  bool _cryActive = false;
  int? _lastCryActiveAtMs;
  static const _audioSampleRate = 16000;
  static const _audioChannels = 1;
  static const _audioBitsPerSample = 16;

  Future<String> start() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    final address = await startPairingMode();
    await startMediaRuntime();
    return address;
  }

  Future<String> startPairingMode() {
    final active = _pairingStartOperation;
    if (active != null) return active;
    late final Future<String> operation;
    operation = _startPairingMode().whenComplete(() {
      if (identical(_pairingStartOperation, operation)) {
        _pairingStartOperation = null;
      }
    });
    _pairingStartOperation = operation;
    return operation;
  }

  Future<String> _startPairingMode() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    if (config.webRtcPilotEnabled) {
      await webRtcGateway?.initialize();
    }
    if (_httpServer == null) {
      late final HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv6,
          httpPort,
          shared: true,
          v6Only: false,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          httpPort,
          shared: true,
        );
      }
      if (_disposed) {
        await server.close(force: true);
        throw StateError('MimiCamServer is disposed.');
      }
      _httpServer = server;
    }
    final boundType = _httpServer!.address.type == InternetAddressType.IPv4
        ? InternetAddressType.IPv4
        : InternetAddressType.any;
    final endpoint = await NetworkAddressProvider.localEndpoint(
      port: _httpServer!.port,
      type: boundType,
    );
    final host = endpoint?.host ??
        (boundType == InternetAddressType.IPv4
            ? InternetAddress.loopbackIPv4.address
            : InternetAddress.loopbackIPv6.address);
    try {
      final prefixes = await NetworkAddressProvider.localIpv6Prefixes();
      _effectiveLocalNetworkGuard = LocalNetworkGuard(
        allowLoopback: localNetworkGuard.allowLoopback,
        allowGlobalIpv6WithoutPrefixContext:
            localNetworkGuard.allowGlobalIpv6WithoutPrefixContext,
        localPrefixes: [
          ...localNetworkGuard.localPrefixes,
          ...prefixes,
        ],
      );
    } catch (error) {
      onLog('Local IPv6 prefix context could not be loaded: $error');
    }
    if (!_httpServerListening) {
      _httpServerListening = true;
      _httpServer!.listen(_handleRequest);
    }
    _pairingModeActive = true;
    final deviceId = await _serverDeviceIdentityResolver.resolve();
    final serviceAdvertiser = _serviceAdvertiser;
    if (serviceAdvertiser != null) {
      try {
        await serviceAdvertiser.start(
          name: 'MimiCam Bebek Odası',
          deviceId: deviceId,
          port: _httpServer!.port,
          protocolVersion: protocol_v2.MimiCamProtocolV2.schemaVersion,
          webRtcAvailable:
              config.webRtcPilotEnabled && webRtcGateway?.isAvailable == true,
        );
      } catch (error) {
        onLog('Bonjour/NSD servisi yayınlanamadı: $error');
      }
    }
    final url = Uri(
      scheme: transportConfig.httpScheme,
      host: host,
      port: _httpServer!.port,
      path: '/',
    ).toString();
    onLog(strings.serverStartedLog(url));
    return url;
  }

  Future<void> stopPairingMode() async {
    final starting = _pairingStartOperation;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // A failed start has no advertisement to stop.
      }
    }
    _pairingModeActive = false;
    try {
      await _serviceAdvertiser?.stop();
    } catch (error) {
      onLog('Bonjour/NSD servisi durdurulamadı: $error');
    }
  }

  Future<void> startMediaRuntime() async {
    await startVideoRuntime();
    await startAudioRuntime();
  }

  Future<void> startVideoRuntime() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    _videoCaptureDesired = true;
    final source = mediaSource;
    if (source != null) {
      await _reconcileInjectedMediaSource(source, video: true);
      return;
    }
    final existingController = cameraController;
    if (existingController != null) {
      if (existingController.value.isInitialized) return;
      await existingController.dispose();
      if (cameraController == existingController) cameraController = null;
    }
    final existingStart = _mediaStart;
    if (existingStart != null) return existingStart;

    final start = _startVideoCaptureRuntime();
    _mediaStart = start;
    try {
      await start;
    } catch (_) {
      _videoCaptureDesired = false;
      rethrow;
    } finally {
      if (_mediaStart == start) _mediaStart = null;
    }
  }

  Future<void> startAudioRuntime() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    final source = mediaSource;
    if (source != null) {
      await _reconcileInjectedMediaSource(source, audio: true);
      return;
    }
    _initializeAnalysisPipeline();
    try {
      final started = await _startAudioAnalysis();
      if (!started) throw StateError(strings.microphonePermissionMissing);
      await _updateMediaHostLifecycle();
    } catch (error) {
      _analysisMetrics?.recordAudioError();
      await _microphoneCapture.stop();
      onLog('Ses başlatılamadı: $error');
      rethrow;
    }
  }

  Future<void> _startVideoCaptureRuntime() async {
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    await _ensureCameraPermission();
    final cameras = await availableCameras();
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    _initializeAnalysisPipeline();

    final controller = CameraController(
      cameras.first,
      _resolutionPresetFor(_activeMediaProfile),
      enableAudio: false,
      fps: max(
        1,
        _mediaProfileCameraRestartPolicy.captureFps(
          deviceProfile: MediaQualityProfile.forDeviceTier(_deviceTier),
          activeProfile: _activeMediaProfile,
        ),
      ),
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    cameraController = controller;
    try {
      await controller.initialize();
      if (_disposed) {
        throw StateError('MimiCamServer is disposed.');
      }
      await controller.startImageStream(_handleCameraFrame);
      await _updateMediaHostLifecycle();
    } catch (_) {
      await stopVideoRuntime();
      rethrow;
    }
  }

  bool _injectedVideoDemand = false;
  bool _injectedAudioDemand = false;
  Future<void> _injectedMediaTail = Future<void>.value();

  Future<void> _reconcileInjectedMediaSource(
    ServerMediaSource source, {
    bool? video,
    bool? audio,
  }) {
    if (video != null) _injectedVideoDemand = video;
    if (audio != null) _injectedAudioDemand = audio;
    final operation = _injectedMediaTail.then<void>(
      (_) => _applyInjectedMediaDemand(source),
      onError: (_) => _applyInjectedMediaDemand(source),
    );
    _injectedMediaTail = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> _applyInjectedMediaDemand(ServerMediaSource source) async {
    if (_injectedVideoDemand || _injectedAudioDemand) {
      _initializeAnalysisPipeline();
    }
    await source.reconcile(
      video: _injectedVideoDemand,
      audio: _injectedAudioDemand,
      onVideoFrame: _handleInjectedVideoFrame,
      onAudioChunk: _handleInjectedAudioChunk,
      onError: (error, _) {
        _analysisMetrics?.recordAudioError();
        onLog('Test medya kaynağı hata verdi: $error');
      },
    );
    await _updateMediaHostLifecycle();
    await _disposeAnalysisIfIdle();
  }

  void _initializeAnalysisPipeline() {
    if (_analysisCoordinator != null) return;
    final motionConfig = MotionAnalysisConfig(
      motionOnThreshold: config.motionThreshold,
      minMotionDurationMs: config.motionMinDurationMs,
    );
    final audioConfig = AudioAnalysisConfig(
      sampleRate: _audioSampleRate,
      cryOnThreshold: config.cryScoreThreshold,
      minCryDurationMs: config.cryMinDurationMs,
    );
    final alertConfig = AlertConfig(
      cryCooldownMs: config.notifyCooldownMs,
      motionCooldownMs: config.notifyCooldownMs,
      cryAlertThreshold: config.cryScoreThreshold,
      motionAlertThreshold: config.motionThreshold,
    );
    final audioAnalyzer = CryAudioAnalyzerV2(config: audioConfig);
    if (enableAudioAutoCalibration) {
      audioAnalyzer.startCalibration(
          timestampMs: DateTime.now().millisecondsSinceEpoch);
    }
    final metrics =
        MediaAnalysisMetrics(motionTargetFps: motionConfig.analysisFps);
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(config: motionConfig),
      audioAnalyzer: audioAnalyzer,
      alertEngine: AlertEngine(
        config: alertConfig,
        strings: strings,
        episodeAggregator: EpisodeBasedNotificationAggregator(),
        networkTierProvider: _activeClientRegistry.effectiveTier,
        audioReliableProvider: _isAudioReliable,
        videoReliableProvider: _isVideoReliable,
      ),
      metrics: metrics,
      onLog: onLog,
      onAudioResult: _handleAudioAnalysisResult,
      onMotionResult: _handleMotionAnalysisResult,
    );
    _analysisMetrics = metrics;
    _analysisCoordinator = coordinator;
    _alertSubscription = coordinator.alerts.listen(_handleAlertEvent);
  }

  Future<void> reloadAnalysisConfig() async {
    if (cameraController == null &&
        !_microphoneCapture.isActive &&
        mediaSource?.isActive != true) {
      return;
    }
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    _initializeAnalysisPipeline();
  }

  Future<bool> _startAudioAnalysis() async {
    final started = await _microphoneCapture.start(
      onChunk: (chunk) {
        _mediaTelemetry.increment(MediaMetricName.audioCapturedCount);
        if (_features.roomAudio.mode == RoomAudioMode.idle) {
          _analysisCoordinator?.onAudioChunk(AudioChunk(
            pcm16le: chunk.rawPcm16le,
            sampleRate: chunk.sampleRate,
            channels: chunk.channels,
            timestampMs: chunk.timestampMs,
          ));
        } else {
          // Do not classify room-generated comfort/talk output as a cry.
          _selfAudioSuppressedChunks++;
        }
        if (enableLegacyWebSocketMediaPackets) {
          _broadcastBinary(
              [MimiCamProtocol.packetAudioPcm16Le, ...chunk.streamPcm16le]);
        }
        _audioStreamService.broadcast(chunk.streamPcm16le);
        _logAudioDiagnostics();
      },
      onError: (error, _) {
        _analysisMetrics?.recordAudioError();
        onLog('Ses akışında hata: $error');
      },
    );
    if (!started) {
      onLog(strings.microphonePermissionMissing);
    }
    return started;
  }

  void _logAudioDiagnostics() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAudioDebugLog <= 5000) return;
    _lastAudioDebugLog = now;
    final audio = _analysisMetrics?.toJson()['audio'];
    if (audio != null) onLog(strings.audioAnalysisLog(audio.toString()));
  }

  void _handleAlertEvent(AlertEvent event) {
    _analysisMetrics?.recordAlert(event);
    final message = event.message;
    onLog(message);
    onAlert(message);
    _alertsBroadcast++;
    _lastAlertBroadcastAtMs = event.timestampMs;
    _lastAlertDeliveredWebSocketClients =
        _broadcastText(AlertProtocolAdapter.toJsonText(event));
    _alertWebSocketDeliveries += _lastAlertDeliveredWebSocketClients;
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary(AlertProtocolAdapter.toLegacyAlertPacket(event));
    }
  }

  void _handleCameraFrame(CameraImage frame) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final capturedAtMonoUs = _mediaTelemetry.nowUs;
    _videoFramesCaptured++;
    _mediaTelemetry.increment(MediaMetricName.videoCapturedCount);
    _lastCameraFrameAtMs = nowMs;
    _lastMotionEnergy = _estimateMotionEnergy(frame);
    _updateContentAwareFrameBudget(nowMs);
    if (!_frameBudget.shouldProcess(nowMs)) return;

    try {
      _analysisCoordinator?.onCameraFrame(_toLumaFrame(frame, nowMs));
      final shouldEncodeJpeg = _encodingPolicy.shouldEncodeJpeg(
        hasMjpegClients:
            _videoStreamService.hasClients || _isVideoProbeActive(nowMs),
        legacyWebSocketEnabled: enableLegacyWebSocketMediaPackets,
      );
      if (!shouldEncodeJpeg) return;
      _offerCameraFrameForEncoding(_CameraEncodeRequest(
        frame: TransferableCameraFrame.capture(frame),
        profile: _activeMediaProfile,
        capturedAtMs: nowMs,
        capturedAtMonoUs: capturedAtMonoUs,
        traceId: '${_mediaTelemetry.generation}-${++_videoTraceSequence}',
        generation: _cameraEncodeGeneration,
      ));
    } catch (error) {
      onLog('Frame işlenemedi: $error');
    }
  }

  void _offerCameraFrameForEncoding(_CameraEncodeRequest request) {
    if (_jpegEncodeInFlight) {
      if (_pendingCameraEncode != null) {
        _videoFramesDroppedBeforeEncode++;
        _mediaTelemetry.increment(
          MediaMetricName.videoDroppedBeforeEncodeCount,
        );
      }
      _pendingCameraEncode = request;
      return;
    }
    _jpegEncodeInFlight = true;
    unawaited(_encodeCameraFrames(request));
  }

  Future<void> _encodeCameraFrames(_CameraEncodeRequest first) async {
    var current = first;
    try {
      while (!_disposed && current.generation == _cameraEncodeGeneration) {
        final encodeStartedAtUs = _mediaTelemetry.nowUs;
        final quality = _jpegByteBudgetController.qualityFor(current.profile);
        final jpeg = await _cameraJpegWorker.encode(
          current.frame,
          quality: quality,
          targetWidth: current.profile.width,
          targetHeight: current.profile.height,
        );
        if (_disposed || current.generation != _cameraEncodeGeneration) return;
        final encodedAtMonoUs = _mediaTelemetry.nowUs;
        final encodeDurationUs = encodedAtMonoUs - encodeStartedAtUs;
        _mediaTelemetry.recordDurationUs(
          MediaMetricName.videoEncode,
          encodeDurationUs,
        );
        _mediaTelemetry.recordDurationUs(
          MediaMetricName.videoCaptureToEncode,
          encodedAtMonoUs - current.capturedAtMonoUs,
        );
        _mediaTelemetry.increment(MediaMetricName.videoEncodedCount);
        _jpegByteBudgetController.recordEncodedFrame(
          current.profile,
          byteLength: jpeg.length,
          atMs: current.capturedAtMs,
        );
        _latestJpeg = jpeg;
        _lastVideoFrameEncodedAtMs = DateTime.now().millisecondsSinceEpoch;
        _lastJpegBytes = jpeg.length;
        _videoFramesEncoded++;
        if (enableLegacyWebSocketMediaPackets) {
          _broadcastBinary([MimiCamProtocol.packetVideoMjpeg, ...jpeg]);
        }
        _videoStreamService.broadcast(
          jpeg,
          capturedAtMs: current.capturedAtMs,
          capturedAtMonoUs: current.capturedAtMonoUs,
          encodeDurationUs: encodeDurationUs,
          traceId: current.traceId,
        );
        final next = _pendingCameraEncode;
        _pendingCameraEncode = null;
        if (next == null) break;
        current = next;
      }
    } catch (error) {
      onLog('Frame encode edilemedi: $error');
    } finally {
      _jpegEncodeInFlight = false;
      final pending = _pendingCameraEncode;
      _pendingCameraEncode = null;
      if (pending != null &&
          !_disposed &&
          pending.generation == _cameraEncodeGeneration) {
        _offerCameraFrameForEncoding(pending);
      }
    }
  }

  void _handleInjectedVideoFrame(Uint8List jpeg) {
    if (jpeg.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final capturedAtMonoUs = _mediaTelemetry.nowUs;
    final traceId = '${_mediaTelemetry.generation}-${++_videoTraceSequence}';
    _videoFramesCaptured++;
    _mediaTelemetry.increment(MediaMetricName.videoCapturedCount);
    _lastCameraFrameAtMs = nowMs;
    _updateContentAwareFrameBudget(nowMs);
    if (!_frameBudget.shouldProcess(nowMs)) {
      // Native service frames arrive as already encoded JPEG. This is an
      // intentional transport/profile skip, not encoder overload.
      _videoFramesSkippedByPolicy++;
      return;
    }
    _mediaTelemetry
      ..increment(MediaMetricName.videoEncodedCount)
      ..recordDurationUs(MediaMetricName.videoEncode, 0);
    _latestJpeg = jpeg;
    _lastVideoFrameEncodedAtMs = nowMs;
    _lastJpegBytes = jpeg.length;
    _videoFramesEncoded++;
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary([MimiCamProtocol.packetVideoMjpeg, ...jpeg]);
    }
    _videoStreamService.broadcast(
      jpeg,
      capturedAtMs: nowMs,
      capturedAtMonoUs: capturedAtMonoUs,
      encodeDurationUs: 0,
      traceId: traceId,
    );
  }

  void _handleInjectedLumaFrame(LumaFrame frame) {
    if (!_injectedVideoDemand) return;
    _analysisCoordinator?.onCameraFrame(frame);
  }

  void _handleInjectedAudioChunk(Uint8List pcm16le) {
    if (pcm16le.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _mediaTelemetry.increment(MediaMetricName.audioCapturedCount);
    if (_features.roomAudio.mode == RoomAudioMode.idle) {
      _analysisCoordinator?.onAudioChunk(AudioChunk(
        pcm16le: pcm16le,
        sampleRate: _audioSampleRate,
        channels: _audioChannels,
        timestampMs: nowMs,
      ));
    } else {
      // Android's service-owned microphone can hear AudioTrack output just as
      // the Dart recorder can. Never classify comfort/talk loopback as a cry.
      _selfAudioSuppressedChunks++;
    }
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary([MimiCamProtocol.packetAudioPcm16Le, ...pcm16le]);
    }
    _audioStreamService.broadcast(pcm16le);
    _logAudioDiagnostics();
  }

  double _estimateMotionEnergy(CameraImage frame) {
    final bytes = frame.planes.first.bytes;
    if (bytes.isEmpty) return 0;
    const sampleCount = 96;
    final stride = max(1, bytes.length ~/ sampleCount);
    final sample = Uint8List(sampleCount);
    for (var index = 0; index < sampleCount; index++) {
      sample[index] = bytes[min(index * stride, bytes.length - 1)];
    }
    final previous = _lastMotionSample;
    _lastMotionSample = sample;
    if (previous == null || previous.length != sample.length) return 0;
    var diff = 0;
    for (var index = 0; index < sample.length; index++) {
      diff += (sample[index] - previous[index]).abs();
    }
    return diff / (sample.length * 255);
  }

  void _updateContentAwareFrameBudget(int nowMs) {
    if (_lastCryActiveAtMs != null && nowMs - _lastCryActiveAtMs! > 2500) {
      _cryActive = false;
    }
    final targetFps = min(
      _activeMediaProfile.targetFps,
      _frameBudgetManager.targetFps(
        motionEnergy: _lastMotionEnergy,
        cryActive: _cryActive,
        networkTier: _activeClientRegistry.effectiveTier(),
        activeClients: _activeClientRegistry.activeClientCount,
      ),
    );
    _frameBudget.updateMinInterval(
      Duration(milliseconds: (1000 / max(1, targetFps)).round()),
    );
  }

  void _handleAudioAnalysisResult(AudioAnalysisResult result) {
    final active = result.isCryLikely || result.cryScore > 0.4;
    if (active) {
      _cryActive = true;
      _lastCryActiveAtMs = result.timestampMs;
    } else if (_lastCryActiveAtMs != null &&
        result.timestampMs - _lastCryActiveAtMs! > 2500) {
      _cryActive = false;
    }
  }

  void _handleMotionAnalysisResult(MotionAnalysisResult result) {
    _lastMotionEnergy = result.meanDiff;
  }

  LumaFrame _toLumaFrame(CameraImage frame, int timestampMs) {
    final yPlane = frame.planes.first;
    return LumaFrame(
      yPlane: yPlane.bytes,
      width: frame.width,
      height: frame.height,
      rowStride: yPlane.bytesPerRow,
      pixelStride: yPlane.bytesPerPixel ?? 1,
      timestampMs: timestampMs,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (_disposed) {
        await request.response.close();
        return;
      }
      final remoteAddress = request.connectionInfo?.remoteAddress;
      // This is not a firewall; it reduces accidental public exposure if the
      // socket becomes reachable outside the local Wi-Fi network.
      if (remoteAddress != null &&
          !_effectiveLocalNetworkGuard.isAllowedRemoteAddress(remoteAddress)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      if ((request.uri.path == '/ws/stream' ||
              request.uri.path == protocol_v2.MimiCamProtocolV2.events) &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final eventClientId = _webSocketClientId(request);
        if (eventClientId == null) {
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _webSockets.add(socket);
        _webSocketClientIds[socket] = eventClientId;
        final previousCount = _eventClientSocketCounts[eventClientId] ?? 0;
        _eventClientSocketCounts[eventClientId] = previousCount + 1;
        if (previousCount == 0) {
          try {
            await onAlertClientConnected?.call(eventClientId);
          } catch (error) {
            _webSockets.remove(socket);
            _webSocketClientIds.remove(socket);
            _eventClientSocketCounts.remove(eventClientId);
            await socket.close();
            onLog('Alert media demand could not start: $error');
            return;
          }
        }
        unawaited(socket.done.whenComplete(() => _releaseWebSocket(socket)));
        onLog(strings.webSocketClientConnected(
            request.connectionInfo?.remoteAddress.address ?? 'unknown'));
        return;
      }
      if (request.uri.path == '/ws/stream' ||
          request.uri.path == protocol_v2.MimiCamProtocolV2.events) {
        request.response.statusCode = HttpStatus.upgradeRequired;
        await request.response.close();
        return;
      }

      final route = _routeFor(request.uri.path);
      if (route == null) {
        if (request.uri.path == '/') {
          await _writeLandingPage(request.response);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
        return;
      }
      if (!route.allowsMethod(request.method)) {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers
              .set(HttpHeaders.allowHeader, route.allowedMethods.join(', '));
        await request.response.close();
        return;
      }

      final auth = await _authorizeRoute(request, route.authMode);
      if (!auth.ok) return;
      await route.handle(request, auth.clientId);
    } catch (error) {
      onLog('HTTP isteği tamamlanamadı: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  List<_RouteSpec> _buildRoutes() => [
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.pairConfirm,
          _AuthMode.none,
          const {HttpMethod.post},
          (request, _) => _handlePairConfirm(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.authRenew,
          _AuthMode.none,
          const {HttpMethod.post},
          (request, _) => _handleAuthRenew(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.sessionStart,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleSessionStart(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.sessionStop,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleSessionStop(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.webRtcOffer,
          _AuthMode.bearer,
          const {HttpMethod.post},
          _handleWebRtcOffer,
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.webRtcIce,
          _AuthMode.bearer,
          const {HttpMethod.get, HttpMethod.post},
          _handleWebRtcIce,
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.webRtcClose,
          _AuthMode.bearer,
          const {HttpMethod.post},
          _handleWebRtcClose,
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.qualityReport,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleQualityReport(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.comfortState,
          _AuthMode.bearer,
          const {HttpMethod.get},
          (request, _) => _handleComfortState(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.comfortCommand,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleComfortCommand(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.nightLightState,
          _AuthMode.bearer,
          const {HttpMethod.get},
          (request, _) => _handleNightLightState(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.nightLightCommand,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleNightLightCommand(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.talkStart,
          _AuthMode.bearer,
          const {HttpMethod.post},
          _handleTalkStart,
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.talkStop,
          _AuthMode.bearer,
          const {HttpMethod.post},
          _handleTalkStop,
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.talkAudio,
          _AuthMode.none,
          const {HttpMethod.post},
          (request, _) => _handleTalkAudio(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.talkVideo,
          _AuthMode.none,
          const {HttpMethod.post},
          (request, _) => _handleTalkVideo(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.statusPublic,
          _AuthMode.none,
          const {HttpMethod.get},
          (request, _) => _handlePublicStatus(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testDashboard,
          _AuthMode.testAccess,
          const {HttpMethod.get},
          (request, _) => _writeTestDashboard(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testDashboardScript,
          _AuthMode.testAccess,
          const {HttpMethod.get},
          (request, _) => _writeTestDashboardScript(request),
        ),
        _RouteSpec(
          '/video',
          _AuthMode.streamToken,
          const {HttpMethod.get},
          _handleVideoRoute,
        ),
        _RouteSpec(
          '/audio',
          _AuthMode.streamToken,
          const {HttpMethod.get},
          _handleAudioRoute,
        ),
        _RouteSpec(
          '/status',
          _AuthMode.bearer,
          const {HttpMethod.get},
          (request, _) => _handlePrivateStatus(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testStatus,
          _AuthMode.bearer,
          const {HttpMethod.get},
          (request, _) => _handleTestStatus(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testStart,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleTestStart(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testReset,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleTestReset(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testProbe,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleTestProbe(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testAlert,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleTestAlert(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.testAudioTone,
          _AuthMode.bearer,
          const {HttpMethod.get},
          (request, _) => _handleTestAudioTone(request),
        ),
      ];

  _RouteSpec? _routeFor(String path) => _routeTable[path];

  Future<({bool ok, String? clientId})> _authorizeRoute(
    HttpRequest request,
    _AuthMode mode,
  ) async {
    switch (mode) {
      case _AuthMode.none:
        return (ok: true, clientId: null);
      case _AuthMode.bearer:
        final auth = await _requireTrustedAuth(request);
        return (ok: auth != null, clientId: auth?.clientId);
      case _AuthMode.testAccess:
        if (kDebugMode) return (ok: true, clientId: null);
        final auth = await _requireTrustedAuth(request);
        return (ok: auth != null, clientId: auth?.clientId);
      case _AuthMode.streamToken:
        // Stream tokens intentionally stop at media endpoints; state-changing
        // endpoints must still prove identity with the trusted Bearer token.
        final clientId = await _requireStreamAuth(request);
        return (ok: clientId != null, clientId: clientId);
    }
  }

  Future<void> _handlePublicStatus(HttpRequest request) async {
    if (!_pairingModeActive) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final pairingNonce = tokenService.createPairingNonce();
    final descriptorHost = _hostFromHeader(request.headers.host) ??
        _httpServer?.address.address ??
        InternetAddress.loopbackIPv4.address;
    final deviceId = await _serverDeviceIdentityResolver.resolve();
    await _writeJson(request.response, {
      'service': 'mimicam',
      'pairing': true,
      'serverDeviceId': deviceId,
      'serverName': 'Bebek Odası',
      'pairingNonce': pairingNonce,
      'transport': transportConfig.payloadTransport,
      'capabilities': _mediaCapabilities(),
      'discovery': {
        'dnsSd': _serviceAdvertiser?.isAdvertising == true,
        'serviceType': MimiCamDiscoveryConfig.serviceType,
        'host': descriptorHost,
        'port': _httpServer?.port ?? httpPort,
      },
    });
  }

  Future<void> _handlePrivateStatus(HttpRequest request) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final battery = await _refreshServerBattery();
    await _writeJson(request.response, {
      'videoClients': _videoStreamService.clientCount,
      'audioClients': _audioStreamService.clientCount,
      'webSocketClients': _webSockets.length,
      'activeStreamClients': _activeClientRegistry.activeClientCount,
      'qualityReportClients': _activeClientRegistry.qualityReportCount,
      'hasFrame': _latestJpeg != null,
      'deviceTier': _deviceTier.name,
      'mediaProfile': _effectiveMediaProfile().toJson(),
      'jpegBytesPerSecond': _jpegByteBudgetController.lastActualBytesPerSecond(
        _activeMediaProfile,
      ),
      'battery': battery.toJson(),
      'clientBatteries': {
        for (final entry in _clientBatterySnapshots.entries)
          entry.key: entry.value.toJson(),
      },
      'transport': _transportStatus(),
      'streamHealth': _streamHealthStatus(nowMs),
      'comfort': _features.comfortAudio.state.toJson(),
      'nightLight': _features.nightLight.state.toJson(),
      'talk': _talkStatus(),
      if (_broadcastAccess != null)
        'broadcastAccess': (await _broadcastAccess.snapshot()).toJson(),
      if (_analysisCoordinator != null) ..._analysisCoordinator!.diagnostics(),
    });
  }

  Future<void> _handleComfortState(HttpRequest request) async {
    await _writeJson(request.response, {
      'ok': true,
      'state': _features.comfortAudio.state.toJson(),
      'tracks': _features.comfortAudio.trackCatalog,
    });
  }

  Future<void> _handleComfortCommand(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final state = await _features.applyComfortCommand(body);
    _updateResourceWatchdog();
    await _writeJson(request.response, {
      'ok': state.lastError == null,
      'state': state.toJson(),
      'tracks': _features.comfortAudio.trackCatalog,
    });
  }

  Future<void> _handleNightLightState(HttpRequest request) async {
    await _writeJson(request.response, {
      'ok': true,
      'state': _features.nightLight.state.toJson(),
    });
  }

  Future<void> _handleNightLightCommand(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final state = await _features.nightLight.applyCommand(
      body,
      torchSetter: _setTorchEnabled,
    );
    await _writeJson(request.response, {
      'ok': state.lastError == null ||
          state.lastError == 'TORCH_UNAVAILABLE_SCREEN_GLOW_FALLBACK',
      'state': state.toJson(),
    });
  }

  Future<void> _handleTalkStart(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    try {
      Map<Object?, Object?>? body;
      try {
        body = await _readJsonObjectBody(request);
      } catch (_) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final session = await _features.startTalk(
        clientId: clientId,
        sampleRate: (body?['sampleRate'] as num?)?.toInt() ?? _audioSampleRate,
        channels: (body?['channels'] as num?)?.toInt() ?? _audioChannels,
      );
      _updateResourceWatchdog();
      await _writeJson(request.response, {
        'ok': true,
        'session': session.toJson(includeToken: true),
      });
    } on TalkSessionBusyException catch (error) {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'TALK_SESSION_BUSY',
        'activeSession': error.activeSession.toJson(),
      });
    }
  }

  Future<void> _handleTalkStop(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final stopped = await _features.stopTalk(
      clientId: clientId,
      token: body?['talkToken']?.toString(),
    );
    _updateResourceWatchdog();
    await _writeJson(request.response, {
      'ok': stopped,
      'talk': _talkStatus(),
    });
  }

  Future<void> _handleTalkAudio(HttpRequest request) async {
    final token = _talkTokenFromRequest(request);
    if (token == null || !_features.isTalkTokenActive(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    var totalBytes = 0;
    TalkSession? session;
    var playedChunks = 0;
    var rejected = false;
    final frameBytes = max(
      2,
      (_audioSampleRate * _audioChannels * 2 * 20 / 1000).round(),
    );
    final assembler = Pcm16FrameAssembler(frameBytes: frameBytes);

    Future<bool> play(Uint8List bytes) async {
      final result = await _features.acceptTalkAudio(token, bytes);
      session = result.session;
      rejected = session == null;
      if (result.played) playedChunks++;
      return session != null;
    }

    await for (final chunk in request) {
      if (chunk.isEmpty) continue;
      totalBytes += chunk.length;
      for (final frame in assembler.add(chunk)) {
        if (!await play(frame)) break;
      }
      if (rejected) break;
    }
    if (!rejected) {
      final tail = assembler.flushAlignedTail();
      if (tail != null && tail.isNotEmpty) await play(tail);
    }
    if (assembler.hasPartialSample) {
      onLog('Talk upload ended with one incomplete PCM16 byte.');
    }
    if (session == null && totalBytes > 0) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    session ??= _features.talkSessions.activeSession;
    await _writeJson(request.response, {
      'ok': session != null,
      'audioBytesReceived': totalBytes,
      'audioChunksPlayed': playedChunks,
      'talk': session?.toJson(),
    });
  }

  Future<void> _handleTalkVideo(HttpRequest request) async {
    await _handleTalkBytes(
      request,
      recorder: _features.acceptTalkVideo,
      mediaKey: 'videoBytesReceived',
    );
  }

  Future<void> _handleTalkBytes(
    HttpRequest request, {
    required TalkSession? Function(String token, Uint8List bytes) recorder,
    required String mediaKey,
  }) async {
    final token = _talkTokenFromRequest(request);
    if (token == null || !_features.isTalkTokenActive(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    var totalBytes = 0;
    TalkSession? session;
    await for (final chunk in request) {
      if (chunk.isEmpty) continue;
      final bytes = Uint8List.fromList(chunk);
      totalBytes += bytes.length;
      session = recorder(token, bytes);
      if (session == null) break;
    }
    if (session == null && totalBytes > 0) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    session ??= _features.talkSessions.activeSession;
    await _writeJson(request.response, {
      'ok': session != null,
      mediaKey: totalBytes,
      'talk': session?.toJson(),
    });
  }

  Future<void> _handleVideoRoute(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) return;
    try {
      await startVideoRuntime();
      await _handleMjpeg(request.response, clientId);
    } catch (_) {
      _activeClientRegistry.detachStream(clientId);
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleAudioRoute(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) return;
    try {
      await startAudioRuntime();
      await _handleAudio(request.response, clientId);
    } catch (_) {
      _activeClientRegistry.detachStream(clientId);
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handlePairConfirm(HttpRequest request) async {
    try {
      if (!_pairingModeActive) {
        request.response.statusCode = HttpStatus.notFound;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_NOT_ACTIVE',
          'message': 'Pairing is not active on this room device.',
        });
        return;
      }
      if (!tokenService.consumePairConfirmAttempt(
        _pairConfirmAttemptKey(request),
      )) {
        request.response.statusCode = HttpStatus.tooManyRequests;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIR_CONFIRM_RATE_LIMITED',
          'message': 'Pairing attempts are temporarily rate limited.',
        });
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      if (json is! Map) {
        request.response.statusCode = HttpStatus.badRequest;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_REQUEST_INVALID',
          'message': 'Pairing request is invalid.',
        });
        return;
      }
      final serverDeviceId = await _serverDeviceIdentityResolver.resolve();
      final originServerDeviceId =
          json['originServerDeviceId']?.toString().trim() ?? '';
      if (originServerDeviceId.isNotEmpty &&
          originServerDeviceId == serverDeviceId) {
        request.response.statusCode = HttpStatus.conflict;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'SELF_PAIRING_NOT_ALLOWED',
          'message': 'A device cannot pair with its own room.',
        });
        return;
      }
      if (tokenService.validateAndConsumeNonce(
              json['pairingNonce']?.toString() ?? '') ==
          false) {
        request.response.statusCode = HttpStatus.unauthorized;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_NONCE_INVALID_OR_EXPIRED',
          'message': 'This pairing QR has expired or was already used.',
        });
        return;
      }
      final token = tokenService.issueTrustedClientToken(
          clientName: json['clientName']?.toString() ?? 'Client',
          deviceId: json['deviceId']?.toString() ?? 'client');
      await _writeJson(request.response, {
        'serverDeviceId': serverDeviceId,
        'serverName': 'Bebek Odası',
        'clientId': token.clientId,
        'trustedClientToken': token.token,
        'trustedClientTokenExpiresAtMs': token.expiresAtMs,
        'capabilities': _mediaCapabilities(),
        'sessionToken': token.token,
      });
    } on TrustedClientLimitException {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': TrustedClientLimitException.code,
        'message': TrustedClientLimitException.userMessage,
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'PAIRING_REQUEST_INVALID',
        'message': 'Pairing request is invalid.',
      });
    }
  }

  Future<void> _handleAuthRenew(HttpRequest request) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : null;
    if (token == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    final renewed = tokenService.renewTrustedClientToken(token);
    if (renewed == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    await _writeJson(request.response, {
      'clientId': renewed.clientId,
      'trustedClientToken': renewed.token,
      'expiresAtMs': renewed.expiresAtMs,
    });
  }

  Future<void> _handleSessionStart(HttpRequest request) =>
      _sessionOperations.run(() => _handleSessionStartLocked(request));

  Future<void> _handleSessionStartLocked(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final clientId = _clientIdForRequest(request, json);
    final demand = _streamDemandForRequest(json);
    final mediaTransport = _mediaTransportForRequest(json);
    final runtimeDemand =
        mediaTransport == 'webrtc' ? (video: false, audio: false) : demand;
    BroadcastAccessSnapshot? accessSnapshot;
    try {
      accessSnapshot = await _broadcastAccess?.beginSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
    } on BroadcastAccessLockedException catch (error) {
      request.response.statusCode = HttpStatus.paymentRequired;
      await _writeBroadcastAccessLocked(request, error.snapshot);
      return;
    }
    late final ActiveSessionStartResult startResult;
    try {
      startResult = _activeClientRegistry.startSession(clientId);
    } on ActiveClientLimitException {
      accessSnapshot = await _broadcastAccess?.endSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
      request.response.statusCode = HttpStatus.tooManyRequests;
      await _writeJson(request.response, {
        'ok': false,
        'code': ActiveClientLimitException.code,
        'message': ActiveClientLimitException.userMessage,
      });
      return;
    }
    final sessionClientId = startResult.clientId;
    final hadExistingSession = !startResult.createdActiveSlot;
    final hadRuntimeSession = _runtimeSessionClients.contains(sessionClientId);
    final previousDemand = _sessionMediaDemands[sessionClientId];
    final previousTransport = _sessionMediaTransports[sessionClientId];
    final previousStandaloneDemand = _standaloneSessionDemands[sessionClientId];
    final sameRuntimeRequest = hadExistingSession &&
        previousDemand == demand &&
        previousTransport == mediaTransport;
    var runtimeMutationApplied = false;
    try {
      _sessionMediaDemands[sessionClientId] = demand;
      _sessionMediaTransports[sessionClientId] = mediaTransport;
      await _applyMediaProfileForCurrentDemand();
      final callback = onStreamSessionStarted;
      if (callback != null) {
        if (!sameRuntimeRequest) {
          await callback(
            sessionClientId,
            video: demand.video,
            audio: demand.audio,
            mediaTransport: mediaTransport,
          );
          runtimeMutationApplied = true;
        }
        _runtimeSessionClients.add(sessionClientId);
      } else if (startMediaOnSessionStart) {
        if (!sameRuntimeRequest) {
          _standaloneSessionDemands[sessionClientId] = runtimeDemand;
          await _reconcileStandaloneSessionDemand();
          runtimeMutationApplied = true;
        }
        _runtimeSessionClients.add(sessionClientId);
      }
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': startResult.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
        'streamToken': startResult.streamToken.token,
        'streamTokenExpiresAtMs': startResult.streamToken.expiresAtMs,
        'video': demand.video,
        'audio': demand.audio,
        'mediaTransport': mediaTransport,
        if (accessSnapshot != null) 'broadcastAccess': accessSnapshot.toJson(),
      });
    } catch (error) {
      if (hadExistingSession) {
        if (previousDemand == null) {
          _sessionMediaDemands.remove(sessionClientId);
        } else {
          _sessionMediaDemands[sessionClientId] = previousDemand;
        }
        if (previousTransport == null) {
          _sessionMediaTransports.remove(sessionClientId);
        } else {
          _sessionMediaTransports[sessionClientId] = previousTransport;
        }
        if (previousStandaloneDemand == null) {
          _standaloneSessionDemands.remove(sessionClientId);
        } else {
          _standaloneSessionDemands[sessionClientId] = previousStandaloneDemand;
        }

        if (runtimeMutationApplied) {
          try {
            final callback = onStreamSessionStarted;
            if (hadRuntimeSession &&
                callback != null &&
                previousDemand != null &&
                previousTransport != null) {
              await callback(
                sessionClientId,
                video: previousDemand.video,
                audio: previousDemand.audio,
                mediaTransport: previousTransport,
              );
            } else if (hadRuntimeSession && startMediaOnSessionStart) {
              await _reconcileStandaloneSessionDemand();
            } else if (!hadRuntimeSession) {
              final stopCallback = onStreamSessionStopped;
              if (stopCallback != null) {
                await stopCallback(sessionClientId);
              } else if (startMediaOnSessionStart) {
                await _reconcileStandaloneSessionDemand();
              }
            }
          } catch (rollbackError) {
            onLog('Session replacement rollback failed: $rollbackError');
          }
        }
        if (hadRuntimeSession) {
          _runtimeSessionClients.add(sessionClientId);
        } else {
          _runtimeSessionClients.remove(sessionClientId);
        }
        try {
          await _applyMediaProfileForCurrentDemand();
        } catch (rollbackError) {
          onLog('Session media profile rollback failed: $rollbackError');
        }
        _activeClientRegistry.rollbackSessionStart(startResult);
      } else if (runtimeMutationApplied) {
        _runtimeSessionClients.remove(sessionClientId);
        try {
          final callback = onStreamSessionStopped;
          if (callback != null) {
            await callback(sessionClientId);
          } else {
            _standaloneSessionDemands.remove(sessionClientId);
            await _reconcileStandaloneSessionDemand();
          }
        } catch (rollbackError) {
          onLog('Session runtime rollback failed: $rollbackError');
        }
      }
      if (!hadExistingSession) {
        _standaloneSessionDemands.remove(sessionClientId);
        _sessionMediaDemands.remove(sessionClientId);
        _sessionMediaTransports.remove(sessionClientId);
        _activeClientRegistry.rollbackSessionStart(startResult);
        try {
          accessSnapshot = await _broadcastAccess?.endSession(
            _broadcastAccessSessionId(clientId),
          );
          _notifyBroadcastAccessChanged(accessSnapshot);
          _scheduleBroadcastAccessTimer(accessSnapshot);
        } catch (accessError) {
          onLog('Session access rollback failed: $accessError');
        }
      }
      onLog('Medya başlatılamadı: $error');
      await _writeJsonBestEffort(
        request.response,
        statusCode: HttpStatus.internalServerError,
        body: {
          'ok': false,
          'code': 'MEDIA_START_FAILED',
          'message': error.toString(),
        },
      );
    }
  }

  Future<void> _handleSessionStop(HttpRequest request) =>
      _sessionOperations.run(() => _handleSessionStopLocked(request));

  Future<void> _handleSessionStopLocked(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final clientId = _clientIdForRequest(request, json);
    final errors = await _cleanupClientSession(clientId, closeWebRtc: true);
    if (errors.isEmpty) {
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      });
      return;
    }
    onLog('Session cleanup completed with errors: ${errors.join(' | ')}');
    await _writeJsonBestEffort(
      request.response,
      statusCode: HttpStatus.internalServerError,
      body: {
        'ok': false,
        'code': 'SESSION_CLEANUP_PARTIAL',
        'message': errors.first.toString(),
      },
    );
  }

  Future<void> _handleWebRtcOffer(
    HttpRequest request,
    String? authenticatedClientId,
  ) =>
      _sessionOperations.run(
        () => _handleWebRtcOfferLocked(request, authenticatedClientId),
      );

  Future<void> _handleWebRtcOfferLocked(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final clientId = authenticatedClientId!;
    var externalCaptureActivated = false;
    var peerTransportAttached = false;
    String? createdPeerId;
    try {
      final body = await _readJsonObjectBody(request);
      final offer = WebRtcOfferRequest.fromJson(body);
      await onWebRtcCaptureStarting?.call(clientId);
      externalCaptureActivated = true;
      final answer = await gateway.acceptOffer(
        clientId: clientId,
        request: offer,
      );
      createdPeerId = answer.peerId;
      // WebRTC has no MJPEG/WAV socket to call attachStream. Keep an explicit
      // transport lease so the 90-second bootstrap token expiry cannot prune
      // a healthy peer from capacity and paywall cleanup accounting.
      _activeClientRegistry.attachStream(clientId);
      peerTransportAttached = true;
      _updateResourceWatchdog();
      await _writeJson(request.response, answer.toJson());
    } on FormatException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'INVALID_WEBRTC_OFFER',
        'message': error.message,
      });
    } on WebRtcPilotCapacityException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_PILOT_CAPACITY',
        'message': error.toString(),
        'fallback': 'mjpeg_wav',
      });
    } on WebRtcPilotUnavailableException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_UNAVAILABLE',
        'message': error.toString(),
        'fallback': 'mjpeg_wav',
      });
    } catch (error) {
      if (peerTransportAttached) {
        _activeClientRegistry.detachStream(clientId);
        peerTransportAttached = false;
      }
      if (createdPeerId != null) {
        try {
          await gateway.closePeer(
            clientId: clientId,
            peerId: createdPeerId,
          );
        } catch (_) {}
      }
      if (externalCaptureActivated) {
        try {
          await onWebRtcCaptureEnded?.call(clientId);
        } catch (_) {}
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_NEGOTIATION_FAILED',
        'message': error.toString(),
        'fallback': 'mjpeg_wav',
      });
    }
  }

  Future<void> _handleWebRtcIce(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final peerId = request.uri.queryParameters['peerId']?.trim() ?? '';
    if (peerId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    try {
      if (request.method == HttpMethod.post) {
        final body = await _readJsonObjectBody(request);
        final candidate = WebRtcIceCandidateSignal.fromJson(
          body?['candidate'],
        );
        await gateway.addRemoteCandidate(
          clientId: authenticatedClientId!,
          peerId: peerId,
          candidate: candidate,
        );
        await _writeJson(request.response, const {'ok': true});
      } else {
        final candidates = gateway.drainLocalCandidates(
          clientId: authenticatedClientId!,
          peerId: peerId,
        );
        await _writeJson(request.response, {
          'ok': true,
          'iceCandidates': candidates.map((item) => item.toJson()).toList(),
        });
      }
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'INVALID_ICE_CANDIDATE',
        'message': error.message,
      });
    } on WebRtcPeerNotFoundException {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleWebRtcClose(
    HttpRequest request,
    String? authenticatedClientId,
  ) =>
      _sessionOperations.run(
        () => _handleWebRtcCloseLocked(request, authenticatedClientId),
      );

  Future<void> _handleWebRtcCloseLocked(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final peerId = request.uri.queryParameters['peerId']?.trim() ?? '';
    try {
      await gateway.closePeer(
        clientId: authenticatedClientId!,
        peerId: peerId,
      );
    } on WebRtcPeerNotFoundException {
      // Close is idempotent from the client's perspective.
    }
    final errors = await _cleanupClientSession(
      authenticatedClientId!,
      closeWebRtc: false,
    );
    await _writeJson(request.response, {
      'ok': errors.isEmpty,
      if (errors.isNotEmpty) 'cleanupError': errors.first.toString(),
    });
  }

  Future<void> pauseExternalMediaForPlatform(String reason) async {
    final gateway = webRtcGateway;
    if (gateway == null || gateway.activePeerCount == 0) return;
    if (gateway is WebRtcBackgroundMediaController) {
      await (gateway as WebRtcBackgroundMediaController)
          .suspendVideoForBackground();
    } else {
      for (final clientId in _activeClientRegistry.activeClientIds) {
        await gateway.closeClient(clientId);
      }
    }
    onLog('WebRTC video paused; background audio preserved: $reason');
  }

  Future<void> recoverExternalMediaForPlatform(String reason) async {
    final gateway = webRtcGateway;
    if (gateway == null ||
        gateway is! WebRtcBackgroundMediaController ||
        gateway.activePeerCount == 0) {
      return;
    }
    await (gateway as WebRtcBackgroundMediaController)
        .reconnectPeersForForeground();
    onLog('WebRTC peers reconnecting after foreground recovery: $reason');
  }

  void _handleWebRtcPeerLifecycleEvent(WebRtcPeerLifecycleEvent event) {
    if (_disposed) return;
    unawaited(_sessionOperations.run(() async {
      if (!_runtimeSessionClients.contains(event.clientId) &&
          !_activeClientRegistry.activeClientIds.contains(event.clientId)) {
        return;
      }
      final errors = await _cleanupClientSession(
        event.clientId,
        closeWebRtc: false,
      );
      onLog(
        'WebRTC peer closed (${event.reason.name}); session released'
        '${errors.isEmpty ? '' : ': ${errors.join(' | ')}'}',
      );
    }).catchError((Object error) {
      onLog('WebRTC peer cleanup could not be queued: $error');
    }));
  }

  Future<List<Object>> _cleanupClientSession(
    String clientId, {
    required bool closeWebRtc,
  }) async {
    final cleanup = BestEffortOperationCollector();

    if (closeWebRtc) {
      await cleanup.attempt(
        'WebRTC client',
        () async => webRtcGateway?.closeClient(clientId),
      );
    }
    await cleanup.attempt(
      'video stream client',
      () => _videoStreamService.closeClient(clientId),
    );
    await cleanup.attempt(
      'audio stream client',
      () => _audioStreamService.closeClient(clientId),
    );
    _activeClientRegistry.stopSession(clientId);
    _sessionMediaDemands.remove(clientId);
    _sessionMediaTransports.remove(clientId);

    final ownedRuntimeSession = _runtimeSessionClients.remove(clientId);
    if (ownedRuntimeSession) {
      final callback = onStreamSessionStopped;
      if (callback != null) {
        await cleanup.attempt(
            'media runtime session', () => callback(clientId));
      } else {
        _standaloneSessionDemands.remove(clientId);
        await cleanup.attempt(
          'standalone media demand',
          _reconcileStandaloneSessionDemand,
        );
      }
    } else {
      _standaloneSessionDemands.remove(clientId);
    }

    await cleanup.attempt('broadcast access session', () async {
      final accessSnapshot = await _broadcastAccess?.endSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
    });
    if (_activeClientRegistry.activeClientCount > 0) {
      await cleanup.attempt(
        'remaining client media profile',
        _applyMediaProfileForCurrentDemand,
      );
    }
    _updateResourceWatchdog();
    return cleanup.errors;
  }

  Future<WebRtcServerGateway?> _authorizedWebRtcGateway(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = webRtcGateway;
    if (!config.webRtcPilotEnabled || gateway == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return null;
    }
    if (!gateway.isAvailable && !await gateway.initialize()) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, const {
        'ok': false,
        'code': 'WEBRTC_UNAVAILABLE',
        'fallback': 'mjpeg_wav',
      });
      return null;
    }
    final tokenClientId =
        _streamTokenClientId(request.uri.queryParameters['streamToken']);
    if (authenticatedClientId == null ||
        tokenClientId == null ||
        authenticatedClientId != tokenClientId) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return null;
    }
    return gateway;
  }

  Future<void> _handleQualityReport(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      if (json is! Map) throw const FormatException('Invalid quality report');
      final auth = _authGuard.trusted(request);
      if (auth == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      // Body clientId is telemetry metadata only; the trusted Bearer token owns
      // the identity used for quality decisions and cleanup.
      final report = ClientQualityReport.fromJson(
        Map<Object?, Object?>.from(json),
        clientId: auth.clientId,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      final battery = BatterySnapshot.fromJson(json['battery']);
      if (battery != null) _clientBatterySnapshots[auth.clientId] = battery;
      final serverBattery = await _refreshServerBattery();
      _activeClientRegistry.updateQualityReport(report);
      final pendingProfile = _previewMediaProfileForCurrentDemand();
      _scheduleMediaProfileApplyForCurrentDemand();
      await _writeJson(request.response, {
        'ok': true,
        'deviceTier': _deviceTier.name,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'effectiveNetworkTier': _activeClientRegistry.effectiveTier().name,
        'mediaProfile': _effectiveMediaProfile(pendingProfile).toJson(),
        'battery': serverBattery.toJson(),
        'clientBattery': battery?.toJson(),
        'transport': _transportStatus(),
        'streamHealth': _streamHealthStatus(
          DateTime.now().millisecondsSinceEpoch,
        ),
        'deviceResources': _deviceResources.toJson(),
        'resourceGovernor': _resourceDecision.toJson(),
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  }

  Future<void> _applyMediaProfileForCurrentDemand() =>
      _mediaProfileApplyQueue.enqueue((generation) async {
        try {
          // Compute inside the serialized section so a queued report never
          // applies a decision made from stale client state.
          _deviceResources = await _deviceResourceProvider.snapshot();
          final baseProfile = _selectMediaProfileForCurrentDemand();
          final nextDecision = _evaluateResourceDecision();
          if (nextDecision.state != _resourceDecision.state) {
            onLog(
              'Kaynak koruma modu: ${nextDecision.state.name} '
              '(${nextDecision.reasons.join(', ')})',
            );
          }
          _resourceDecision = nextDecision;
          final nextProfile = nextDecision.applyTo(baseProfile);
          await _setActiveMediaProfile(
            nextProfile,
            applyGeneration: generation,
          );
        } catch (error, stackTrace) {
          _mediaProfileApplyFailureCount++;
          _lastMediaProfileApplyError = error;
          _lastMediaProfileApplyErrorAtMs =
              DateTime.now().millisecondsSinceEpoch;
          onLog('Medya profili uygulanamadı: $error');
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

  MediaQualityProfile _selectMediaProfileForCurrentDemand() =>
      _mediaQualitySelector.select(
        deviceTier: _deviceTier,
        networkTier: NetworkQualityTier.unknown,
        activeClientCount: _activeClientRegistry.activeClientCount,
        worstReport: _activeClientRegistry.worstQualityReport(),
        qualityReports: _activeClientRegistry.activeQualityReports(),
        backpressureMetrics: _combinedBackpressureMetrics(),
      );

  MediaQualityProfile _previewMediaProfileForCurrentDemand() =>
      _resourceDecision.applyTo(_mediaQualitySelector.preview(
        deviceTier: _deviceTier,
        networkTier: NetworkQualityTier.unknown,
        activeClientCount: _activeClientRegistry.activeClientCount,
        worstReport: _activeClientRegistry.worstQualityReport(),
        qualityReports: _activeClientRegistry.activeQualityReports(),
        backpressureMetrics: _combinedBackpressureMetrics(),
      ));

  MediaResourceGovernorDecision _evaluateResourceDecision() {
    final reports = _activeClientRegistry.activeQualityReports().toList();
    final encodeP95 = _mediaTelemetry
        .snapshot()
        .distribution(MediaMetricName.videoEncode)
        ?.p95Ms;
    return _resourcePolicyCoordinator.evaluate(
      MediaResourceGovernorInput(
        device: _deviceResources,
        networkTier: _activeClientRegistry.effectiveTier(),
        backpressure: _combinedBackpressureMetrics(),
        activeClientCount: _activeClientRegistry.activeClientCount,
        videoEncodeP95Ms: encodeP95,
        framesCaptured: _videoFramesCaptured,
        framesDroppedBeforeEncode: _videoFramesDroppedBeforeEncode,
        decoderCoalescedFrames: reports.fold<int>(
          0,
          (total, report) => total + report.coalescedVideoFrames,
        ),
        audioUnderruns: reports.where((report) => report.audioUnderrun).length,
        audioDemandAvailable: _microphoneCapture.isActive ||
            _audioStreamService.hasClients ||
            _injectedAudioDemand ||
            _sessionMediaDemands.values.any((value) => value.audio) ||
            _standaloneSessionDemands.values.any((value) => value.audio),
      ),
    );
  }

  void _scheduleMediaProfileApplyForCurrentDemand() {
    // The apply operation records and logs its own error before rethrowing. The
    // completion handler prevents a detached Future from becoming unhandled.
    unawaited(
      _applyMediaProfileForCurrentDemand().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      ),
    );
  }

  String _broadcastAccessSessionId(String clientId) =>
      'server.stream.${clientId.trim().isEmpty ? 'unknown_client' : clientId.trim()}';

  Future<void> _writeBroadcastAccessLocked(
    HttpRequest request,
    BroadcastAccessSnapshot snapshot,
  ) =>
      _writeJson(request.response, {
        'ok': false,
        'code': 'BROADCAST_ACCESS_LOCKED',
        'message':
            'Free broadcast time ended. One-time ${snapshot.priceLabel} unlock required.',
        'broadcastAccess': snapshot.toJson(),
      });

  void _notifyBroadcastAccessChanged(BroadcastAccessSnapshot? snapshot) {
    if (snapshot == null) return;
    onBroadcastAccessChanged?.call(snapshot);
  }

  void _cancelBroadcastAccessTimer() {
    _broadcastAccessTimerGeneration++;
    _broadcastAccessTimer?.cancel();
    _broadcastAccessTimer = null;
  }

  void _scheduleBroadcastAccessTimer(BroadcastAccessSnapshot? snapshot) {
    _cancelBroadcastAccessTimer();
    if (snapshot == null || snapshot.unlocked || !snapshot.active) {
      return;
    }
    final generation = _broadcastAccessTimerGeneration;
    final delay = snapshot.isLocked ? Duration.zero : snapshot.remaining;
    _broadcastAccessTimer = Timer(delay, () {
      if (_disposed || generation != _broadcastAccessTimerGeneration) return;
      _broadcastAccessTimer = null;
      unawaited(
          _expireBroadcastAccessIfNeeded(generation).catchError((Object error) {
        onLog('Broadcast expiry cleanup could not be queued: $error');
      }));
    });
  }

  Future<void> _expireBroadcastAccessIfNeeded(int generation) =>
      _sessionOperations.run(
        () => _expireBroadcastAccessIfNeededLocked(generation),
      );

  Future<void> _expireBroadcastAccessIfNeededLocked(int generation) async {
    final access = _broadcastAccess;
    if (access == null ||
        _disposed ||
        generation != _broadcastAccessTimerGeneration) {
      return;
    }
    final snapshot = await access.snapshot();
    if (_disposed || generation != _broadcastAccessTimerGeneration) return;
    if (!snapshot.active || snapshot.unlocked) {
      _cancelBroadcastAccessTimer();
      _notifyBroadcastAccessChanged(snapshot);
      return;
    }
    if (!snapshot.isLocked) {
      _scheduleBroadcastAccessTimer(snapshot);
      _notifyBroadcastAccessChanged(snapshot);
      return;
    }
    _cancelBroadcastAccessTimer();
    final expiredClientIds = _activeClientRegistry.activeClientIds;
    for (final clientId in expiredClientIds) {
      final errors = await _cleanupClientSession(
        clientId,
        closeWebRtc: true,
      );
      if (errors.isNotEmpty) {
        onLog(
          'Expired session $clientId released with errors: '
          '${errors.join(' | ')}',
        );
      }
    }
    _activeClientRegistry.clear();
    await access.endAllSessions();
    onLog('Ücretsiz yayın süresi doldu; canlı stream kilitlendi.');
    _notifyBroadcastAccessChanged(await access.snapshot());
  }

  StreamBackpressureMetrics _combinedBackpressureMetrics() =>
      combineBackpressureMetrics([
        _videoStreamService.backpressureMetrics,
        _audioStreamService.backpressureMetrics,
      ]);

  bool _isAudioReliable() =>
      _audioStreamService.backpressureMetrics.consecutiveSkippedAudioChunks ==
      0;

  bool _isVideoReliable() =>
      _videoStreamService.backpressureMetrics.consecutiveSkippedVideoFrames < 3;

  Future<void> _setActiveMediaProfile(
    MediaQualityProfile nextProfile, {
    required int applyGeneration,
  }) async {
    if (!_isCurrentMediaProfileApply(applyGeneration)) return;
    final previousProfile = _activeMediaProfile;
    if (_mediaProfileCameraRestartPolicy.requiresRestart(
      previousProfile,
      nextProfile,
    )) {
      final restarted = await _restartCameraWithProfile(
        nextProfile,
        applyGeneration: applyGeneration,
      );
      if (!restarted) return;
    }
    if (!_isCurrentMediaProfileApply(applyGeneration)) return;
    _activeMediaProfile = nextProfile;
    _frameBudget.updateMinInterval(_activeMediaProfile.frameInterval);
    if (mediaSource case final ServerMediaPolicySink nativePolicy) {
      await nativePolicy.applyMediaPolicy(
        jpegQuality: _activeMediaProfile.jpegQuality,
        maxVideoFps: _activeMediaProfile.targetFps,
      );
    }
    await _applyWebRtcMediaPolicy(_activeMediaProfile);
    if (previousProfile.id != _activeMediaProfile.id) {
      onLog('Medya profili: ${_activeMediaProfile.summary}');
      onMediaProfileChanged?.call(_activeMediaProfile);
    }
  }

  bool _isCurrentMediaProfileApply(int generation) =>
      !_disposed && _mediaProfileApplyQueue.isCurrent(generation);

  Future<bool> _restartCameraWithProfile(
    MediaQualityProfile profile, {
    required int applyGeneration,
  }) async {
    if (!_isCurrentMediaProfileApply(applyGeneration)) return false;
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    final previousController = cameraController;
    if (previousController == null) return true;
    if (!identical(cameraController, previousController)) return false;
    cameraController = null;
    _latestJpeg = null;
    _frameBudget.reset();
    _resourcePolicyCoordinator.resetDecision();
    await previousController.dispose();
    CameraController? nextController;
    var installed = false;
    try {
      if (!_isCurrentMediaProfileApply(applyGeneration)) return false;
      await _ensureCameraPermission();
      if (!_isCurrentMediaProfileApply(applyGeneration)) return false;
      final cameras = await availableCameras();
      if (!_isCurrentMediaProfileApply(applyGeneration)) return false;
      if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

      nextController = CameraController(
        cameras.first,
        _resolutionPresetFor(profile),
        enableAudio: false,
        fps: max(
          1,
          _mediaProfileCameraRestartPolicy.captureFps(
            deviceProfile: MediaQualityProfile.forDeviceTier(_deviceTier),
            activeProfile: profile,
          ),
        ),
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await nextController.initialize();
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          cameraController != null) {
        await _disposeStaleCameraController(nextController);
        return false;
      }
      cameraController = nextController;
      await nextController.startImageStream(_handleCameraFrame);
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !identical(cameraController, nextController)) {
        if (identical(cameraController, nextController)) {
          cameraController = null;
        }
        await _disposeStaleCameraController(nextController);
        return false;
      }
      installed = true;
      return true;
    } catch (error, stackTrace) {
      if (nextController != null &&
          identical(cameraController, nextController)) {
        cameraController = null;
      }
      if (nextController != null) {
        await _disposeStaleCameraController(nextController);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!installed &&
          _videoCaptureDesired &&
          !_disposed &&
          cameraController == null) {
        try {
          await _startVideoCaptureRuntime();
          onLog('Camera profile restart rolled back to the previous profile.');
        } catch (recoveryError) {
          onLog('Camera profile rollback failed: $recoveryError');
        }
      }
    }
  }

  Future<void> _disposeStaleCameraController(
    CameraController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (error) {
      onLog('Eski kamera controller kapatılamadı: $error');
    }
  }

  Future<void> _ensureCameraPermission() async {
    if (await mediaPermissions.requestCamera()) return;
    throw StateError(strings.cameraPermissionMissing);
  }

  Map<String, Object?> _mediaCapabilities() => {
        'video': _activeMediaProfile.videoCodec,
        'videoPreferred': _activeMediaProfile.preferredVideoCodec,
        'audio': _activeMediaProfile.audioCodec,
        'audioPreferred': _activeMediaProfile.preferredAudioCodec,
        'mediaTransportPreferred':
            config.webRtcPilotEnabled && webRtcGateway?.isAvailable == true
                ? 'webrtc'
                : 'mjpeg_wav',
        'mediaTransports': [
          if (config.webRtcPilotEnabled && webRtcGateway?.isAvailable == true)
            'webrtc',
          'mjpeg_wav',
        ],
        'webrtc': {
          'enabled':
              config.webRtcPilotEnabled && webRtcGateway?.isAvailable == true,
          'video': 'h264',
          'audio': 'opus',
          'maxPeers': 1,
          'fallback': 'mjpeg_wav',
        },
        'events': 'json',
        'maxClients': maxActiveWatchClients,
        'maxChildren': 4,
        'comfortAudio': true,
        'nightLight': true,
        'twoWayTalk': true,
        'talkAudio': {
          'codec': 'pcm_s16le',
          'sampleRate': _audioSampleRate,
          'channels': _audioChannels,
        },
        'talkVideo': false,
        'battery': true,
        'dnsSdDiscovery': true,
        'ipv6': _httpServer?.address.type == InternetAddressType.IPv6,
        'bleDiscovery': false,
        if (_broadcastAccess != null) ...{
          'freeBroadcastLimitMs':
              BroadcastAccessConfig.freeLimit.inMilliseconds,
          'oneTimeUnlockPrice': BroadcastAccessConfig.oneTimePriceLabel,
          'oneTimeUnlockProductId': BroadcastAccessConfig.productId,
        },
        'transportPreferred': transportConfig.payloadTransport,
        'transportModes': const ['wifi_lan', 'hotspot_lan', 'dns_sd'],
        'deviceTier': _deviceTier.name,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      };

  Map<String, Object?> _transportStatus() => {
        'mode': transportConfig.payloadTransport,
        'active': 'wifi_lan',
        'dnsSdDiscovery': _serviceAdvertiser?.isAdvertising == true,
        'bleDiscovery': false,
        'hotspotAutomation': false,
        'mediaOverBle': false,
      };

  Future<BatterySnapshot> _refreshServerBattery() async {
    _serverBattery = await _batteryProvider.snapshot();
    return _serverBattery;
  }

  Map<String, Object?> _streamHealthStatus(int nowMs) {
    final video = _videoStreamService.snapshot;
    final audio = _audioStreamService.snapshot;
    final audioGapMs = _ageMs(nowMs, audio.lastClientWriteAtMs);
    final frameGapMs = _ageMs(nowMs, video.lastClientWriteAtMs);
    final tier = _activeClientRegistry.effectiveTier();
    return {
      'signal': tier.name,
      'rttMs': _activeClientRegistry.worstQualityReport()?.rttMs,
      'fps': _activeMediaProfile.targetFps,
      'bitrateBytesPerSecond':
          _jpegByteBudgetController.lastActualBytesPerSecond(
        _activeMediaProfile,
      ),
      'audioGapMs': audioGapMs,
      'videoFrameGapMs': frameGapMs,
      'audioHealth':
          audioGapMs == null || audioGapMs < 1500 ? 'healthy' : 'underrun',
      'reconnects': 0,
      'videoClients': video.clientCount,
      'audioClients': audio.clientCount,
      'encoderBusy': _jpegEncodeInFlight,
      'framesDroppedBeforeEncode': _videoFramesDroppedBeforeEncode,
      'framesSkippedByPolicy': _videoFramesSkippedByPolicy,
      'selfAudioSuppressedChunks': _selfAudioSuppressedChunks,
      'mediaProfileApplyFailureCount': _mediaProfileApplyFailureCount,
      'lastMediaProfileApplyError': _lastMediaProfileApplyError?.toString(),
      'lastMediaProfileApplyErrorAtMs': _lastMediaProfileApplyErrorAtMs,
      'deviceResources': _deviceResources.toJson(),
      'resourceGovernor': _resourceDecision.toJson(),
      'sessionTelemetry': _mediaTelemetry.snapshot().toJson(),
      'clientTransportTelemetry':
          _activeClientRegistry.worstQualityReport()?.transportTelemetry,
    };
  }

  Map<String, Object?> _talkStatus() => _features.talkStatus();

  MediaQualityProfile _effectiveMediaProfile([
    MediaQualityProfile? profile,
  ]) {
    final effective = profile ?? _activeMediaProfile;
    return effective.copyWith(
      jpegQuality: _jpegByteBudgetController.qualityFor(effective),
    );
  }

  ResolutionPreset _resolutionPresetFor(MediaQualityProfile profile) =>
      switch (profile.cameraPresetKey) {
        'low' => ResolutionPreset.low,
        'high' => ResolutionPreset.high,
        _ => ResolutionPreset.medium,
      };

  String? _webSocketClientId(HttpRequest request) {
    final trusted = _authGuard.trusted(request);
    if (trusted != null) return trusted.clientId;
    final token = request.uri.queryParameters['token'];
    return token == null
        ? null
        : tokenService.validateTrustedClientToken(token)?.clientId;
  }

  String _pairConfirmAttemptKey(HttpRequest request) =>
      request.connectionInfo?.remoteAddress.address ?? 'unknown';

  String? _hostFromHeader(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final host = Uri.parse('http://${value.trim()}').host;
      return host.isEmpty ? null : host;
    } on FormatException {
      return null;
    }
  }

  String? _talkTokenFromRequest(HttpRequest request) {
    final queryToken = request.uri.queryParameters['talkToken'];
    if (queryToken != null && queryToken.isNotEmpty) return queryToken;
    final headerToken = request.headers.value('X-MimiCam-Talk-Token');
    if (headerToken != null && headerToken.isNotEmpty) return headerToken;
    final bearer = request.headers.value(HttpHeaders.authorizationHeader);
    if (bearer != null && bearer.startsWith('Talk ')) {
      return bearer.substring(5);
    }
    return null;
  }

  Future<bool> _setTorchEnabled(bool enabled) async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return false;
    await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
    return true;
  }

  String _clientIdForRequest(HttpRequest request, Object? json) {
    final auth = _authGuard.trusted(request);
    if (auth != null) return auth.clientId;
    if (json is Map) {
      final clientId = json['clientId']?.toString().trim();
      if (clientId != null && clientId.isNotEmpty) return clientId;
    }
    return request.connectionInfo?.remoteAddress.address ?? 'unknown_client';
  }

  ({bool video, bool audio}) _streamDemandForRequest(Object? json) {
    if (json is! Map) return (video: true, audio: false);
    final video = json['video'];
    final audio = json['audio'];
    return (
      video: video is bool ? video : true,
      audio: audio is bool ? audio : false,
    );
  }

  String _mediaTransportForRequest(Object? json) {
    if (json is! Map || json['mediaTransport'] != 'webrtc') {
      return 'mjpeg_wav';
    }
    final gateway = webRtcGateway;
    return config.webRtcPilotEnabled && gateway?.isAvailable == true
        ? 'webrtc'
        : 'mjpeg_wav';
  }

  Future<void> _reconcileStandaloneSessionDemand() async {
    final video = _standaloneSessionDemands.values.any((value) => value.video);
    final audio = _standaloneSessionDemands.values.any((value) => value.audio);
    if (video) {
      await startVideoRuntime();
    } else {
      await stopVideoRuntime();
    }
    if (audio) {
      await startAudioRuntime();
    } else {
      await stopAudioRuntime();
    }
  }

  Future<Object?> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Future<Map<Object?, Object?>?> _readJsonObjectBody(
      HttpRequest request) async {
    final json = await _readJsonBody(request);
    if (json == null) return null;
    if (json is! Map) throw const FormatException('Expected JSON object');
    return Map<Object?, Object?>.from(json);
  }

  Future<RequestAuthResult?> _requireTrustedAuth(HttpRequest request) async {
    final auth = _authGuard.trusted(request);
    if (auth != null) return auth;
    request.response.statusCode = HttpStatus.unauthorized;
    await request.response.close();
    return null;
  }

  Future<String?> _requireStreamAuth(HttpRequest request) async {
    final clientId =
        _streamTokenClientId(request.uri.queryParameters['streamToken']);
    final trusted = _authGuard.trusted(request);
    if (clientId == null || (trusted != null && trusted.clientId != clientId)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return null;
    }
    try {
      return _activeClientRegistry.attachStream(clientId).clientId;
    } on ActiveClientLimitException {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await _writeJson(request.response, {
        'ok': false,
        'code': ActiveClientLimitException.code,
        'message': ActiveClientLimitException.userMessage,
      });
      return null;
    }
  }

  String? _streamTokenClientId(String? streamToken) {
    if (streamToken == null || streamToken.isEmpty) return null;
    return _activeClientRegistry.clientIdForStreamToken(streamToken);
  }

  Future<void> stopMediaRuntime() async {
    _cancelBroadcastAccessTimer();
    await stopVideoRuntime();
    await stopAudioRuntime();
    mediaSource?.resetDiagnostics();
    _mediaQualitySelector.reset();
    _resourceDecision = MediaResourceGovernorDecision.normal;
  }

  Future<void> stopVideoRuntime() async {
    _videoCaptureDesired = false;
    final source = mediaSource;
    if (source != null) {
      await _reconcileInjectedMediaSource(source, video: false);
      return;
    }
    _mediaProfileApplyQueue.invalidate();
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    final controller = cameraController;
    cameraController = null;
    try {
      await controller?.dispose();
    } finally {
      _latestJpeg = null;
      _videoProbeEncodeUntilMs = null;
      _lastMotionSample = null;
      _lastMotionEnergy = 0;
      _frameBudget.reset();
      await _videoStreamService.closeAll();
      _videoStreamService.resetDiagnostics();
      _jpegByteBudgetController.reset();
      _videoFramesDroppedBeforeEncode = 0;
      _videoFramesSkippedByPolicy = 0;
      _videoFramesCaptured = 0;
      await _disposeAnalysisIfIdle();
      await _updateMediaHostLifecycle();
    }
  }

  Future<void> stopAudioRuntime() async {
    final source = mediaSource;
    if (source != null) {
      await _reconcileInjectedMediaSource(source, audio: false);
      return;
    }
    await _microphoneCapture.stop();
    await _audioStreamService.closeAll();
    _microphoneCapture.resetDiagnostics();
    _audioStreamService.resetDiagnostics();
    _cryActive = false;
    _lastCryActiveAtMs = null;
    await _disposeAnalysisIfIdle();
    await _updateMediaHostLifecycle();
  }

  Future<void> _disposeAnalysisIfIdle() async {
    final hasCapture = mediaSource?.isActive == true ||
        cameraController != null ||
        _microphoneCapture.isActive;
    if (hasCapture) return;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
  }

  Future<void> _updateMediaHostLifecycle() async {
    // Injected sources are deterministic test/diagnostic producers and do not
    // own platform camera or microphone hardware.
    if (mediaSource != null) {
      // Android's production CameraX/AudioRecord bridge is also a mediaSource.
      // Its foreground-service ownership stays native, while Dart still owns
      // the thermal/resource watchdog lifecycle.
      _updateResourceWatchdog();
      return;
    }
    final hasCapture = mediaSource?.isActive == true ||
        cameraController != null ||
        _microphoneCapture.isActive;
    if (hasCapture) {
      _updateResourceWatchdog();
      if (defaultTargetPlatform == TargetPlatform.iOS && _wakelockEnabled) {
        await WakelockPlus.disable();
        _wakelockEnabled = false;
      } else if (defaultTargetPlatform != TargetPlatform.iOS &&
          !_wakelockEnabled) {
        await WakelockPlus.enable();
        _wakelockEnabled = true;
      }
      await ForegroundServiceController.startServer();
      return;
    }
    await ForegroundServiceController.stopServer();
    _updateResourceWatchdog();
    if (_wakelockEnabled) {
      await WakelockPlus.disable();
      _wakelockEnabled = false;
    }
  }

  bool _isResourceMonitoringRequired() =>
      !_disposed &&
      (mediaSource?.isActive == true ||
          cameraController != null ||
          _microphoneCapture.isActive ||
          (webRtcGateway?.activePeerCount ?? 0) > 0 ||
          _features.roomAudio.mode != RoomAudioMode.idle);

  void _updateResourceWatchdog() =>
      _resourcePolicyCoordinator.reconcileWatchdog();

  void _handleRoomAudioModeChanged(RoomAudioMode mode) {
    _updateResourceWatchdog();
  }

  Future<void> _refreshResourceProfile() async {
    final provider = _deviceResourceProvider;
    if (provider is CachedDeviceResourceSnapshotProvider) {
      provider.invalidate();
    }
    await _applyMediaProfileForCurrentDemand();
  }

  Future<void> _applyWebRtcMediaPolicy(MediaQualityProfile profile) async {
    final gateway = webRtcGateway;
    if (gateway == null ||
        gateway.activePeerCount == 0 ||
        gateway is! WebRtcMediaPolicyController) {
      return;
    }
    final controller = gateway as WebRtcMediaPolicyController;
    await controller.applyMediaPolicy(
      _resourcePolicyCoordinator.webRtcPolicyFor(profile, _resourceDecision),
    );
  }

  Future<void> _handleMjpeg(HttpResponse response, String clientId) async {
    await _videoStreamService.attachClient(
      response,
      clientId,
      firstFrame: _latestJpeg,
    );
  }

  Future<void> _handleAudio(HttpResponse response, String clientId) async {
    await _audioStreamService.attachClient(response, clientId);
  }

  Future<void> _writeJson(
      HttpResponse response, Map<String, Object?> body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeJsonBestEffort(
    HttpResponse response, {
    required int statusCode,
    required Map<String, Object?> body,
  }) async {
    try {
      response.statusCode = statusCode;
      await _writeJson(response, body);
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _writeLandingPage(HttpResponse response) async {
    response.headers.contentType = ContentType.html;
    response.write('''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>MimiCam</title></head>
<body style="margin:0;background:#111;color:white;font-family:-apple-system,BlinkMacSystemFont,sans-serif">
  <main style="padding:16px"><h1>${strings.appTitle}</h1><p>${strings.streamActiveHtml}</p><p><a style="color:#ff8ab3" href="${protocol_v2.MimiCamProtocolV2.testDashboard}">Canlı test panelini aç</a></p></main>
</body></html>''');
    await response.close();
  }

  Future<void> _writeTestDashboard(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    final html = await const MimiCamTestDashboardAssets().loadHtml(
      title: '${strings.appTitle} Test',
    );
    request.response.write(html);
    await request.response.close();
  }

  Future<void> _writeTestDashboardScript(HttpRequest request) async {
    request.response.headers.contentType =
        ContentType('application', 'javascript', charset: 'utf-8');
    request.response.write(
      await const MimiCamTestDashboardAssets().loadScript(),
    );
    await request.response.close();
  }

  Future<void> _releaseWebSocket(WebSocket socket) async {
    _webSockets.remove(socket);
    final clientId = _webSocketClientIds.remove(socket);
    if (clientId == null) return;
    final count = _eventClientSocketCounts[clientId] ?? 0;
    if (count > 1) {
      _eventClientSocketCounts[clientId] = count - 1;
      return;
    }
    _eventClientSocketCounts.remove(clientId);
    if (_disposed) return;
    try {
      await onAlertClientDisconnected?.call(clientId);
    } catch (error) {
      onLog('Alert media demand could not stop: $error');
    }
  }

  int _broadcastBinary(List<int> data) {
    var delivered = 0;
    for (final socket in _webSockets.toList()) {
      try {
        socket.add(data);
        delivered++;
      } catch (_) {
        unawaited(_releaseWebSocket(socket));
      }
    }
    return delivered;
  }

  int _broadcastText(String data) {
    var delivered = 0;
    for (final socket in _webSockets.toList()) {
      try {
        socket.add(data);
        delivered++;
      } catch (_) {
        unawaited(_releaseWebSocket(socket));
      }
    }
    return delivered;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelBroadcastAccessTimer();
    final cleanup = BestEffortOperationCollector();

    await cleanup.attempt('WebRTC lifecycle subscription', () async {
      await _webRtcPeerSubscription?.cancel();
      _webRtcPeerSubscription = null;
    });
    await cleanup.attempt(
      'session operation queue',
      _sessionOperations.close,
    );
    _mediaProfileApplyQueue.invalidate();
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    await cleanup.attempt('camera JPEG worker', _cameraJpegWorker.dispose);
    _resourcePolicyCoordinator.dispose();
    await cleanup.attempt(
      'broadcast access sessions',
      () async => _broadcastAccess?.endAllSessions(),
    );
    await cleanup.attempt(
      'foreground service',
      ForegroundServiceController.stopServer,
    );
    if (_wakelockEnabled) {
      await cleanup.attempt('wakelock', WakelockPlus.disable);
      _wakelockEnabled = false;
    }
    await cleanup.attempt(
      'injected media source',
      () async => mediaSource?.stop(),
    );
    await cleanup.attempt('microphone capture', _microphoneCapture.dispose);
    await cleanup.attempt('alert subscription', () async {
      await _alertSubscription?.cancel();
    });
    _alertSubscription = null;
    await cleanup.attempt('analysis coordinator', () async {
      await _analysisCoordinator?.dispose();
    });
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    _frameBudget.reset();
    _activeClientRegistry.clear();
    _runtimeSessionClients.clear();
    _standaloneSessionDemands.clear();
    _sessionMediaDemands.clear();
    _sessionMediaTransports.clear();
    await cleanup.attempt('room features', _features.dispose);
    await cleanup.attempt('native playback demand', () async {
      await onPlaybackDemandChanged?.call(false);
    });
    await cleanup.attempt('room audio subscription', () async {
      await _roomAudioModeSubscription?.cancel();
    });
    _roomAudioModeSubscription = null;
    await cleanup.attempt('native luma subscription', () async {
      await _injectedLumaSubscription?.cancel();
    });
    _injectedLumaSubscription = null;
    await cleanup.attempt('service advertiser', () async {
      await _serviceAdvertiser?.dispose();
    });
    await cleanup.attempt('WebRTC gateway', () async {
      await webRtcGateway?.dispose();
    });
    await cleanup.attempt('video streams', _videoStreamService.closeAll);
    _videoStreamService.resetDiagnostics();
    await cleanup.attempt('audio streams', _audioStreamService.closeAll);
    _audioStreamService.resetDiagnostics();
    mediaSource?.resetDiagnostics();
    _jpegByteBudgetController.reset();
    tokenService.clearEphemeralState();
    await cleanup.attempt('token persistence', tokenService.flushPersistence);
    final controller = cameraController;
    cameraController = null;
    await cleanup.attempt(
      'camera controller',
      () async => controller?.dispose(),
    );
    _videoProbeEncodeUntilMs = null;
    await cleanup.attempt('HTTP server', () async {
      await _httpServer?.close(force: true);
    });
    for (final socket in _webSockets.toList()) {
      await cleanup.attempt('WebSocket', socket.close);
    }
    _webSockets.clear();
    _webSocketClientIds.clear();
    _eventClientSocketCounts.clear();
    _lastMotionSample = null;
    _lastMotionEnergy = 0;
    _cryActive = false;
    _lastCryActiveAtMs = null;
    if (cleanup.hasFailures) {
      onLog(
        'Server disposed with cleanup errors: '
        '${cleanup.failureMessages.join(' | ')}',
      );
    }
  }
}

class _CameraEncodeRequest {
  const _CameraEncodeRequest({
    required this.frame,
    required this.profile,
    required this.capturedAtMs,
    required this.capturedAtMonoUs,
    required this.traceId,
    required this.generation,
  });

  final TransferableCameraFrame frame;
  final MediaQualityProfile profile;
  final int capturedAtMs;
  final int capturedAtMonoUs;
  final String traceId;
  final int generation;
}

abstract interface class MediaPermissionGateway {
  Future<bool> requestCamera();
}

class PermissionHandlerMediaPermissionGateway
    implements MediaPermissionGateway {
  const PermissionHandlerMediaPermissionGateway({
    CameraPermissionGateway cameraPermissions =
        const MethodChannelCameraPermissionGateway(),
  }) : _cameraPermissions = cameraPermissions;

  final CameraPermissionGateway _cameraPermissions;

  @override
  Future<bool> requestCamera() async {
    var status = await _cameraPermissions.status();
    if (status.isDenied) status = await _cameraPermissions.request();
    return status.isGranted;
  }
}

typedef CameraMediaPermissionGateway = PermissionHandlerMediaPermissionGateway;

enum _AuthMode { none, bearer, streamToken, testAccess }

class _RouteSpec {
  const _RouteSpec(this.path, this.authMode, this.allowedMethods, this.handle);

  final String path;
  final _AuthMode authMode;
  final Set<String> allowedMethods;
  final Future<void> Function(HttpRequest request, String? clientId) handle;

  bool allowsMethod(String method) => allowedMethods.contains(method);
}

class HttpMethod {
  const HttpMethod._();

  static const get = 'GET';
  static const post = 'POST';
}
