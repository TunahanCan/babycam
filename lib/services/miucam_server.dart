import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../analysis/alert/alert_config.dart';
import '../analysis/alert/alert_engine.dart';
import '../analysis/alert/alert_event.dart';
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
import '../core/async/serialized_async_executor.dart';
import '../core/media/camera_permission_gateway.dart';
import '../core/media/adaptive_media_profile.dart';
import '../core/media/client_quality_tracker.dart';
import '../core/media/media_session_telemetry.dart';
import '../core/miucam_protocol.dart';
import '../core/network/local_network_guard.dart';
import '../core/protocol/device_feature_models.dart';
import '../core/protocol/miucam_protocol.dart' as protocol_v2;
import '../core/protocol/webrtc_signaling.dart';
import '../core/security/transport_config.dart';
import '../core/security/trusted_client_token.dart';
import '../features/server/pairing/pairing_token_service.dart';
import '../features/server/media/mjpeg_stream_service.dart';
import '../features/server/media/microphone_capture_service.dart';
import '../features/server/media/server_media_source.dart';
import '../features/server/media/wav_audio_stream_service.dart';
import '../features/server/media/webrtc/webrtc_server_gateway.dart';
import '../l10n/app_strings.dart';
import 'configuration_service.dart';
import 'monetization/broadcast_access_service.dart';
import 'discovery/miucam_service_discovery.dart';
import 'server/active_client_registry.dart';
import 'server/alert_protocol_adapter.dart';
import 'server/baby_monitor_feature_services.dart';
import 'server/baby_monitor_feature_controller.dart';
import 'server/best_effort_operation_collector.dart';
import 'server/bounded_json_body_reader.dart';
import 'server/camera_jpeg_worker.dart';
import 'server/jpeg_byte_budget_controller.dart';
import 'server/media_analysis_coordinator.dart';
import 'server/media_frame_policy.dart';
import 'server/media_analysis_metrics.dart';
import 'server/media_profile_apply_queue.dart';
import 'server/media_quality_selector.dart';
import 'server/media_resource_governor.dart';
import 'server/miucam_event_socket_controller.dart';
import 'server/miucam_http_dispatcher.dart';
import 'server/pcm16_frame_assembler.dart';
import 'server/request_auth_guard.dart';
import 'server/room_audio_coordinator.dart';
import 'server/server_device_identity_resolver.dart';
import 'server/server_resource_policy_coordinator.dart';
import 'server/server_session_registry.dart';
import 'server/server_media_transport_controller.dart';
import 'server/server_session_controller.dart';
import 'server/stream_backpressure_gate.dart';
import 'platform/device_capability_probe.dart';
import 'platform/battery_snapshot_provider.dart';
import 'platform/foreground_service_controller.dart';
import 'platform/device_resource_snapshot_provider.dart';
import 'network_address_provider.dart';

part 'server/miucam_server_routes.dart';
part 'server/miucam_server_http_controllers.dart';
part 'server/miucam_server_session_http_controller.dart';
part 'server/miucam_server_media_controllers.dart';

class MiuCamServer {
  MiuCamServer({
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
    this.maxMediaConnectionsPerClient = 3,
    int? maxTotalMediaConnections,
    this.maxEventSocketsPerClient = 2,
    int? maxTotalEventSockets,
    this.startMediaOnSessionStart = true,
    this.mediaSource,
    MediaPermissionGateway? mediaPermissions,
    this.httpPort = MiuCamProtocol.httpPort,
    ComfortAudioService? comfortAudioService,
    NightLightController? nightLightController,
    TalkSessionRegistry? talkSessions,
    BabyMonitorFeatureController? featureController,
    MiuCamServiceAdvertiser? serviceAdvertiser,
    MiuCamDiscoveryDeviceIdProvider? serverDeviceIdProvider,
    BatterySnapshotProvider? batteryProvider,
    BroadcastAccessService? broadcastAccess,
    DeviceResourceSnapshotProvider? deviceResourceProvider,
    MediaResourceGovernor? mediaResourceGovernor,
    MediaSessionTelemetry? mediaTelemetry,
    this.webRtcGateway,
    this.onBroadcastAccessChanged,
  })  : maxTotalMediaConnections =
            maxTotalMediaConnections ?? maxActiveWatchClients * 3,
        maxTotalEventSockets =
            maxTotalEventSockets ?? maxActiveWatchClients * 2,
        tokenService = tokenService ?? PairingTokenService(),
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
      maxMediaConnectionsPerClient: maxMediaConnectionsPerClient,
      maxTotalMediaConnections: this.maxTotalMediaConnections,
      maxEventSocketsPerClient: maxEventSocketsPerClient,
      maxTotalEventSockets: this.maxTotalEventSockets,
    );
    _authGuard = RequestAuthGuard(tokenService: this.tokenService);
    _sessionController = ServerSessionController(
      activeClients: _activeClientRegistry,
    );
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
    _media = ServerMediaTransportController(
      sampleRate: _audioSampleRate,
      channels: _audioChannels,
      bitsPerSample: _audioBitsPerSample,
      telemetry: _mediaTelemetry,
    );
    _eventSockets = MiuCamEventSocketController(
      activeClients: _activeClientRegistry,
      resolveClientId: _webSocketClientId,
      writeConnectionLimitError: _writeConnectionLimitError,
      onClientConnected: onAlertClientConnected,
      onClientDisconnected: onAlertClientDisconnected,
      isDisposed: () => _disposed,
      connectedLog: strings.webSocketClientConnected,
      onLog: onLog,
    );
    final routes = _buildMiuCamRoutes(this);
    _httpDispatcher = MiuCamHttpDispatcher(
      routes: routes,
      isDisposed: () => _disposed,
      isRemoteAddressAllowed: (address) =>
          _effectiveLocalNetworkGuard.isAllowedRemoteAddress(address),
      isEventSocketPath: (path) =>
          path == '/ws/stream' || path == protocol_v2.MiuCamProtocolV2.events,
      handleEventSocket: _eventSockets.handleUpgrade,
      authorize: _authorizeRoute,
      writeLandingPage: _writeLandingPage,
      onLog: onLog,
    );
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
  final int maxMediaConnectionsPerClient;
  final int maxTotalMediaConnections;
  final int maxEventSocketsPerClient;
  final int maxTotalEventSockets;
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
  late final ActiveClientRegistry _activeClientRegistry;
  late final RequestAuthGuard _authGuard;
  late final ServerMediaTransportController _media;
  late final MiuCamEventSocketController _eventSockets;
  final BabyMonitorFeatureController _features;
  final MiuCamServiceAdvertiser? _serviceAdvertiser;
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
  late final MiuCamHttpDispatcher _httpDispatcher;
  late final ServerSessionController _sessionController;

  MjpegStreamService get _videoStreamService => _media.video;
  WavAudioStreamService get _audioStreamService => _media.audio;
  MicrophoneCaptureService get _microphoneCapture => _media.microphone;
  ServerSessionController get _sessionOperations => _sessionController;
  ServerSessionRegistry get _sessions => _sessionController.registry;

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
  bool _injectedVideoDemand = false;
  bool _injectedAudioDemand = false;
  final _injectedMediaOperations = SerializedAsyncExecutor();
  Uint8List? _latestJpeg;
  int _videoFramesDroppedBeforeEncode = 0;
  int _videoFramesSkippedByPolicy = 0;
  int _videoFramesCaptured = 0;
  int _videoTraceSequence = 0;
  bool _jpegEncodeInFlight = false;
  _CameraEncodeRequest? _pendingCameraEncode;
  int _cameraEncodeGeneration = 0;
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
  static const maxJsonRequestBodyBytes = 64 * 1024;
  static const _jsonBodyReader = BoundedJsonBodyReader(
    maxBytes: maxJsonRequestBodyBytes,
  );

  Future<String> start() async {
    if (_disposed) throw StateError('MiuCamServer is disposed.');
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
    if (_disposed) throw StateError('MiuCamServer is disposed.');
    if (config.webRtcPilotEnabled) {
      await webRtcGateway?.initialize();
    }
    if (_httpServer == null) {
      late final HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv6,
          httpPort,
          v6Only: false,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          httpPort,
        );
      }
      if (_disposed) {
        await server.close(force: true);
        throw StateError('MiuCamServer is disposed.');
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
          name: 'MiuCam Bebek Odası',
          deviceId: deviceId,
          port: _httpServer!.port,
          protocolVersion: protocol_v2.MiuCamProtocolV2.schemaVersion,
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

  List<TrustedClientRecord> get trustedClients => tokenService.trustedClients;

  Future<void> revokeTrustedClient(String clientId) async {
    if (_disposed) return;
    await tokenService.revokeClientPersisted(clientId);
    await _disconnectRevokedClient(clientId);
  }

  Future<void> revokeAllTrustedClients() async {
    if (_disposed) return;
    final clientIds = tokenService.trustedClients
        .map((client) => client.clientId)
        .toList(growable: false);
    await tokenService.revokeAllPersisted();
    for (final clientId in clientIds) {
      await _disconnectRevokedClient(clientId);
    }
  }

  Future<void> _disconnectRevokedClient(String clientId) async {
    await _eventSockets.closeClient(clientId);
    try {
      await _features.stopTalk(clientId: clientId);
    } catch (error) {
      onLog('Revoked client talk cleanup failed ($clientId): $error');
    }
    final errors = await _sessionOperations.run(
      () => _cleanupClientSession(clientId, closeWebRtc: true),
    );
    if (errors.isNotEmpty) {
      onLog(
        'Revoked client cleanup completed with errors ($clientId): '
        '${errors.join(' | ')}',
      );
    }
  }

  Future<void> startMediaRuntime() async {
    await startVideoRuntime();
    await startAudioRuntime();
  }

  Future<void> startVideoRuntime() async {
    if (_disposed) throw StateError('MiuCamServer is disposed.');
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
    if (_disposed) throw StateError('MiuCamServer is disposed.');
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

  Future<void> _handleRequest(HttpRequest request) async {
    await _httpDispatcher.dispatch(request);
  }

  Future<({bool ok, String? clientId})> _authorizeRoute(
    HttpRequest request,
    MiuCamRouteAuthMode mode,
  ) async {
    switch (mode) {
      case MiuCamRouteAuthMode.none:
        return (ok: true, clientId: null);
      case MiuCamRouteAuthMode.bearer:
        final auth = await _requireTrustedAuth(request);
        return (ok: auth != null, clientId: auth?.clientId);
      case MiuCamRouteAuthMode.streamToken:
        // Stream tokens intentionally stop at media endpoints; state-changing
        // endpoints must still prove identity with the trusted Bearer token.
        final clientId = await _requireStreamAuth(request);
        return (ok: clientId != null, clientId: clientId);
    }
  }

  String? _webSocketClientId(HttpRequest request) {
    return _authGuard.trusted(request)?.clientId;
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
    final headerToken = request.headers.value('X-MiuCam-Talk-Token');
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
    final video = _sessions.standaloneDemands.any((value) => value.video);
    final audio = _sessions.standaloneDemands.any((value) => value.audio);
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

  Future<Map<Object?, Object?>?> _readJsonObjectBody(HttpRequest request) =>
      _jsonBodyReader.readObject(request);

  Future<void> _rejectInvalidJsonBody(
    HttpRequest request,
    Object error,
  ) async {
    if (error is RequestBodyTooLargeException) {
      request.response
        ..statusCode = HttpStatus.requestEntityTooLarge
        ..persistentConnection = false;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'REQUEST_BODY_TOO_LARGE',
        'message': 'The request body is too large.',
        'maxBytes': error.maxBytes,
      });
      return;
    }
    if (error is RequestBodyReadTimeoutException) {
      request.response
        ..statusCode = HttpStatus.requestTimeout
        ..persistentConnection = false;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'REQUEST_BODY_TIMEOUT',
        'message': 'The request body timed out.',
      });
      return;
    }
    request.response.statusCode = HttpStatus.badRequest;
    await request.response.close();
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
    return clientId;
  }

  Future<StreamAttachResult?> _reserveMediaConnection(
    HttpResponse response,
    String clientId,
  ) async {
    try {
      return _activeClientRegistry.attachStream(clientId);
    } on ActiveClientLimitException {
      response.statusCode = HttpStatus.tooManyRequests;
      await _writeJson(response, {
        'ok': false,
        'code': ActiveClientLimitException.code,
        'message': ActiveClientLimitException.userMessage,
      });
      return null;
    } on ConnectionLimitException catch (error) {
      await _writeConnectionLimitError(response, error);
      return null;
    }
  }

  Future<void> _writeConnectionLimitError(
    HttpResponse response,
    ConnectionLimitException error,
  ) async {
    response.statusCode = error.scope == ConnectionLimitScope.client
        ? HttpStatus.tooManyRequests
        : HttpStatus.serviceUnavailable;
    response.headers.set(HttpHeaders.retryAfterHeader, '1');
    await _writeJson(response, {
      'ok': false,
      'code': error.code,
      'message': error.userMessage,
      'channel': error.channel,
      'maxConnections': error.maxConnections,
    });
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
    _analysisCoordinator?.markVideoDiscontinuity();
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
    _analysisCoordinator?.markAudioDiscontinuity();
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
    // Injected sources do not necessarily own Flutter camera or microphone
    // objects; the Android service source owns its platform lifecycle natively.
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
    // Never carry a pre-talk/pre-comfort cry candidate across locally
    // generated audio. Calibration is retained; only temporal evidence resets.
    _analysisCoordinator?.markAudioDiscontinuity();
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

  Future<void> _handleMjpeg(
    HttpResponse response,
    String clientId, {
    required void Function() onDetached,
  }) async {
    await _videoStreamService.attachClient(
      response,
      clientId,
      firstFrame: _latestJpeg,
      onDetached: onDetached,
    );
  }

  Future<void> _handleAudio(
    HttpResponse response,
    String clientId, {
    required void Function() onDetached,
  }) async {
    await _audioStreamService.attachClient(
      response,
      clientId,
      onDetached: onDetached,
    );
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
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>MiuCam</title></head>
<body style="margin:0;background:#111;color:white;font-family:-apple-system,BlinkMacSystemFont,sans-serif">
  <main style="padding:16px"><h1>${strings.appTitle}</h1><p>${strings.streamActiveHtml}</p></main>
</body></html>''');
    await response.close();
  }

  int _broadcastBinary(List<int> data) => _eventSockets.broadcastBinary(data);

  int _broadcastText(String data) => _eventSockets.broadcastText(data);

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
    _activeClientRegistry.clear(includeEventSockets: true);
    _sessions.clear();
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
    await cleanup.attempt('HTTP server', () async {
      await _httpServer?.close(force: true);
    });
    await _eventSockets.closeAll(
      closeSafely: (operation) => cleanup.attempt('WebSocket', operation),
    );
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

typedef _AuthMode = MiuCamRouteAuthMode;
typedef _RouteSpec = MiuCamHttpRoute;
