import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:record/record.dart';
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
import '../core/mimicam_protocol.dart';
import '../core/network/local_network_guard.dart';
import '../core/protocol/mimicam_protocol.dart' as protocol_v2;
import '../core/security/transport_config.dart';
import '../features/server/pairing/pairing_token_service.dart';
import '../l10n/app_strings.dart';
import 'configuration_service.dart';
import 'motion_analyzer.dart' show CameraImageJpegEncoder;
import 'server/active_client_registry.dart';
import 'server/alert_protocol_adapter.dart';
import 'server/jpeg_byte_budget_controller.dart';
import 'server/media_analysis_coordinator.dart';
import 'server/media_frame_policy.dart';
import 'server/media_analysis_metrics.dart';
import 'server/media_quality_selector.dart';
import 'server/request_auth_guard.dart';
import 'server/stream_backpressure_gate.dart';
import 'platform/device_capability_probe.dart';
import 'platform/foreground_service_controller.dart';
import 'network_address_provider.dart';

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
    DeviceCapabilityTier? deviceTier,
    PairingTokenService? tokenService,
    this.transportConfig = TransportConfig.local,
    this.localNetworkGuard = const LocalNetworkGuard(),
    this.maxActiveWatchClients = 5,
    this.startMediaOnSessionStart = true,
    MediaPermissionGateway? mediaPermissions,
    this.httpPort = MimiCamProtocol.httpPort,
  })  : tokenService = tokenService ?? PairingTokenService(),
        mediaPermissions =
            mediaPermissions ?? const CameraMediaPermissionGateway(),
        _deviceTier = deviceTier ?? DeviceCapabilityProbe.detectTier() {
    _activeMediaProfile = MediaQualityProfile.forDeviceTier(_deviceTier);
    _frameBudget.updateMinInterval(_activeMediaProfile.frameInterval);
    _activeClientRegistry = ActiveClientRegistry(
      tokenService: this.tokenService,
      maxActiveClients: maxActiveWatchClients,
    );
    _authGuard = RequestAuthGuard(tokenService: this.tokenService);
  }

  final bool enableLegacyWebSocketMediaPackets;
  final bool enableAudioAutoCalibration;

  final ConfigurationService config;
  final AppStrings strings;
  final void Function(String message) onLog;
  final void Function(String message) onAlert;
  final void Function(MediaQualityProfile profile)? onMediaProfileChanged;
  final FutureOr<void> Function(
    String clientId, {
    required bool video,
    required bool audio,
  })? onStreamSessionStarted;
  final FutureOr<void> Function(String clientId)? onStreamSessionStopped;
  final PairingTokenService tokenService;
  final MediaPermissionGateway mediaPermissions;
  final TransportConfig transportConfig;
  final LocalNetworkGuard localNetworkGuard;
  final int maxActiveWatchClients;
  final bool startMediaOnSessionStart;
  final int httpPort;
  AudioRecorder? _audioRecorder;
  MediaAnalysisCoordinator? _analysisCoordinator;
  MediaAnalysisMetrics? _analysisMetrics;
  StreamSubscription<AlertEvent>? _alertSubscription;
  final _webSockets = <WebSocket>{};
  final _mjpegClients = <HttpResponse>{};
  final _audioClients = <HttpResponse>{};
  final _mjpegClientIds = <HttpResponse, String>{};
  final _audioClientIds = <HttpResponse, String>{};
  final _audioBusyClientIds = <String>{};
  final _mjpegBackpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.video);
  final _audioBackpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.audio);
  late final ActiveClientRegistry _activeClientRegistry;
  late final RequestAuthGuard _authGuard;

  CameraController? cameraController;
  DeviceCapabilityTier get deviceTier => _deviceTier;
  MediaQualityProfile get activeMediaProfile => _activeMediaProfile;
  Map<String, Object?> get mediaCapabilities => _mediaCapabilities();

  HttpServer? _httpServer;
  bool _httpServerListening = false;
  bool _pairingModeActive = false;
  bool _disposed = false;
  bool _wakelockEnabled = false;
  Future<void>? _mediaStart;
  StreamSubscription<Uint8List>? _audioSubscription;
  Uint8List? _latestJpeg;
  int? _lastCameraFrameAtMs;
  int? _lastVideoFrameEncodedAtMs;
  int? _lastVideoClientWriteAtMs;
  int? _lastAudioChunkAtMs;
  int? _lastAudioClientWriteAtMs;
  int? _lastAlertBroadcastAtMs;
  int? _videoProbeEncodeUntilMs;
  int _videoFramesEncoded = 0;
  int _videoFramesStreamed = 0;
  int _audioChunksCaptured = 0;
  int _audioChunksStreamed = 0;
  int _alertsBroadcast = 0;
  int _alertWebSocketDeliveries = 0;
  int _lastJpegBytes = 0;
  int _lastAudioChunkBytes = 0;
  int _lastAudioClientWriteBytes = 0;
  int _lastAlertDeliveredWebSocketClients = 0;
  bool? _lastMicrophonePermissionGranted;
  String? _lastAudioStartError;
  int _lastAudioDebugLog = 0;
  final _frameBudget = MediaFrameBudget();
  final _frameBudgetManager = const FrameBudgetManager();
  final _encodingPolicy = const MediaEncodingPolicy();
  final _jpegByteBudgetController = JpegByteBudgetController();
  final _mediaQualitySelector = MediaQualitySelector();
  final DeviceCapabilityTier _deviceTier;
  late MediaQualityProfile _activeMediaProfile;
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

  Future<String> startPairingMode() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    final address = await NetworkAddressProvider.localHttpAddress() ??
        '${InternetAddress.loopbackIPv4.address}:$httpPort';
    final host = address.split(':').first;
    if (_httpServer == null) {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        httpPort,
        shared: true,
      );
      if (_disposed) {
        await server.close(force: true);
        throw StateError('MimiCamServer is disposed.');
      }
      _httpServer = server;
    }
    if (!_httpServerListening) {
      _httpServerListening = true;
      _httpServer!.listen(_handleRequest);
    }
    _pairingModeActive = true;
    final url = '${transportConfig.httpScheme}://$host:${_httpServer!.port}/';
    onLog(strings.serverStartedLog(url));
    return url;
  }

  void stopPairingMode() {
    _pairingModeActive = false;
  }

  Future<void> startMediaRuntime() async {
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    final existingController = cameraController;
    if (existingController != null) {
      if (existingController.value.isInitialized) return;
      await existingController.dispose();
      if (cameraController == existingController) cameraController = null;
    }
    final existingStart = _mediaStart;
    if (existingStart != null) return existingStart;

    final start = _startMediaRuntime();
    _mediaStart = start;
    try {
      await start;
    } finally {
      if (_mediaStart == start) _mediaStart = null;
    }
  }

  Future<void> _startMediaRuntime() async {
    await _ensureCameraPermission();
    final cameras = await availableCameras();
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    _initializeAnalysisPipeline();

    final controller = CameraController(
      cameras.first,
      _resolutionPresetFor(_activeMediaProfile),
      enableAudio: false,
    );
    cameraController = controller;
    try {
      await controller.initialize();
      if (_disposed) {
        throw StateError('MimiCamServer is disposed.');
      }
      await controller.startImageStream(_handleCameraFrame);
      await _startAudioAnalysisBestEffort();
      if (_disposed) {
        throw StateError('MimiCamServer is disposed.');
      }
      await WakelockPlus.enable();
      _wakelockEnabled = true;
      await ForegroundServiceController.startServer();
    } catch (_) {
      await stopMediaRuntime();
      rethrow;
    }
  }

  void _initializeAnalysisPipeline() {
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
    if (cameraController == null && _audioSubscription == null) return;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    _initializeAnalysisPipeline();
  }

  Future<void> _startAudioAnalysis() async {
    final audioRecorder = _audioRecorder ??= AudioRecorder();
    _lastAudioStartError = null;
    final hasPermission = await audioRecorder.hasPermission();
    _lastMicrophonePermissionGranted = hasPermission;
    if (!hasPermission) {
      onLog(strings.microphonePermissionMissing);
      return;
    }
    final stream = await audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _audioSampleRate,
      numChannels: _audioChannels,
    ));
    _audioSubscription = stream.listen((chunk) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _lastAudioChunkAtMs = nowMs;
      _lastAudioChunkBytes = chunk.length;
      _audioChunksCaptured++;
      _analysisCoordinator?.onAudioChunk(AudioChunk(
        pcm16le: chunk,
        sampleRate: _audioSampleRate,
        channels: _audioChannels,
        timestampMs: nowMs,
      ));
      if (enableLegacyWebSocketMediaPackets) {
        _broadcastBinary([MimiCamProtocol.packetAudioPcm16Le, ...chunk]);
      }
      for (final client in _audioClients.toList()) {
        final clientId = _audioClientIds[client];
        // Busy clients skip the current chunk instead of growing a queue; live
        // audio freshness is more important than delayed backlog playback.
        if (!_audioBackpressure.tryMarkBusy(client)) continue;
        if (clientId != null) _audioBusyClientIds.add(clientId);
        final startedAt = DateTime.now();
        try {
          client.add(chunk);
          client.flush().then<void>((_) {
            _audioChunksStreamed++;
            _lastAudioClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
            _lastAudioClientWriteBytes = chunk.length;
            _audioBackpressure.recordSuccess(
              client,
              duration: DateTime.now().difference(startedAt),
            );
          }).catchError((Object _) {
            _audioBackpressure.recordFailure(client);
            _removeAudioClient(client);
          }).whenComplete(() {
            _audioBackpressure.markIdle(client);
            if (clientId != null) _audioBusyClientIds.remove(clientId);
          });
        } catch (_) {
          _audioBackpressure.recordFailure(client);
          _removeAudioClient(client);
          if (clientId != null) _audioBusyClientIds.remove(clientId);
        }
      }
      _logAudioDiagnostics();
    });
  }

  Future<void> _startAudioAnalysisBestEffort() async {
    if (_audioSubscription != null) return;
    try {
      await _startAudioAnalysis();
    } catch (error) {
      _analysisMetrics?.recordAudioError();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _lastAudioStartError = error.toString();
      onLog('Ses başlatılamadı: $error');
    }
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
    _broadcastBinary(AlertProtocolAdapter.toLegacyAlertPacket(event));
  }

  void _handleCameraFrame(CameraImage frame) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastCameraFrameAtMs = nowMs;
    _lastMotionEnergy = _estimateMotionEnergy(frame);
    _updateContentAwareFrameBudget(nowMs);
    if (!_frameBudget.shouldProcess(nowMs)) return;

    try {
      final shouldEncodeJpeg = _encodingPolicy.shouldEncodeJpeg(
        hasMjpegClients: _mjpegClients.isNotEmpty || _isVideoProbeActive(nowMs),
        legacyWebSocketEnabled: enableLegacyWebSocketMediaPackets,
      );
      if (shouldEncodeJpeg) {
        final jpegQuality = _jpegByteBudgetController.qualityFor(
          _activeMediaProfile,
        );
        final jpeg = CameraImageJpegEncoder.encode(
          frame,
          quality: jpegQuality,
        );
        _jpegByteBudgetController.recordEncodedFrame(
          _activeMediaProfile,
          byteLength: jpeg.length,
          atMs: nowMs,
        );
        _latestJpeg = jpeg;
        _lastVideoFrameEncodedAtMs = nowMs;
        _lastJpegBytes = jpeg.length;
        _videoFramesEncoded++;
        if (enableLegacyWebSocketMediaPackets) {
          _broadcastBinary([MimiCamProtocol.packetVideoMjpeg, ...jpeg]);
        }
        for (final client in _mjpegClients.toList()) {
          final clientId = _mjpegClientIds[client];
          if (clientId != null && _audioBusyClientIds.contains(clientId)) {
            _mjpegBackpressure.recordSkippedVideoFrame(client);
            continue;
          }
          // The stream is latest-frame oriented: slow clients drop frames
          // rather than buffering old JPEGs and increasing memory pressure.
          if (!_mjpegBackpressure.tryMarkBusy(client)) continue;
          final startedAt = DateTime.now();
          _writeMjpegFrame(client, jpeg).then<void>((_) {
            _recordVideoClientWrite(
              client,
              duration: DateTime.now().difference(startedAt),
            );
          }).catchError((Object _) {
            _mjpegBackpressure.recordFailure(client);
            _removeMjpegClient(client);
          }).whenComplete(() => _mjpegBackpressure.markIdle(client));
        }
      }
      _analysisCoordinator?.onCameraFrame(_toLumaFrame(frame, nowMs));
    } catch (error) {
      onLog('Frame işlenemedi: $error');
    }
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
    if (_disposed) {
      await request.response.close();
      return;
    }
    final remoteAddress = request.connectionInfo?.remoteAddress;
    // This is not a firewall; it reduces accidental public exposure if the
    // socket becomes reachable outside the local Wi-Fi network.
    if (remoteAddress != null &&
        !localNetworkGuard.isAllowedRemoteAddress(remoteAddress)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if ((request.uri.path == '/ws/stream' ||
            request.uri.path == protocol_v2.MimiCamProtocolV2.events) &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      if (!_isAuthorized(request)) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _webSockets.add(socket);
      socket.done.whenComplete(() => _webSockets.remove(socket));
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
      await _writeLandingPage(request.response);
      return;
    }
    if (!route.allowsMethod(request.method)) {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, route.allowedMethods.join(', '));
      await request.response.close();
      return;
    }

    final auth = await _authorizeRoute(request, route.authMode);
    if (!auth.ok) return;
    await route.handle(request, auth.clientId);
  }

  List<_RouteSpec> get _routes => [
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
          protocol_v2.MimiCamProtocolV2.qualityReport,
          _AuthMode.bearer,
          const {HttpMethod.post},
          (request, _) => _handleQualityReport(request),
        ),
        _RouteSpec(
          protocol_v2.MimiCamProtocolV2.statusPublic,
          _AuthMode.none,
          const {HttpMethod.get},
          (request, _) => _handlePublicStatus(request),
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
      ];

  _RouteSpec? _routeFor(String path) {
    for (final route in _routes) {
      if (route.path == path) return route;
    }
    return null;
  }

  Future<({bool ok, String? clientId})> _authorizeRoute(
    HttpRequest request,
    _AuthMode mode,
  ) async {
    switch (mode) {
      case _AuthMode.none:
        return (ok: true, clientId: null);
      case _AuthMode.bearer:
        return (ok: await _requireAuth(request), clientId: null);
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
    await _writeJson(request.response, {
      'service': 'mimicam',
      'pairing': true,
      'serverDeviceId': 'server_local',
      'serverName': 'Bebek Odası',
      'pairingNonce': tokenService.createPairingNonce(),
      'transport': transportConfig.payloadTransport,
      'capabilities': _mediaCapabilities(),
    });
  }

  Future<void> _handlePrivateStatus(HttpRequest request) async {
    await _writeJson(request.response, {
      'videoClients': _mjpegClients.length,
      'audioClients': _audioClients.length,
      'webSocketClients': _webSockets.length,
      'activeStreamClients': _activeClientRegistry.activeClientCount,
      'qualityReportClients': _activeClientRegistry.qualityReportCount,
      'hasFrame': _latestJpeg != null,
      'deviceTier': _deviceTier.name,
      'mediaProfile': _effectiveMediaProfile().toJson(),
      'jpegBytesPerSecond': _jpegByteBudgetController.lastActualBytesPerSecond(
        _activeMediaProfile,
      ),
      if (_analysisCoordinator != null) ..._analysisCoordinator!.diagnostics(),
    });
  }

  Future<void> _handleTestStatus(HttpRequest request) async {
    await _writeJson(request.response, _testDiagnostics());
  }

  Future<void> _handleTestStart(HttpRequest request) async {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    Object? error;
    try {
      await startMediaRuntime();
    } catch (caught) {
      error = caught;
      request.response.statusCode = HttpStatus.serviceUnavailable;
    }
    await _writeJson(request.response, {
      'ok': error == null,
      'startedAtMs': startedAtMs,
      'completedAtMs': DateTime.now().millisecondsSinceEpoch,
      if (error != null) 'error': error.toString(),
      'diagnostics': _testDiagnostics(),
    });
  }

  Future<void> _handleTestProbe(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final waitMs =
        _intFrom(body?['waitMs'], defaultValue: 1500).clamp(0, 5000).toInt();
    final startRuntime = _boolFrom(body?['startRuntime'], defaultValue: true);
    final requireVideo = _boolFrom(body?['requireVideo'], defaultValue: true);
    final requireAudio = _boolFrom(body?['requireAudio'], defaultValue: true);
    final emitAlert = _boolFrom(body?['emitAlert'], defaultValue: false);
    final requireEvents =
        _boolFrom(body?['requireEvents'], defaultValue: emitAlert);
    final requireEventDelivery =
        _boolFrom(body?['requireEventDelivery'], defaultValue: false);

    final before = _probeCounters();
    Object? startError;
    if (requireVideo) {
      _videoProbeEncodeUntilMs =
          DateTime.now().millisecondsSinceEpoch + waitMs + 500;
    }
    if (startRuntime) {
      try {
        await startMediaRuntime();
      } catch (error) {
        startError = error;
      }
    }
    if (emitAlert) _broadcastTestAlert(body);

    final deadline = DateTime.now().millisecondsSinceEpoch + waitMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline &&
        !_probeReady(
          before,
          requireVideo: requireVideo,
          requireAudio: requireAudio,
          requireEvents: requireEvents,
          requireEventDelivery: requireEventDelivery,
        )) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_videoProbeEncodeUntilMs != null &&
        DateTime.now().millisecondsSinceEpoch >= _videoProbeEncodeUntilMs!) {
      _videoProbeEncodeUntilMs = null;
    }

    final checks = _probeChecks(
      before,
      requireVideo: requireVideo,
      requireAudio: requireAudio,
      requireEvents: requireEvents,
      requireEventDelivery: requireEventDelivery,
    );
    final ok = startError == null && checks.values.every((value) => value);
    if (!ok) request.response.statusCode = HttpStatus.serviceUnavailable;
    await _writeJson(request.response, {
      'ok': ok,
      'waitMs': waitMs,
      if (startError != null) 'startError': startError.toString(),
      'checks': checks,
      'before': before.toJson(),
      'after': _probeCounters().toJson(),
      'diagnostics': _testDiagnostics(),
    });
  }

  Future<void> _handleTestAlert(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final event = _broadcastTestAlert(body);
    await _writeJson(request.response, {
      'ok': true,
      'alert': event.toJson(),
      'deliveredWebSocketClients': _lastAlertDeliveredWebSocketClients,
      'diagnostics': _testDiagnostics(),
    });
  }

  Future<void> _handleVideoRoute(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) return;
    try {
      await startMediaRuntime();
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
      await startMediaRuntime();
      await _startAudioAnalysisBestEffort();
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
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      if (json is! Map ||
          tokenService.validateAndConsumeNonce(
                  json['pairingNonce']?.toString() ?? '') ==
              false) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final token = tokenService.issueTrustedClientToken(
          clientName: json['clientName']?.toString() ?? 'Client',
          deviceId: json['deviceId']?.toString() ?? 'client');
      await _writeJson(request.response, {
        'serverDeviceId': 'server_local',
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
      await request.response.close();
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

  Future<void> _handleSessionStart(HttpRequest request) async {
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
    late final ActiveSessionStartResult startResult;
    try {
      startResult = _activeClientRegistry.startSession(clientId);
    } on ActiveClientLimitException {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await _writeJson(request.response, {
        'ok': false,
        'code': ActiveClientLimitException.code,
        'message': ActiveClientLimitException.userMessage,
      });
      return;
    }
    try {
      await _applyMediaProfileForCurrentDemand();
      if (startMediaOnSessionStart) await startMediaRuntime();
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': startResult.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
        'streamToken': startResult.streamToken.token,
        'streamTokenExpiresAtMs': startResult.streamToken.expiresAtMs,
        'video': demand.video,
        'audio': demand.audio,
      });
      _notifyStreamSessionStarted(
        startResult.clientId,
        video: demand.video,
        audio: demand.audio,
      );
    } catch (error) {
      if (startResult.createdActiveSlot) {
        _activeClientRegistry.stopSession(startResult.clientId);
      }
      request.response.statusCode = HttpStatus.internalServerError;
      onLog('Medya başlatılamadı: $error');
      await _writeJson(request.response, {
        'ok': false,
        'code': 'MEDIA_START_FAILED',
        'message': error.toString(),
      });
    }
  }

  Future<void> _handleSessionStop(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonObjectBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final clientId = _clientIdForRequest(request, json);
    try {
      _activeClientRegistry.stopSession(clientId);
      if (_activeClientRegistry.activeClientCount == 0 &&
          _mjpegClients.isEmpty &&
          _audioClients.isEmpty) {
        await stopMediaRuntime();
      } else {
        await _applyMediaProfileForCurrentDemand();
      }
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      });
      _notifyStreamSessionStopped(clientId);
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
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
      _activeClientRegistry.updateQualityReport(report);
      await _applyMediaProfileForCurrentDemand();
      await _writeJson(request.response, {
        'ok': true,
        'deviceTier': _deviceTier.name,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'effectiveNetworkTier': _activeClientRegistry.effectiveTier().name,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  }

  Future<void> _applyMediaProfileForCurrentDemand() async {
    final nextProfile = _mediaQualitySelector.select(
      deviceTier: _deviceTier,
      networkTier: _activeClientRegistry.effectiveTier(),
      activeClientCount: _activeClientRegistry.activeClientCount,
      worstReport: _activeClientRegistry.worstQualityReport(),
      qualityReports: _activeClientRegistry.activeQualityReports(),
      backpressureMetrics: _combinedBackpressureMetrics(),
    );
    await _setActiveMediaProfile(nextProfile);
  }

  void _notifyStreamSessionStarted(
    String clientId, {
    required bool video,
    required bool audio,
  }) {
    final callback = onStreamSessionStarted;
    if (callback == null) return;
    unawaited(
      Future<void>.sync(
        () => callback(clientId, video: video, audio: audio),
      ).catchError((_) {}),
    );
  }

  void _notifyStreamSessionStopped(String clientId) {
    final callback = onStreamSessionStopped;
    if (callback == null) return;
    unawaited(Future<void>.sync(() => callback(clientId)).catchError((_) {}));
  }

  StreamBackpressureMetrics _combinedBackpressureMetrics() =>
      combineBackpressureMetrics([
        _mjpegBackpressure.aggregateMetrics(),
        _audioBackpressure.aggregateMetrics(),
      ]);

  bool _isAudioReliable() =>
      _audioBackpressure.aggregateMetrics().skippedAudioChunks == 0;

  bool _isVideoReliable() =>
      _mjpegBackpressure.aggregateMetrics().skippedVideoFrames < 3;

  Future<void> _setActiveMediaProfile(MediaQualityProfile nextProfile) async {
    final previousProfile = _activeMediaProfile;
    if (previousProfile.cameraPresetKey != nextProfile.cameraPresetKey) {
      await _restartCameraWithProfile(nextProfile);
    }
    _activeMediaProfile = nextProfile;
    _frameBudget.updateMinInterval(_activeMediaProfile.frameInterval);
    if (previousProfile.id != _activeMediaProfile.id) {
      onLog('Medya profili: ${_activeMediaProfile.summary}');
      onMediaProfileChanged?.call(_activeMediaProfile);
    }
  }

  Future<void> _restartCameraWithProfile(MediaQualityProfile profile) async {
    final previousController = cameraController;
    if (previousController == null) return;
    cameraController = null;
    _latestJpeg = null;
    _frameBudget.reset();
    await previousController.dispose();
    if (_disposed) return;

    await _ensureCameraPermission();
    final cameras = await availableCameras();
    if (_disposed) return;
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    final nextController = CameraController(
      cameras.first,
      _resolutionPresetFor(profile),
      enableAudio: false,
    );
    try {
      await nextController.initialize();
      if (_disposed) {
        await nextController.dispose();
        return;
      }
      cameraController = nextController;
      await nextController.startImageStream(_handleCameraFrame);
    } catch (_) {
      if (cameraController == nextController) cameraController = null;
      await nextController.dispose();
      rethrow;
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
        'events': 'json',
        'maxClients': maxActiveWatchClients,
        'transportPreferred': 'webrtc',
        'deviceTier': _deviceTier.name,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      };

  MediaQualityProfile _effectiveMediaProfile() => _activeMediaProfile.copyWith(
        jpegQuality: _jpegByteBudgetController.qualityFor(_activeMediaProfile),
      );

  ResolutionPreset _resolutionPresetFor(MediaQualityProfile profile) =>
      switch (profile.cameraPresetKey) {
        'low' => ResolutionPreset.low,
        'high' => ResolutionPreset.high,
        _ => ResolutionPreset.medium,
      };

  bool _isAuthorized(HttpRequest request) {
    return _authGuard.trusted(request) != null;
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

  Future<bool> _requireAuth(HttpRequest request) async {
    if (_isAuthorized(request)) return true;
    request.response.statusCode = HttpStatus.unauthorized;
    await request.response.close();
    return false;
  }

  Future<String?> _requireStreamAuth(HttpRequest request) async {
    final trusted = _authGuard.trusted(request);
    final clientId = trusted?.clientId ??
        _streamTokenClientId(request.uri.queryParameters['streamToken']);
    if (clientId == null) {
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

  AlertEvent _broadcastTestAlert(Map<Object?, Object?>? body) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final message = body?['message']?.toString().trim();
    final event = AlertEvent(
      id: 'test-$nowMs',
      type: AlertType.systemWarning,
      severity: AlertSeverity.info,
      message: message == null || message.isEmpty
          ? 'MimiCam test bildirimi'
          : message,
      score: 0,
      timestampMs: nowMs,
      metadata: const {
        'event': 'test_probe',
        'source': '/test/alert',
      },
    );
    _handleAlertEvent(event);
    return event;
  }

  Map<String, Object?> _testDiagnostics() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final videoMetrics = _mjpegBackpressure.aggregateMetrics();
    final audioMetrics = _audioBackpressure.aggregateMetrics();
    return {
      'ok': true,
      'timestampMs': nowMs,
      'runtime': {
        'httpListening': _httpServerListening,
        'pairingModeActive': _pairingModeActive,
        'mediaStarting': _mediaStart != null,
        'mediaActive': cameraController != null ||
            _audioSubscription != null ||
            _analysisCoordinator != null,
        'cameraInitialized': cameraController?.value.isInitialized ?? false,
        'microphoneActive': _audioSubscription != null,
        'wakelockEnabled': _wakelockEnabled,
      },
      'clients': {
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'videoClients': _mjpegClients.length,
        'audioClients': _audioClients.length,
        'webSocketClients': _webSockets.length,
      },
      'video': {
        'hasLatestJpeg': _latestJpeg != null,
        'lastCameraFrameAtMs': _lastCameraFrameAtMs,
        'lastCameraFrameAgeMs': _ageMs(nowMs, _lastCameraFrameAtMs),
        'lastFrameEncodedAtMs': _lastVideoFrameEncodedAtMs,
        'lastFrameEncodedAgeMs': _ageMs(nowMs, _lastVideoFrameEncodedAtMs),
        'lastClientWriteAtMs': _lastVideoClientWriteAtMs,
        'lastClientWriteAgeMs': _ageMs(nowMs, _lastVideoClientWriteAtMs),
        'framesEncoded': _videoFramesEncoded,
        'framesStreamed': _videoFramesStreamed,
        'lastJpegBytes': _lastJpegBytes,
        'probeEncodeActive': _isVideoProbeActive(nowMs),
        'backpressure': _backpressureJson(videoMetrics),
      },
      'audio': {
        'recorderCreated': _audioRecorder != null,
        'permissionGranted': _lastMicrophonePermissionGranted,
        'active': _audioSubscription != null,
        'lastChunkAtMs': _lastAudioChunkAtMs,
        'lastChunkAgeMs': _ageMs(nowMs, _lastAudioChunkAtMs),
        'lastClientWriteAtMs': _lastAudioClientWriteAtMs,
        'lastClientWriteAgeMs': _ageMs(nowMs, _lastAudioClientWriteAtMs),
        'chunksCaptured': _audioChunksCaptured,
        'chunksStreamed': _audioChunksStreamed,
        'lastChunkBytes': _lastAudioChunkBytes,
        'lastClientWriteBytes': _lastAudioClientWriteBytes,
        'lastStartError': _lastAudioStartError,
        'backpressure': _backpressureJson(audioMetrics),
      },
      'events': {
        'alertsBroadcast': _alertsBroadcast,
        'lastAlertAtMs': _lastAlertBroadcastAtMs,
        'lastAlertAgeMs': _ageMs(nowMs, _lastAlertBroadcastAtMs),
        'lastDeliveredWebSocketClients': _lastAlertDeliveredWebSocketClients,
        'totalWebSocketDeliveries': _alertWebSocketDeliveries,
      },
      'analysis': _analysisMetrics?.toJson(),
    };
  }

  _ProbeCounters _probeCounters() => _ProbeCounters(
        cameraFramesAtMs: _lastCameraFrameAtMs,
        videoFramesEncoded: _videoFramesEncoded,
        videoFramesStreamed: _videoFramesStreamed,
        audioChunksCaptured: _audioChunksCaptured,
        audioChunksStreamed: _audioChunksStreamed,
        alertsBroadcast: _alertsBroadcast,
        lastDeliveredWebSocketClients: _lastAlertDeliveredWebSocketClients,
        totalWebSocketDeliveries: _alertWebSocketDeliveries,
      );

  bool _probeReady(
    _ProbeCounters before, {
    required bool requireVideo,
    required bool requireAudio,
    required bool requireEvents,
    required bool requireEventDelivery,
  }) {
    final checks = _probeChecks(
      before,
      requireVideo: requireVideo,
      requireAudio: requireAudio,
      requireEvents: requireEvents,
      requireEventDelivery: requireEventDelivery,
    );
    return checks.values.every((value) => value);
  }

  Map<String, bool> _probeChecks(
    _ProbeCounters before, {
    required bool requireVideo,
    required bool requireAudio,
    required bool requireEvents,
    required bool requireEventDelivery,
  }) {
    final after = _probeCounters();
    return {
      'video': !requireVideo ||
          after.videoFramesEncoded > before.videoFramesEncoded ||
          _latestJpeg != null,
      'audio': !requireAudio ||
          after.audioChunksCaptured > before.audioChunksCaptured ||
          _lastAudioChunkAtMs != null,
      'events':
          !requireEvents || after.alertsBroadcast > before.alertsBroadcast,
      'eventDelivery': !requireEventDelivery ||
          after.totalWebSocketDeliveries > before.totalWebSocketDeliveries,
    };
  }

  bool _isVideoProbeActive(int nowMs) =>
      _videoProbeEncodeUntilMs != null && nowMs <= _videoProbeEncodeUntilMs!;

  Map<String, Object?> _backpressureJson(StreamBackpressureMetrics metrics) => {
        'skippedWrites': metrics.skippedWrites,
        'skippedVideoFrames': metrics.skippedVideoFrames,
        'skippedAudioChunks': metrics.skippedAudioChunks,
        'consecutiveWriteFailures': metrics.consecutiveWriteFailures,
        'lastSuccessfulVideoWriteAtMs': metrics.lastSuccessfulVideoWriteAtMs,
        'lastSuccessfulAudioWriteAtMs': metrics.lastSuccessfulAudioWriteAtMs,
        'lastWriteDurationMs': metrics.lastWriteDurationMs,
        'averageWriteDurationMs': metrics.averageWriteDurationMs,
      };

  int? _ageMs(int nowMs, int? eventAtMs) =>
      eventAtMs == null ? null : max(0, nowMs - eventAtMs);

  int _intFrom(Object? value, {required int defaultValue}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? defaultValue;
  }

  bool _boolFrom(Object? value, {required bool defaultValue}) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return defaultValue;
  }

  Future<void> stopMediaRuntime() async {
    await ForegroundServiceController.stopServer();
    if (_wakelockEnabled) {
      await WakelockPlus.disable();
      _wakelockEnabled = false;
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    await cameraController?.dispose();
    cameraController = null;
    _latestJpeg = null;
    _videoProbeEncodeUntilMs = null;
    _lastMotionSample = null;
    _lastMotionEnergy = 0;
    _cryActive = false;
    _lastCryActiveAtMs = null;
    _frameBudget.reset();
    _mjpegBackpressure.clear();
    _audioBackpressure.clear();
    _mjpegClientIds.clear();
    _audioClientIds.clear();
    _audioBusyClientIds.clear();
    _jpegByteBudgetController.reset();
    _mediaQualitySelector.reset();
  }

  Future<void> _handleMjpeg(HttpResponse response, String clientId) async {
    response.headers.set(HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame');
    _mjpegClients.add(response);
    _mjpegClientIds[response] = clientId;
    response.done.catchError((Object _) {}).whenComplete(() {
      _removeMjpegClient(response);
    });
    final firstFrame = _latestJpeg;
    if (firstFrame != null) {
      final startedAt = DateTime.now();
      await _writeMjpegFrame(response, firstFrame);
      _recordVideoClientWrite(
        response,
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  Future<void> _handleAudio(HttpResponse response, String clientId) async {
    response.headers
      ..contentType = ContentType('audio', 'wav')
      ..chunkedTransferEncoding = true
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set(HttpHeaders.acceptRangesHeader, 'none')
      ..set('X-Audio-Sample-Rate', '$_audioSampleRate')
      ..set('X-Audio-Channels', '$_audioChannels')
      ..set('X-Audio-Bits-Per-Sample', '$_audioBitsPerSample');
    response.add(_wavHeader(
        sampleRate: _audioSampleRate,
        channels: _audioChannels,
        bitsPerSample: _audioBitsPerSample));
    _audioClients.add(response);
    _audioClientIds[response] = clientId;
    response.done.catchError((Object _) {}).whenComplete(() {
      _removeAudioClient(response);
    });
    await response.flush();
  }

  void _removeMjpegClient(HttpResponse response) {
    final clientId = _mjpegClientIds.remove(response);
    _mjpegClients.remove(response);
    _mjpegBackpressure.remove(response);
    if (clientId != null) _activeClientRegistry.detachStream(clientId);
  }

  void _removeAudioClient(HttpResponse response) {
    final clientId = _audioClientIds.remove(response);
    _audioClients.remove(response);
    if (clientId != null) _audioBusyClientIds.remove(clientId);
    _audioBackpressure.remove(response);
    if (clientId != null) _activeClientRegistry.detachStream(clientId);
  }

  void _recordVideoClientWrite(
    HttpResponse response, {
    required Duration duration,
  }) {
    _videoFramesStreamed++;
    _lastVideoClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
    _mjpegBackpressure.recordSuccess(response, duration: duration);
  }

  Future<void> _writeMjpegFrame(HttpResponse response, Uint8List jpeg) async {
    response.add(utf8.encode(
        '--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n'));
    response.add(jpeg);
    response.add(utf8.encode('\r\n'));
    await response.flush();
  }

  Future<void> _writeJson(
      HttpResponse response, Map<String, Object?> body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeLandingPage(HttpResponse response) async {
    response.headers.contentType = ContentType.html;
    response.write('''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>MimiCam</title></head>
<body style="margin:0;background:#111;color:white;font-family:-apple-system,BlinkMacSystemFont,sans-serif">
  <main style="padding:16px"><h1>${strings.appTitle}</h1><img src="/video" style="width:100%;max-width:900px;border-radius:16px"><p>${strings.streamActiveHtml}</p><p><a style="color:#ff8ab3" href="/audio">${strings.audioOnlyHtml}</a></p></main>
</body></html>''');
    await response.close();
  }

  Uint8List _wavHeader(
      {required int sampleRate,
      required int channels,
      required int bitsPerSample}) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final data = ByteData(44);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    const dataSize = 0x7fffffff;
    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    return data.buffer.asUint8List();
  }

  int _broadcastBinary(List<int> data) {
    var delivered = 0;
    for (final socket in _webSockets.toList()) {
      try {
        socket.add(data);
        delivered++;
      } catch (_) {
        _webSockets.remove(socket);
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
        _webSockets.remove(socket);
      }
    }
    return delivered;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await ForegroundServiceController.stopServer();
    if (_wakelockEnabled) {
      await WakelockPlus.disable();
      _wakelockEnabled = false;
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    _frameBudget.reset();
    _activeClientRegistry.clear();
    _mjpegBackpressure.clear();
    _audioBackpressure.clear();
    _mjpegClientIds.clear();
    _audioClientIds.clear();
    _audioBusyClientIds.clear();
    _jpegByteBudgetController.reset();
    tokenService.revokeAll();
    await _audioRecorder?.dispose();
    _audioRecorder = null;
    await cameraController?.dispose();
    cameraController = null;
    _videoProbeEncodeUntilMs = null;
    await _httpServer?.close(force: true);
    for (final socket in _webSockets.toList()) {
      await socket.close();
    }
    _webSockets.clear();
    _mjpegClients.clear();
    _audioClients.clear();
    _lastMotionSample = null;
    _lastMotionEnergy = 0;
    _cryActive = false;
    _lastCryActiveAtMs = null;
  }
}

class _ProbeCounters {
  const _ProbeCounters({
    required this.cameraFramesAtMs,
    required this.videoFramesEncoded,
    required this.videoFramesStreamed,
    required this.audioChunksCaptured,
    required this.audioChunksStreamed,
    required this.alertsBroadcast,
    required this.lastDeliveredWebSocketClients,
    required this.totalWebSocketDeliveries,
  });

  final int? cameraFramesAtMs;
  final int videoFramesEncoded;
  final int videoFramesStreamed;
  final int audioChunksCaptured;
  final int audioChunksStreamed;
  final int alertsBroadcast;
  final int lastDeliveredWebSocketClients;
  final int totalWebSocketDeliveries;

  Map<String, Object?> toJson() => {
        'cameraFramesAtMs': cameraFramesAtMs,
        'videoFramesEncoded': videoFramesEncoded,
        'videoFramesStreamed': videoFramesStreamed,
        'audioChunksCaptured': audioChunksCaptured,
        'audioChunksStreamed': audioChunksStreamed,
        'alertsBroadcast': alertsBroadcast,
        'lastDeliveredWebSocketClients': lastDeliveredWebSocketClients,
        'totalWebSocketDeliveries': totalWebSocketDeliveries,
      };
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

enum _AuthMode { none, bearer, streamToken }

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
