part of '../mimicam_server.dart';

final _mjpegHeaderEnd = Uint8List.fromList([13, 10, 13, 10]);
final _contentLengthPattern = RegExp(
  r'content-length:\s*(\d+)',
  caseSensitive: false,
);
const _defaultAudioToneDurationMs = 1200;
const _defaultAudioToneFrequencyHz = 440;
const _defaultAudioToneAmplitude = .35;

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
    final useAudioTone =
        _boolFrom(body?['useAudioTone'], defaultValue: false) ||
            body?['audioMode']?.toString().trim().toLowerCase() == 'tone';

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
        useAudioTone: useAudioTone,
        timeout: Duration(milliseconds: max(500, waitMs + 1500)),
      );
      checks.addAll(_probeChecks(
        before,
        requireVideo: requireVideo,
        requireAudio: requireAudio,
        requireEvents: requireEvents,
        requireEventDelivery: requireEventDelivery,
      ));
      checks.addAll({
        if (requireVideo && loopback['videoOk'] == true) 'video': true,
        if (requireAudio && loopback['audioOk'] == true) 'audio': true,
        if (requireVideo) 'videoClient': loopback['videoOk'] == true,
        if (requireAudio) 'audioClient': loopback['audioOk'] == true,
      });
    }
    final ok = startError == null && checks.values.every((value) => value);
    if (!ok) request.response.statusCode = HttpStatus.serviceUnavailable;
    await _writeJson(request.response, {
      'ok': ok,
      'waitMs': waitMs,
      'audioMode': useAudioTone ? 'tone' : 'microphone',
      if (startError != null) 'startError': startError.toString(),
      'checks': checks,
      'video': _probeVideoResult(
        checks,
        loopback,
        requireVideo: requireVideo,
      ),
      'audio': _probeAudioResult(
        before,
        checks,
        loopback,
        requireAudio: requireAudio,
        useAudioTone: useAudioTone,
      ),
      'alerts': _probeAlertResult(
        checks,
        requireEvents: requireEvents,
        requireEventDelivery: requireEventDelivery,
      ),
      'profile': {
        'current': _activeMediaProfile.id,
        'reason': _activeClientRegistry.effectiveTier().name,
      },
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
    required bool useAudioTone,
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
    var audio = const _LoopbackAudioProbeResult(
      wavHeaderValid: false,
      pcmBytesReceived: 0,
      chunksReceived: 0,
      reason: 'notRequested',
    );
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
        audio = await _readLoopbackAudioPayload(
          server.port,
          streamToken,
          timeout,
          emitTone: useAudioTone ? _emitLoopbackAudioTone : null,
        );
        audioOk = audio.ok;
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
      'audioBytes': audio.pcmBytesReceived,
      'audioWavHeaderValid': audio.wavHeaderValid,
      'audioChunksReceived': audio.chunksReceived,
      if (audio.reason != null) 'audioReason': audio.reason,
      'audio': audio.toJson(),
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

  Future<_LoopbackAudioProbeResult> _readLoopbackAudioPayload(
    int port,
    String streamToken,
    Duration timeout, {
    FutureOr<void> Function()? emitTone,
  }) async {
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
      if (emitTone != null) unawaited(Future<void>.sync(emitTone));
      final buffer = BytesBuilder(copy: false);
      final completer = Completer<_LoopbackAudioProbeResult>();
      late final StreamSubscription<List<int>> subscription;
      var wavHeaderValid = false;
      var pcmBytesReceived = 0;
      var chunksReceived = 0;
      subscription = response.timeout(timeout).listen(
        (chunk) {
          if (completer.isCompleted) return;
          buffer.add(chunk);
          final bytes = buffer.toBytes();
          if (bytes.length >= 12 && !_hasWavSignature(bytes)) {
            completer.complete(const _LoopbackAudioProbeResult(
              wavHeaderValid: false,
              pcmBytesReceived: 0,
              chunksReceived: 0,
              reason: 'invalidWavHeader',
            ));
            client.close(force: true);
            unawaited(subscription.cancel());
            return;
          }
          if (bytes.length <= 44) {
            return;
          }
          wavHeaderValid = true;
          final nextPcmBytes = bytes.length - 44;
          if (nextPcmBytes > pcmBytesReceived) chunksReceived++;
          pcmBytesReceived = nextPcmBytes;
          completer.complete(_LoopbackAudioProbeResult(
            wavHeaderValid: wavHeaderValid,
            pcmBytesReceived: pcmBytesReceived,
            chunksReceived: chunksReceived,
          ));
          client.close(force: true);
          unawaited(subscription.cancel());
        },
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(_LoopbackAudioProbeResult(
              wavHeaderValid: wavHeaderValid,
              pcmBytesReceived: pcmBytesReceived,
              chunksReceived: chunksReceived,
              reason: wavHeaderValid
                  ? 'noPcmBytesAfterWavHeader'
                  : 'wavHeaderNotReceived',
            ));
          }
        },
        cancelOnError: true,
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () => _LoopbackAudioProbeResult(
          wavHeaderValid: wavHeaderValid,
          pcmBytesReceived: pcmBytesReceived,
          chunksReceived: chunksReceived,
          reason:
              wavHeaderValid ? 'noPcmBytesAfterWavHeader' : 'wavHeaderTimeout',
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  bool _hasWavSignature(Uint8List bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE';

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
    final pcm = _testTonePcm(
      durationMs: _intFrom(
        query['durationMs'],
        defaultValue: _defaultAudioToneDurationMs,
      ),
      frequencyHz: _intFrom(
        query['frequencyHz'],
        defaultValue: _defaultAudioToneFrequencyHz,
      ),
      amplitude: double.tryParse(query['amplitude'] ?? '') ??
          _defaultAudioToneAmplitude,
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

  Uint8List _testTonePcm({
    int durationMs = _defaultAudioToneDurationMs,
    int frequencyHz = _defaultAudioToneFrequencyHz,
    double amplitude = _defaultAudioToneAmplitude,
  }) =>
      WavPcm16.sineTone(
        sampleRate: MimiCamServer._audioSampleRate,
        durationMs: durationMs.clamp(100, 5000).toInt(),
        frequencyHz: frequencyHz.clamp(80, 2000).toInt(),
        amplitude: amplitude.clamp(.02, .80).toDouble(),
      );

  Future<void> _emitLoopbackAudioTone() async {
    final pcm = _testTonePcm(durationMs: 100);
    const frameBytes = MimiCamServer._audioSampleRate *
        MimiCamServer._audioChannels *
        (MimiCamServer._audioBitsPerSample ~/ 8) *
        20 ~/
        1000;
    for (var offset = 0; offset < pcm.length; offset += frameBytes) {
      final end = min(offset + frameBytes, pcm.length);
      _audioStreamService.broadcast(Uint8List.sublistView(pcm, offset, end));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
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
    final qualityReports = _activeClientRegistry.activeQualityReports();
    final audioFailureReason = _audioFailureReason(nowMs);
    return {
      'ok': true,
      'timestampMs': nowMs,
      'server': {
        'running': _httpServerListening,
        'mediaRuntimeStarted': cameraController != null ||
            microphone.active ||
            (injectedSource?.active ?? false) ||
            _analysisCoordinator != null,
        'currentProfile': _activeMediaProfile.id,
        'activeClients': _activeClientRegistry.activeClientCount,
      },
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
        'qualityReports':
            qualityReports.map((report) => report.toJson()).toList(),
        'audioPipelines': _clientAudioPipelineReports(qualityReports),
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
        'enabled': true,
        'recorderCreated': microphone.recorderCreated,
        'microphoneStarted': microphone.active,
        'permissionGranted': microphone.permissionGranted,
        'active': microphone.active,
        'lastStartAttemptAtMs': microphone.lastStartAttemptAtMs,
        'lastStartAttemptAgeMs': _ageMs(nowMs, microphone.lastStartAttemptAtMs),
        'lastChunkAtMs': microphone.lastChunkAtMs,
        'lastChunkAgeMs': _ageMs(nowMs, microphone.lastChunkAtMs),
        'lastClientWriteAtMs': audioStream.lastClientWriteAtMs,
        'lastClientWriteAgeMs': _ageMs(nowMs, audioStream.lastClientWriteAtMs),
        'chunksCaptured': microphone.chunksCaptured,
        'bytesCaptured': microphone.bytesCaptured,
        'chunksStreamed': audioStream.chunksStreamed,
        'chunksSent': audioStream.chunksStreamed,
        'bytesStreamed': audioStream.bytesStreamed,
        'bytesSent': audioStream.bytesStreamed,
        'sourceChunksAccepted': audioStream.sourceChunksAccepted,
        'sourceBytesAccepted': audioStream.sourceBytesAccepted,
        'sourceChunksCaptured': injectedSource?.audioChunks ?? 0,
        'lastSequence': audioStream.lastSequence,
        'lastSourceChunkAtMs': audioStream.lastSourceChunkAtMs ??
            injectedSource?.lastAudioChunkAtMs,
        'lastSourceChunkAgeMs': _ageMs(
          nowMs,
          audioStream.lastSourceChunkAtMs ?? injectedSource?.lastAudioChunkAtMs,
        ),
        'lastSourceChunkBytes': audioStream.lastSourceChunkBytes > 0
            ? audioStream.lastSourceChunkBytes
            : injectedSource?.lastAudioChunkBytes ?? 0,
        'lastChunkBytes': microphone.lastChunkBytes,
        'lastClientWriteBytes': audioStream.lastClientWriteBytes,
        'failureReason': audioFailureReason,
        'captureFailureReason': microphone.failureReason,
        'lastError': microphone.lastStartError ?? injectedSource?.lastError,
        'lastStartError':
            microphone.lastStartError ?? injectedSource?.lastError,
        'underruns': audioMetrics.skippedAudioChunks,
        'leveler': microphone.leveler.toJson(),
        'clientIds': audioStream.clientIds,
        'busyClientIds': audioStream.busyClientIds,
        'clientPipelines': _clientAudioPipelineReports(qualityReports),
        'backpressure': _backpressureJson(audioMetrics),
      },
      'events': {
        'alertsBroadcast': _alertsBroadcast,
        'lastAlertAtMs': _lastAlertBroadcastAtMs,
        'lastAlertAgeMs': _ageMs(nowMs, _lastAlertBroadcastAtMs),
        'lastDeliveredWebSocketClients': _lastAlertDeliveredWebSocketClients,
        'totalWebSocketDeliveries': _alertWebSocketDeliveries,
      },
      'battery': _serverBattery.toJson(),
      'transport': _transportStatus(),
      'streamHealth': _streamHealthStatus(nowMs),
      'comfort': _features.comfortAudio.state.toJson(),
      'nightLight': _features.nightLight.state.toJson(),
      'talk': _talkStatus(),
      'analysis': _analysisMetrics?.toJson(),
    };
  }

  _ProbeCounters _probeCounters() => _ProbeCounters(
        cameraFramesAtMs: _lastCameraFrameAtMs,
        videoFramesEncoded: _videoFramesEncoded,
        videoFramesStreamed: _videoStreamService.snapshot.framesStreamed,
        audioChunksCaptured: max(
          _microphoneCapture.snapshot.chunksCaptured +
              (mediaSource?.snapshot.audioChunks ?? 0),
          _audioStreamService.snapshot.sourceChunksAccepted,
        ),
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

  Map<String, Object?> _probeVideoResult(
    Map<String, bool> checks,
    Map<String, Object?>? loopback, {
    required bool requireVideo,
  }) {
    final loopbackOk = loopback?['videoOk'] != false;
    final ok = !requireVideo || (checks['video'] == true && loopbackOk);
    return {
      'ok': ok,
      'required': requireVideo,
      'framesReceived': loopback?['videoFrames'] ?? (loopbackOk ? 1 : 0),
      'firstFrameBytes': loopback?['videoBytes'] ?? 0,
      if (!ok) 'reason': loopback?['error'] ?? 'noVideoFrame',
    };
  }

  Map<String, Object?> _probeAudioResult(
    _ProbeCounters before,
    Map<String, bool> checks,
    Map<String, Object?>? loopback, {
    required bool requireAudio,
    required bool useAudioTone,
  }) {
    final microphone = _microphoneCapture.snapshot;
    final loopbackAudio = loopback?['audio'];
    final audioLoopback = loopbackAudio is Map
        ? Map<String, Object?>.from(loopbackAudio)
        : const <String, Object?>{};
    final loopbackOk = loopback?['audioOk'] != false;
    final ok = !requireAudio || (checks['audio'] == true && loopbackOk);
    final reason = ok
        ? null
        : audioLoopback['reason'] ??
            loopback?['audioReason'] ??
            _audioFailureReason(
              DateTime.now().millisecondsSinceEpoch,
              before: before,
              requirePcm: requireAudio && !useAudioTone,
            ) ??
            loopback?['error'] ??
            'audioProbeFailed';
    return {
      'ok': ok,
      'required': requireAudio,
      'mode': useAudioTone ? 'tone' : 'microphone',
      'wavHeaderValid': audioLoopback['wavHeaderValid'] ?? false,
      'pcmBytesReceived': audioLoopback['pcmBytesReceived'] ?? 0,
      'chunksReceived': audioLoopback['chunksReceived'] ?? 0,
      'microphoneStarted': microphone.active,
      'permissionGranted': microphone.permissionGranted,
      'chunksCaptured': microphone.chunksCaptured,
      'bytesCaptured': microphone.bytesCaptured,
      'chunksStreamed': _audioStreamService.snapshot.chunksStreamed,
      if (reason != null) 'reason': reason,
      if (microphone.lastStartError != null)
        'lastError': microphone.lastStartError,
    };
  }

  Map<String, Object?> _probeAlertResult(
    Map<String, bool> checks, {
    required bool requireEvents,
    required bool requireEventDelivery,
  }) {
    final ok = (!requireEvents || checks['events'] == true) &&
        (!requireEventDelivery || checks['eventDelivery'] == true);
    return {
      'ok': ok,
      'required': requireEvents || requireEventDelivery,
      'eventReceived': checks['events'] == true,
      'eventDelivery': checks['eventDelivery'] == true,
      'eventsSent': _alertsBroadcast,
      'deliveredWebSocketClients': _lastAlertDeliveredWebSocketClients,
      if (!ok) 'reason': 'eventNotDelivered',
    };
  }

  String? _audioFailureReason(
    int nowMs, {
    _ProbeCounters? before,
    bool requirePcm = false,
  }) {
    final microphone = _microphoneCapture.snapshot;
    final audioStream = _audioStreamService.snapshot;
    final injectedSource = mediaSource?.snapshot;
    final sourceChunks =
        audioStream.sourceChunksAccepted + (injectedSource?.audioChunks ?? 0);
    final beforeChunks = before?.audioChunksCaptured ?? 0;
    if (sourceChunks > 0 &&
        (!requirePcm ||
            _probeCounters().audioChunksCaptured > beforeChunks ||
            audioStream.sourceChunksAccepted > 0)) {
      return null;
    }
    if (microphone.permissionGranted == false) return 'permissionDenied';
    if (microphone.failureReason != null) return microphone.failureReason;
    if (microphone.lastStartError != null) return 'captureStartFailed';
    if (microphone.recorderCreated && !microphone.active) {
      return 'captureNotActive';
    }
    final startAgeMs = _ageMs(nowMs, microphone.lastStartAttemptAtMs);
    if (microphone.active &&
        microphone.chunksCaptured == 0 &&
        (startAgeMs ?? 0) >= 1000) {
      return 'noPcmCaptured';
    }
    if (requirePcm) return 'noPcmBytesAfterWavHeader';
    return null;
  }

  List<Map<String, Object?>> _clientAudioPipelineReports(
    Iterable<ClientQualityReport> reports,
  ) =>
      reports
          .where((report) => report.audioPipeline.isNotEmpty)
          .map((report) => {
                'clientId': report.clientId,
                ...report.audioPipeline,
              })
          .toList(growable: false);

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

class _LoopbackAudioProbeResult {
  const _LoopbackAudioProbeResult({
    required this.wavHeaderValid,
    required this.pcmBytesReceived,
    required this.chunksReceived,
    this.reason,
  });

  final bool wavHeaderValid;
  final int pcmBytesReceived;
  final int chunksReceived;
  final String? reason;

  bool get ok => wavHeaderValid && pcmBytesReceived > 0;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'wavHeaderValid': wavHeaderValid,
        'pcmBytesReceived': pcmBytesReceived,
        'chunksReceived': chunksReceived,
        if (reason != null) 'reason': reason,
      };
}
