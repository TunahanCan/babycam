import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../analysis/alert/alert_config.dart';
import '../analysis/alert/alert_engine.dart';
import '../analysis/alert/alert_event.dart';
import '../analysis/audio/audio_analysis_config.dart';
import '../analysis/audio/audio_chunk.dart';
import '../analysis/audio/cry_audio_analyzer_v2.dart';
import '../analysis/video/luma_frame.dart';
import '../analysis/video/motion_analysis_config.dart';
import '../analysis/video/motion_analyzer_v2.dart';
import '../core/media/adaptive_media_profile.dart';
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
    DeviceCapabilityTier? deviceTier,
    PairingTokenService? tokenService,
    this.transportConfig = TransportConfig.local,
    this.localNetworkGuard = const LocalNetworkGuard(),
    this.maxActiveWatchClients = 5,
    this.startMediaOnSessionStart = true,
    this.httpPort = MimiCamProtocol.httpPort,
  })  : tokenService = tokenService ?? PairingTokenService(),
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
  final PairingTokenService tokenService;
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
  final _mjpegBackpressure = StreamBackpressureGate<HttpResponse>();
  final _audioBackpressure = StreamBackpressureGate<HttpResponse>();
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
  StreamSubscription<Uint8List>? _audioSubscription;
  Uint8List? _latestJpeg;
  int _lastAudioDebugLog = 0;
  final _frameBudget = MediaFrameBudget();
  final _encodingPolicy = const MediaEncodingPolicy();
  final _mediaQualitySelector = const MediaQualitySelector();
  final DeviceCapabilityTier _deviceTier;
  late MediaQualityProfile _activeMediaProfile;
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
    if (cameraController != null) return;
    final cameras = await availableCameras();
    if (_disposed) throw StateError('MimiCamServer is disposed.');
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    _initializeAnalysisPipeline();

    cameraController = CameraController(
      cameras.first,
      _resolutionPresetFor(_activeMediaProfile),
      enableAudio: false,
    );
    await cameraController!.initialize();
    if (_disposed) {
      await cameraController?.dispose();
      cameraController = null;
      throw StateError('MimiCamServer is disposed.');
    }
    await cameraController!.startImageStream(_handleCameraFrame);
    await _startAudioAnalysis();
    if (_disposed) {
      await stopMediaRuntime();
      throw StateError('MimiCamServer is disposed.');
    }
    await WakelockPlus.enable();
    _wakelockEnabled = true;
    await ForegroundServiceController.startServer();
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
      alertEngine: AlertEngine(config: alertConfig, strings: strings),
      metrics: metrics,
      onLog: onLog,
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
    if (!await audioRecorder.hasPermission()) {
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
        if (!_audioBackpressure.tryMarkBusy(client)) continue;
        try {
          client.add(chunk);
          client.flush().catchError((Object _) {
            _audioClients.remove(client);
            _audioBackpressure.remove(client);
          }).whenComplete(() => _audioBackpressure.markIdle(client));
        } catch (_) {
          _audioClients.remove(client);
          _audioBackpressure.remove(client);
        }
      }
      _logAudioDiagnostics();
    });
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
    _broadcastBinary(AlertProtocolAdapter.toLegacyAlertPacket(event));
  }

  void _handleCameraFrame(CameraImage frame) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_frameBudget.shouldProcess(nowMs)) return;

    try {
      final shouldEncodeJpeg = _encodingPolicy.shouldEncodeJpeg(
        hasMjpegClients: _mjpegClients.isNotEmpty,
        legacyWebSocketEnabled: enableLegacyWebSocketMediaPackets,
      );
      if (shouldEncodeJpeg) {
        final jpeg = CameraImageJpegEncoder.encode(
          frame,
          quality: _activeMediaProfile.jpegQuality,
        );
        _latestJpeg = jpeg;
        if (enableLegacyWebSocketMediaPackets) {
          _broadcastBinary([MimiCamProtocol.packetVideoMjpeg, ...jpeg]);
        }
        for (final client in _mjpegClients.toList()) {
          if (!_mjpegBackpressure.tryMarkBusy(client)) continue;
          _writeMjpegFrame(client, jpeg).catchError((Object _) {
            _mjpegClients.remove(client);
            _mjpegBackpressure.remove(client);
          }).whenComplete(() => _mjpegBackpressure.markIdle(client));
        }
      }
      _analysisCoordinator?.onCameraFrame(_toLumaFrame(frame, nowMs));
    } catch (error) {
      onLog('Frame işlenemedi: $error');
    }
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

    switch (request.uri.path) {
      case protocol_v2.MimiCamProtocolV2.pairConfirm:
        await _handlePairConfirm(request);
        return;
      case protocol_v2.MimiCamProtocolV2.authRenew:
        await _handleAuthRenew(request);
        return;
      case protocol_v2.MimiCamProtocolV2.sessionStart:
        if (!await _requireAuth(request)) return;
        await _handleSessionStart(request);
        return;
      case protocol_v2.MimiCamProtocolV2.sessionStop:
        if (!await _requireAuth(request)) return;
        await _handleSessionStop(request);
        return;
      case protocol_v2.MimiCamProtocolV2.qualityReport:
        if (!await _requireAuth(request)) return;
        await _handleQualityReport(request);
        return;
      case protocol_v2.MimiCamProtocolV2.statusPublic:
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
        return;
      case '/video':
        final clientId = await _requireStreamAuth(request);
        if (clientId == null) return;
        try {
          await startMediaRuntime();
          await _handleMjpeg(request.response, clientId);
        } catch (_) {
          _activeClientRegistry.detachStream(clientId);
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
        return;
      case '/audio':
        final clientId = await _requireStreamAuth(request);
        if (clientId == null) return;
        try {
          await startMediaRuntime();
          await _handleAudio(request.response, clientId);
        } catch (_) {
          _activeClientRegistry.detachStream(clientId);
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
        return;
      case '/status':
        if (!await _requireAuth(request)) return;
        await _writeJson(request.response, {
          'videoClients': _mjpegClients.length,
          'audioClients': _audioClients.length,
          'webSocketClients': _webSockets.length,
          'activeStreamClients': _activeClientRegistry.activeClientCount,
          'qualityReportClients': _activeClientRegistry.qualityReportCount,
          'hasFrame': _latestJpeg != null,
          'deviceTier': _deviceTier.name,
          'mediaProfile': _activeMediaProfile.toJson(),
          if (_analysisCoordinator != null)
            ..._analysisCoordinator!.diagnostics(),
        });
        return;
      default:
        await _writeLandingPage(request.response);
        return;
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
      json = await _readJsonBody(request);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final clientId = _clientIdForRequest(request, json);
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
        'mediaProfile': _activeMediaProfile.toJson(),
        'streamToken': startResult.streamToken.token,
        'streamTokenExpiresAtMs': startResult.streamToken.expiresAtMs,
      });
    } catch (_) {
      if (startResult.createdActiveSlot) {
        _activeClientRegistry.stopSession(startResult.clientId);
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleSessionStop(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonBody(request);
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
        'mediaProfile': _activeMediaProfile.toJson(),
      });
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
      final tier = NetworkQualityTier.fromName(json['tier']?.toString());
      _activeClientRegistry.updateQuality(
        clientId: _clientIdForRequest(request, json),
        tier: tier,
        rttMs: _intValue(json['rttMs']),
      );
      await _applyMediaProfileForCurrentDemand();
      await _writeJson(request.response, {
        'ok': true,
        'deviceTier': _deviceTier.name,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'effectiveNetworkTier': _activeClientRegistry.effectiveTier().name,
        'mediaProfile': _activeMediaProfile.toJson(),
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
    );
    await _setActiveMediaProfile(nextProfile);
  }

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

  Map<String, Object?> _mediaCapabilities() => {
        'video': _activeMediaProfile.videoCodec,
        'videoPreferred': _activeMediaProfile.preferredVideoCodec,
        'audio': _activeMediaProfile.audioCodec,
        'audioPreferred': _activeMediaProfile.preferredAudioCodec,
        'events': 'json',
        'maxClients': maxActiveWatchClients,
        'transportPreferred': 'webrtc',
        'deviceTier': _deviceTier.name,
        'mediaProfile': _activeMediaProfile.toJson(),
      };

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

  Future<Object?> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
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
    _frameBudget.reset();
    _mjpegBackpressure.clear();
    _audioBackpressure.clear();
  }

  Future<void> _handleMjpeg(HttpResponse response, String clientId) async {
    response.headers.set(HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame');
    _mjpegClients.add(response);
    response.done.catchError((Object _) {}).whenComplete(() {
      _mjpegClients.remove(response);
      _mjpegBackpressure.remove(response);
      _activeClientRegistry.detachStream(clientId);
    });
    final firstFrame = _latestJpeg;
    if (firstFrame != null) await _writeMjpegFrame(response, firstFrame);
  }

  Future<void> _handleAudio(HttpResponse response, String clientId) async {
    response.headers.contentType = ContentType('audio', 'wav');
    response.add(_wavHeader(
        sampleRate: _audioSampleRate,
        channels: _audioChannels,
        bitsPerSample: _audioBitsPerSample));
    _audioClients.add(response);
    response.done.catchError((Object _) {}).whenComplete(() {
      _audioClients.remove(response);
      _audioBackpressure.remove(response);
      _activeClientRegistry.detachStream(clientId);
    });
    await response.flush();
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

    writeAscii(0, 'RIFF');
    data.setUint32(4, 0x7fffffff, Endian.little);
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
    data.setUint32(40, 0x7fffffff, Endian.little);
    return data.buffer.asUint8List();
  }

  void _broadcastBinary(List<int> data) {
    for (final socket in _webSockets.toList()) {
      socket.add(data);
    }
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
    tokenService.revokeAll();
    await _audioRecorder?.dispose();
    _audioRecorder = null;
    await cameraController?.dispose();
    cameraController = null;
    await _httpServer?.close(force: true);
    for (final socket in _webSockets.toList()) {
      await socket.close();
    }
    _webSockets.clear();
    _mjpegClients.clear();
    _audioClients.clear();
  }
}
