part of '../mimicam_server.dart';

final _mjpegHeaderEnd = Uint8List.fromList([13, 10, 13, 10]);
final _contentLengthPattern = RegExp(
  r'content-length:\s*(\d+)',
  caseSensitive: false,
);

extension MimiCamServerTestEndpoints on MimiCamServer {
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

  Future<void> _handleTestReset(HttpRequest request) async {
    await _closeStreamingClients();
    await stopMediaRuntime();
    _activeClientRegistry.clear();
    _resetTestDiagnostics();
    await _writeJson(request.response, {
      'ok': true,
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
    final loopbackMedia = _boolFrom(body?['loopbackMedia'], defaultValue: true);

    final before = _probeCounters();
    final authClientId = _authGuard.trusted(request)?.clientId;
    final wasActiveBefore = authClientId != null &&
        _activeClientRegistry.activeClientIds.contains(authClientId);
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
    Map<String, Object?>? loopback;
    if (loopbackMedia &&
        startError == null &&
        (requireVideo || requireAudio) &&
        authClientId != null) {
      loopback = await _runLoopbackMediaProbe(
        request,
        clientId: authClientId,
        stopAfterProbe: !wasActiveBefore,
        requireVideo: requireVideo,
        requireAudio: requireAudio,
        timeout: Duration(milliseconds: max(500, waitMs + 1500)),
      );
      checks.addAll({
        if (requireVideo) 'videoClient': loopback['videoOk'] == true,
        if (requireAudio) 'audioClient': loopback['audioOk'] == true,
      });
    }
    final ok = startError == null && checks.values.every((value) => value);
    if (!ok) request.response.statusCode = HttpStatus.serviceUnavailable;
    await _writeJson(request.response, {
      'ok': ok,
      'waitMs': waitMs,
      if (startError != null) 'startError': startError.toString(),
      'checks': checks,
      if (loopback != null) 'loopback': loopback,
      'before': before.toJson(),
      'after': _probeCounters().toJson(),
      'diagnostics': _testDiagnostics(),
    });
  }

  Future<Map<String, Object?>> _runLoopbackMediaProbe(
    HttpRequest sourceRequest, {
    required String clientId,
    required bool stopAfterProbe,
    required bool requireVideo,
    required bool requireAudio,
    required Duration timeout,
  }) async {
    final server = _httpServer;
    final bearer = sourceRequest.headers.value(HttpHeaders.authorizationHeader);
    if (server == null || bearer == null || !bearer.startsWith('Bearer ')) {
      return {
        'ok': false,
        'videoOk': !requireVideo,
        'audioOk': !requireAudio,
        'error': 'loopback probe is not authorized',
      };
    }
    final client = HttpClient()..connectionTimeout = timeout;
    String? streamToken;
    Object? error;
    var videoOk = !requireVideo;
    var audioOk = !requireAudio;
    var videoBytes = 0;
    var audioBytes = 0;
    try {
      final started = await _loopbackSessionStart(
        client,
        server.port,
        bearer,
        clientId,
        requireAudio: requireAudio,
        timeout: timeout,
      );
      streamToken = started['streamToken']?.toString();
      if (streamToken == null || streamToken.isEmpty) {
        throw StateError('loopback session did not return streamToken');
      }
      if (requireVideo) {
        videoBytes = await _readLoopbackMjpegFrame(
          server.port,
          streamToken,
          timeout,
        );
        videoOk = videoBytes > 0;
      }
      if (requireAudio) {
        audioBytes = await _readLoopbackAudioPayload(
          server.port,
          streamToken,
          timeout,
        );
        audioOk = audioBytes > 0;
      }
    } catch (caught) {
      error = caught;
    } finally {
      if (stopAfterProbe) {
        try {
          await _loopbackSessionStop(
            client,
            server.port,
            bearer,
            clientId,
            timeout,
          );
        } catch (_) {}
      }
      client.close(force: true);
    }
    return {
      'ok': error == null && videoOk && audioOk,
      'videoOk': videoOk,
      'audioOk': audioOk,
      'videoBytes': videoBytes,
      'audioBytes': audioBytes,
      if (streamToken != null) 'streamTokenReceived': true,
      if (error != null) 'error': error.toString(),
    };
  }

  Future<Map<String, Object?>> _loopbackSessionStart(
    HttpClient client,
    int port,
    String bearer,
    String clientId, {
    required bool requireAudio,
    required Duration timeout,
  }) async {
    final request = await client
        .postUrl(_loopbackUri(port, protocol_v2.MimiCamProtocolV2.sessionStart))
        .timeout(timeout);
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, bearer);
    request.write(jsonEncode({
      'clientId': clientId,
      'video': true,
      'audio': requireAudio,
    }));
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('loopback session/start failed: ${response.statusCode}');
    }
    final json = jsonDecode(body);
    if (json is! Map) throw StateError('loopback session/start invalid JSON');
    return Map<String, Object?>.from(json);
  }

  Future<void> _loopbackSessionStop(
    HttpClient client,
    int port,
    String bearer,
    String clientId,
    Duration timeout,
  ) async {
    final request = await client
        .postUrl(_loopbackUri(port, protocol_v2.MimiCamProtocolV2.sessionStop))
        .timeout(timeout);
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, bearer);
    request.write(jsonEncode({'clientId': clientId}));
    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
  }

  Future<int> _readLoopbackMjpegFrame(
    int port,
    String streamToken,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(_loopbackUri(
            port,
            protocol_v2.MimiCamProtocolV2.video,
            query: {'streamToken': streamToken},
          ))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw StateError('loopback video failed: ${response.statusCode}');
      }
      final buffer = BytesBuilder(copy: false);
      final completer = Completer<int>();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.timeout(timeout).listen(
        (chunk) {
          if (completer.isCompleted) return;
          buffer.add(chunk);
          final frameBytes = _firstMjpegPayloadBytes(buffer.toBytes());
          if (frameBytes <= 0) return;
          completer.complete(frameBytes);
          client.close(force: true);
          unawaited(subscription.cancel());
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(0);
        },
        cancelOnError: true,
      );
      return await completer.future.timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _readLoopbackAudioPayload(
    int port,
    String streamToken,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(_loopbackUri(
            port,
            protocol_v2.MimiCamProtocolV2.audio,
            query: {'streamToken': streamToken},
          ))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw StateError('loopback audio failed: ${response.statusCode}');
      }
      final buffer = BytesBuilder(copy: false);
      final completer = Completer<int>();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.timeout(timeout).listen(
        (chunk) {
          if (completer.isCompleted) return;
          buffer.add(chunk);
          final bytes = buffer.toBytes();
          if (bytes.length <= 44 ||
              String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
              String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
            return;
          }
          completer.complete(bytes.length - 44);
          client.close(force: true);
          unawaited(subscription.cancel());
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(0);
        },
        cancelOnError: true,
      );
      return await completer.future.timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Uri _loopbackUri(
    int port,
    String path, {
    Map<String, String>? query,
  }) =>
      Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        path: path,
        queryParameters: query,
      );

  int _firstMjpegPayloadBytes(Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      final headerEnd = _indexOfBytes(bytes, _mjpegHeaderEnd, start: offset);
      if (headerEnd < 0) return 0;
      final header = latin1.decode(
        Uint8List.sublistView(bytes, offset, headerEnd),
        allowInvalid: true,
      );
      final match = _contentLengthPattern.firstMatch(header);
      final length = int.tryParse(match?.group(1) ?? '') ?? 0;
      final payloadStart = headerEnd + _mjpegHeaderEnd.length;
      if (length <= 0) {
        offset = payloadStart;
        continue;
      }
      if (bytes.length >= payloadStart + length) return length;
      return 0;
    }
    return 0;
  }

  int _indexOfBytes(Uint8List bytes, Uint8List pattern, {required int start}) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;
    for (var i = start; i <= bytes.length - pattern.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
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

  Future<void> _handleTestAudioTone(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final durationMs =
        _intFrom(query['durationMs'], defaultValue: 1200).clamp(100, 5000);
    final frequencyHz =
        _intFrom(query['frequencyHz'], defaultValue: 440).clamp(80, 2000);
    final amplitude = (double.tryParse(query['amplitude'] ?? '') ?? .35)
        .clamp(.02, .80)
        .toDouble();
    final pcm = WavPcm16.sineTone(
      sampleRate: MimiCamServer._audioSampleRate,
      durationMs: durationMs.toInt(),
      frequencyHz: frequencyHz.toInt(),
      amplitude: amplitude,
    );

    request.response.headers
      ..contentType = ContentType('audio', 'wav')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Audio-Test-Tone', 'true')
      ..set('X-Audio-Sample-Rate', '${MimiCamServer._audioSampleRate}')
      ..set('X-Audio-Channels', '${MimiCamServer._audioChannels}')
      ..set(
        'X-Audio-Bits-Per-Sample',
        '${MimiCamServer._audioBitsPerSample}',
      );
    request.response
      ..add(WavPcm16.header(
        sampleRate: MimiCamServer._audioSampleRate,
        channels: MimiCamServer._audioChannels,
        bitsPerSample: MimiCamServer._audioBitsPerSample,
        dataSize: pcm.length,
      ))
      ..add(pcm);
    await request.response.close();
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
    final videoStream = _videoStreamService.snapshot;
    final videoMetrics = videoStream.backpressure;
    final microphone = _microphoneCapture.snapshot;
    final audioStream = _audioStreamService.snapshot;
    final audioMetrics = audioStream.backpressure;
    final injectedSource = mediaSource?.snapshot;
    return {
      'ok': true,
      'timestampMs': nowMs,
      'runtime': {
        'httpListening': _httpServerListening,
        'pairingModeActive': _pairingModeActive,
        'mediaStarting': _mediaStart != null,
        'mediaActive': cameraController != null ||
            microphone.active ||
            (injectedSource?.active ?? false) ||
            _analysisCoordinator != null,
        'cameraInitialized': cameraController?.value.isInitialized ?? false,
        'microphoneActive': microphone.active,
        'injectedMediaSourceActive': injectedSource?.active ?? false,
        'wakelockEnabled': _wakelockEnabled,
      },
      if (injectedSource != null) 'mediaSource': injectedSource.toJson(),
      'clients': {
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'videoClients': videoStream.clientCount,
        'audioClients': audioStream.clientCount,
        'webSocketClients': _webSockets.length,
      },
      'video': {
        'hasLatestJpeg': _latestJpeg != null,
        'lastCameraFrameAtMs': _lastCameraFrameAtMs,
        'lastCameraFrameAgeMs': _ageMs(nowMs, _lastCameraFrameAtMs),
        'lastFrameEncodedAtMs': _lastVideoFrameEncodedAtMs,
        'lastFrameEncodedAgeMs': _ageMs(nowMs, _lastVideoFrameEncodedAtMs),
        'lastClientWriteAtMs': videoStream.lastClientWriteAtMs,
        'lastClientWriteAgeMs': _ageMs(nowMs, videoStream.lastClientWriteAtMs),
        'framesEncoded': _videoFramesEncoded,
        'framesStreamed': videoStream.framesStreamed,
        'sourceFrames': injectedSource?.videoFrames ?? 0,
        'lastSourceFrameAtMs': injectedSource?.lastVideoFrameAtMs,
        'lastSourceFrameAgeMs':
            _ageMs(nowMs, injectedSource?.lastVideoFrameAtMs),
        'lastSourceFrameBytes': injectedSource?.lastVideoFrameBytes ?? 0,
        'lastJpegBytes': _lastJpegBytes,
        'probeEncodeActive': _isVideoProbeActive(nowMs),
        'backpressure': _backpressureJson(videoMetrics),
      },
      'audio': {
        'recorderCreated': microphone.recorderCreated,
        'permissionGranted': microphone.permissionGranted,
        'active': microphone.active,
        'lastChunkAtMs': microphone.lastChunkAtMs,
        'lastChunkAgeMs': _ageMs(nowMs, microphone.lastChunkAtMs),
        'lastClientWriteAtMs': audioStream.lastClientWriteAtMs,
        'lastClientWriteAgeMs': _ageMs(nowMs, audioStream.lastClientWriteAtMs),
        'chunksCaptured': microphone.chunksCaptured,
        'chunksStreamed': audioStream.chunksStreamed,
        'sourceChunksCaptured': injectedSource?.audioChunks ?? 0,
        'lastSourceChunkAtMs': injectedSource?.lastAudioChunkAtMs,
        'lastSourceChunkAgeMs':
            _ageMs(nowMs, injectedSource?.lastAudioChunkAtMs),
        'lastSourceChunkBytes': injectedSource?.lastAudioChunkBytes ?? 0,
        'lastChunkBytes': microphone.lastChunkBytes,
        'lastClientWriteBytes': audioStream.lastClientWriteBytes,
        'lastStartError':
            microphone.lastStartError ?? injectedSource?.lastError,
        'leveler': microphone.leveler.toJson(),
        'clientIds': audioStream.clientIds,
        'busyClientIds': audioStream.busyClientIds,
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
        videoFramesStreamed: _videoStreamService.snapshot.framesStreamed,
        audioChunksCaptured: _microphoneCapture.snapshot.chunksCaptured +
            (mediaSource?.snapshot.audioChunks ?? 0),
        audioChunksStreamed: _audioStreamService.snapshot.chunksStreamed,
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
          _microphoneCapture.snapshot.lastChunkAtMs != null,
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

  Future<void> _closeStreamingClients() async {
    await _videoStreamService.closeAll();
    await _audioStreamService.closeAll();
    for (final socket in _webSockets.toList()) {
      try {
        await socket.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _webSockets.clear();
  }

  void _resetTestDiagnostics() {
    _latestJpeg = null;
    _lastCameraFrameAtMs = null;
    _lastVideoFrameEncodedAtMs = null;
    _lastAlertBroadcastAtMs = null;
    _videoProbeEncodeUntilMs = null;
    _videoFramesEncoded = 0;
    _alertsBroadcast = 0;
    _alertWebSocketDeliveries = 0;
    _lastJpegBytes = 0;
    _lastAlertDeliveredWebSocketClients = 0;
    _videoStreamService.resetDiagnostics();
    _microphoneCapture.resetDiagnostics();
    _audioStreamService.resetDiagnostics();
    mediaSource?.resetDiagnostics();
    _analysisMetrics?.reset();
  }

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
