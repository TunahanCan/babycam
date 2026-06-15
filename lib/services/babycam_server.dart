import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:record/record.dart';

import '../core/babycam_protocol.dart';
import 'audio_analyzer.dart';
import 'configuration_service.dart';
import 'discovery_service.dart';
import 'motion_analyzer.dart';
import 'network_address_provider.dart';
import 'telegram_service.dart';

class BabyCamServer {
  BabyCamServer({required this.config, required this.onLog, required this.onAlert})
      : _telegram = TelegramService(config, onLog: onLog);

  final ConfigurationService config;
  final void Function(String message) onLog;
  final void Function(String message) onAlert;
  final TelegramService _telegram;
  final _discovery = DiscoveryService();
  final _audioRecorder = AudioRecorder();
  final _audioAnalyzer = AudioAnalyzer();
  final _motionAnalyzer = MotionAnalyzer();
  final _webSockets = <WebSocket>{};
  final _mjpegClients = <HttpResponse>{};
  final _audioClients = <HttpResponse>{};

  CameraController? cameraController;
  HttpServer? _httpServer;
  StreamSubscription<Uint8List>? _audioSubscription;
  Uint8List? _latestJpeg;
  bool _encodingFrame = false;
  int _motionAboveThresholdSince = 0;
  int _cryAboveThresholdSince = 0;
  int _lastMotionTime = 0;
  int _lastCryTime = 0;
  int _lastNotifyTime = 0;
  int _lastAudioDebugLog = 0;
  static const _audioSampleRate = 16000;
  static const _audioChannels = 1;
  static const _audioBitsPerSample = 16;

  Future<String> start() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('Kamera bulunamadı.');

    cameraController = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    await cameraController!.initialize();
    await cameraController!.startImageStream(_handleCameraFrame);
    await _startAudioAnalysis();

    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, BabyCamProtocol.httpPort, shared: true);
    _httpServer!.listen(_handleRequest);

    final address = await NetworkAddressProvider.localHttpAddress() ?? '${InternetAddress.loopbackIPv4.address}:${BabyCamProtocol.httpPort}';
    await _discovery.advertise(address);
    onLog('Server başladı: http://$address/');
    await _telegram.sendMessage('👋 Merhaba! Baby monitor servisi başlatıldı. Yayın: http://$address/');
    return 'http://$address/';
  }

  Future<void> _startAudioAnalysis() async {
    if (!await _audioRecorder.hasPermission()) {
      onLog('Mikrofon izni yok; ses analizi devre dışı.');
      return;
    }
    final stream = await _audioRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _audioSampleRate,
      numChannels: _audioChannels,
    ));
    _audioSubscription = stream.listen((chunk) {
      final result = _audioAnalyzer.analyzePcm16(chunk);
      _broadcastBinary([BabyCamProtocol.packetAudioPcm16Le, ...chunk]);
      for (final client in _audioClients.toList()) {
        client.add(chunk);
        client.flush().catchError((Object _) {
          _audioClients.remove(client);
        });
      }
      _handleAudioResult(result);
    });
  }

  void _handleAudioResult(AudioAnalysisResult result) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAudioDebugLog > 5000) {
      _lastAudioDebugLog = now;
      onLog('Ses analizi: ${result.summary}');
    }

    final score = result.cryScore > result.moanScore ? result.cryScore : result.moanScore;
    if (score >= config.cryScoreThreshold) {
      _cryAboveThresholdSince = _cryAboveThresholdSince == 0 ? now : _cryAboveThresholdSince;
      _lastCryTime = now;
    } else if (now - _lastCryTime > config.cryWindowMs) {
      _cryAboveThresholdSince = 0;
    }

    if (_cryAboveThresholdSince != 0 && now - _cryAboveThresholdSince >= config.cryMinDurationMs) {
      _notifyOnce('🔊 ${result.reason}. Güven ${(score * 100).round()}%. ${result.summary}');
      _cryAboveThresholdSince = 0;
    }
  }

  void _handleCameraFrame(CameraImage frame) {
    if (_encodingFrame) return;
    _encodingFrame = true;
    final analysis = _motionAnalyzer.analyze(frame);
    _latestJpeg = analysis.jpeg;
    _broadcastBinary([BabyCamProtocol.packetVideoMjpeg, ...analysis.jpeg]);
    for (final client in _mjpegClients.toList()) {
      _writeMjpegFrame(client, analysis.jpeg).catchError((Object _) {
        _mjpegClients.remove(client);
      });
    }
    _handleMotionScore(analysis.score);
    Future<void>.delayed(const Duration(milliseconds: 100), () => _encodingFrame = false);
  }

  void _handleMotionScore(double score) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (score >= config.motionThreshold) {
      _motionAboveThresholdSince = _motionAboveThresholdSince == 0 ? now : _motionAboveThresholdSince;
      _lastMotionTime = now;
    } else if (now - _lastMotionTime > config.motionWindowMs) {
      _motionAboveThresholdSince = 0;
    }

    if (_motionAboveThresholdSince != 0 && now - _motionAboveThresholdSince >= config.motionMinDurationMs) {
      _notifyOnce('👶 Hareket algılandı. Skor: ${(score * 100).round()}%');
      _motionAboveThresholdSince = 0;
    }
  }

  void _notifyOnce(String message) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyTime < config.notifyCooldownMs) return;
    _lastNotifyTime = now;
    onLog(message);
    onAlert(message);
    _broadcastBinary(BabyCamProtocol.alertFrame(message));
    _telegram.sendMessage(message);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/ws/stream' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _webSockets.add(socket);
      socket.done.whenComplete(() => _webSockets.remove(socket));
      onLog('WebSocket client bağlandı: ${request.connectionInfo?.remoteAddress.address}');
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
  <main style="padding:16px"><h1>BabyCam Flutter</h1><img src="/video" style="width:100%;max-width:900px;border-radius:16px"><p>LAN MJPEG yayını aktif.</p><p><a style="color:#ff8ab3" href="/audio">Sadece WAV ses akışı</a></p></main>
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
