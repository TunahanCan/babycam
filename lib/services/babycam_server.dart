import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:record/record.dart';

import '../analysis/alert/alert_config.dart';
import '../analysis/alert/alert_engine.dart';
import '../analysis/alert/alert_event.dart';
import '../analysis/audio/audio_analysis_config.dart';
import '../analysis/audio/audio_chunk.dart';
import '../analysis/audio/cry_audio_analyzer_v2.dart';
import '../analysis/video/luma_frame.dart';
import '../analysis/video/motion_analysis_config.dart';
import '../analysis/video/motion_analyzer_v2.dart';
import '../core/babycam_protocol.dart';
import '../l10n/app_strings.dart';
import 'configuration_service.dart';
import 'discovery_service.dart';
import 'motion_analyzer.dart' show CameraImageJpegEncoder;
import 'server/alert_protocol_adapter.dart';
import 'server/media_analysis_coordinator.dart';
import 'server/media_analysis_metrics.dart';
import 'network_address_provider.dart';
import 'telegram_service.dart';

class BabyCamServer {
  BabyCamServer({
    required this.config,
    required this.strings,
    required this.onLog,
    required this.onAlert,
    this.enableLegacyWebSocketMediaPackets = false,
    this.enableAudioAutoCalibration = true,
  }) : _telegram = TelegramService(config, strings: strings, onLog: onLog);

  final bool enableLegacyWebSocketMediaPackets;
  final bool enableAudioAutoCalibration;

  final ConfigurationService config;
  final AppStrings strings;
  final void Function(String message) onLog;
  final void Function(String message) onAlert;
  final TelegramService _telegram;
  final _discovery = DiscoveryService();
  final _audioRecorder = AudioRecorder();
  MediaAnalysisCoordinator? _analysisCoordinator;
  MediaAnalysisMetrics? _analysisMetrics;
  StreamSubscription<AlertEvent>? _alertSubscription;
  final _webSockets = <WebSocket>{};
  final _mjpegClients = <HttpResponse>{};
  final _audioClients = <HttpResponse>{};

  CameraController? cameraController;
  HttpServer? _httpServer;
  StreamSubscription<Uint8List>? _audioSubscription;
  Uint8List? _latestJpeg;
  bool _encodingFrame = false;
  int _lastAudioDebugLog = 0;
  static const _audioSampleRate = 16000;
  static const _audioChannels = 1;
  static const _audioBitsPerSample = 16;

  Future<String> start() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    _initializeAnalysisPipeline();

    cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    await cameraController!.initialize();
    await cameraController!.startImageStream(_handleCameraFrame);
    await _startAudioAnalysis();

    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, BabyCamProtocol.httpPort, shared: true);
    _httpServer!.listen(_handleRequest);

    final address = await NetworkAddressProvider.localHttpAddress() ?? '${InternetAddress.loopbackIPv4.address}:${BabyCamProtocol.httpPort}';
    await _discovery.advertise(address);
    onLog(strings.serverStartedLog('http://$address/'));
    await _telegram.sendMessage(strings.telegramServerStarted('http://$address/'));
    return 'http://$address/';
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
      audioAnalyzer.startCalibration(timestampMs: DateTime.now().millisecondsSinceEpoch);
    }
    final metrics = MediaAnalysisMetrics(motionTargetFps: motionConfig.analysisFps);
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(config: motionConfig),
      audioAnalyzer: audioAnalyzer,
      alertEngine: AlertEngine(config: alertConfig),
      metrics: metrics,
      onLog: onLog,
    );
    _analysisMetrics = metrics;
    _analysisCoordinator = coordinator;
    _alertSubscription = coordinator.alerts.listen(_handleAlertEvent);
  }

  Future<void> _startAudioAnalysis() async {
    if (!await _audioRecorder.hasPermission()) {
      onLog(strings.microphonePermissionMissing);
      return;
    }
    final stream = await _audioRecorder.startStream(const RecordConfig(
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
        _broadcastBinary([BabyCamProtocol.packetAudioPcm16Le, ...chunk]);
      }
      for (final client in _audioClients.toList()) {
        client.add(chunk);
        client.flush().catchError((Object _) {
          _audioClients.remove(client);
        });
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
    _telegram.sendMessage(message);
  }

  void _handleCameraFrame(CameraImage frame) {
    if (_encodingFrame) return;
    _encodingFrame = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final jpeg = CameraImageJpegEncoder.encode(frame);
      _latestJpeg = jpeg;
      if (enableLegacyWebSocketMediaPackets) {
        _broadcastBinary([BabyCamProtocol.packetVideoMjpeg, ...jpeg]);
      }
      for (final client in _mjpegClients.toList()) {
        _writeMjpegFrame(client, jpeg).catchError((Object _) {
          _mjpegClients.remove(client);
        });
      }
      _analysisCoordinator?.onCameraFrame(_toLumaFrame(frame, nowMs));
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        _encodingFrame = false;
      });
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
    if (request.uri.path == '/ws/stream' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _webSockets.add(socket);
      socket.done.whenComplete(() => _webSockets.remove(socket));
      onLog(strings.webSocketClientConnected(request.connectionInfo?.remoteAddress.address ?? 'unknown'));
      return;
    }

    switch (request.uri.path) {
      case '/video':
        await _handleMjpeg(request.response);
        return;
      case '/audio':
        await _handleAudio(request.response);
        return;
      case '/status':
        await _writeJson(request.response, {
          'videoClients': _mjpegClients.length,
          'audioClients': _audioClients.length,
          'webSocketClients': _webSockets.length,
          'hasFrame': _latestJpeg != null,
          if (_analysisCoordinator != null) ..._analysisCoordinator!.diagnostics(),
        });
        return;
      default:
        await _writeLandingPage(request.response);
        return;
    }
  }

  Future<void> _handleMjpeg(HttpResponse response) async {
    response.headers.set(HttpHeaders.contentTypeHeader, 'multipart/x-mixed-replace; boundary=frame');
    _mjpegClients.add(response);
    final firstFrame = _latestJpeg;
    if (firstFrame != null) await _writeMjpegFrame(response, firstFrame);
  }

  Future<void> _handleAudio(HttpResponse response) async {
    response.headers.contentType = ContentType('audio', 'wav');
    response.add(_wavHeader(sampleRate: _audioSampleRate, channels: _audioChannels, bitsPerSample: _audioBitsPerSample));
    _audioClients.add(response);
    await response.flush();
  }

  Future<void> _writeMjpegFrame(HttpResponse response, Uint8List jpeg) async {
    response.add(utf8.encode('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpeg.length}\r\n\r\n'));
    response.add(jpeg);
    response.add(utf8.encode('\r\n'));
    await response.flush();
  }

  Future<void> _writeJson(HttpResponse response, Map<String, Object?> body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeLandingPage(HttpResponse response) async {
    response.headers.contentType = ContentType.html;
    response.write('''<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>BabyCam</title></head>
<body style="margin:0;background:#111;color:white;font-family:-apple-system,BlinkMacSystemFont,sans-serif">
  <main style="padding:16px"><h1>${strings.appTitle}</h1><img src="/video" style="width:100%;max-width:900px;border-radius:16px"><p>${strings.streamActiveHtml}</p><p><a style="color:#ff8ab3" href="/audio">${strings.audioOnlyHtml}</a></p></main>
</body></html>''');
    await response.close();
  }

  Uint8List _wavHeader({required int sampleRate, required int channels, required int bitsPerSample}) {
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
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    await _audioRecorder.dispose();
    await cameraController?.dispose();
    cameraController = null;
    await _httpServer?.close(force: true);
    for (final socket in _webSockets.toList()) {
      await socket.close();
    }
    _webSockets.clear();
    _mjpegClients.clear();
    _audioClients.clear();
    _discovery.dispose();
  }
}
