part of '../miucam_server.dart';

/// Owns capture, analysis and frame fan-out concerns.
extension MiuCamServerMediaCaptureController on MiuCamServer {
  Future<void> _startVideoCaptureRuntime(
    int generation, {
    required int operationToken,
  }) async {
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    await _ensureCameraPermission();
    if (!_ownsVideoCaptureOperation(generation, operationToken)) {
      throw StateError('Video capture demand changed during permission.');
    }
    final cameras = await availableCameras();
    if (!_ownsVideoCaptureOperation(generation, operationToken)) {
      throw StateError('Video capture demand changed during discovery.');
    }
    if (cameras.isEmpty) throw StateError(strings.cameraNotFound);

    _initializeAnalysisPipeline();
    _analysisCoordinator?.markVideoDiscontinuity();

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
    if (!_ownsVideoCaptureOperation(generation, operationToken)) {
      await _disposeCameraControllerLease(controller);
      throw StateError('Video capture demand changed before initialization.');
    }
    _pendingCameraControllers[controller] = generation;
    try {
      await _awaitCameraControllerOperation(
        controller.initialize(),
        controller: controller,
        label: 'initialize camera',
      );
      if (!_ownsVideoCaptureOperation(generation, operationToken)) {
        throw StateError('Video capture demand changed during initialization.');
      }
      await _awaitCameraControllerOperation(
        controller.startImageStream(_handleCameraFrame),
        controller: controller,
        label: 'start camera stream',
      );
      if (!_ownsVideoCaptureOperation(generation, operationToken)) {
        throw StateError('Video capture demand changed while starting stream.');
      }
      cameraController = controller;
      await _updateMediaHostLifecycle().timeout(mediaLifecycleOperationTimeout);
      if (!_ownsVideoCaptureOperation(generation, operationToken) ||
          !identical(cameraController, controller)) {
        throw StateError('Video capture demand changed while publishing.');
      }
    } catch (_) {
      if (identical(cameraController, controller)) {
        cameraController = null;
      }
      await _disposeCameraControllerLease(controller);
      rethrow;
    }
  }

  Future<T> _awaitCameraControllerOperation<T>(
    Future<T> operation, {
    required CameraController controller,
    required String label,
  }) {
    var timedOut = false;
    operation.then<void>(
      (_) {
        if (timedOut) {
          unawaited(_disposeCameraControllerLease(controller));
        }
      },
      onError: (Object _, StackTrace __) {
        if (timedOut) {
          unawaited(_disposeCameraControllerLease(controller));
        }
      },
    );
    return operation.timeout(
      mediaLifecycleOperationTimeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException(
          '$label timed out.',
          mediaLifecycleOperationTimeout,
        );
      },
    );
  }

  bool _ownsVideoCaptureIntent(int generation) =>
      !_disposed &&
      _videoCaptureDesired &&
      _videoCaptureIntentGeneration == generation;

  bool _ownsVideoCaptureOperation(int generation, int operationToken) =>
      _ownsVideoCaptureIntent(generation) &&
      _cameraOperationToken == operationToken;

  Future<void> _disposeCameraControllersForGeneration(int generation) async {
    final controllers = _pendingCameraControllers.entries
        .where((entry) => entry.value == generation)
        .map((entry) => entry.key)
        .toList(growable: false);
    final activeController = cameraController;
    if (activeController != null &&
        _pendingCameraControllers[activeController] == generation) {
      cameraController = null;
    }
    await Future.wait<bool>(
      controllers.map(_disposeCameraControllerLease),
    );
  }

  Future<bool> _disposeCameraControllerLease(CameraController controller) {
    _cameraControllersPendingDisposal.add(controller);
    final existing = _cameraControllerDisposals[controller];
    if (existing != null) return existing;
    late final Future<bool> operation;
    operation = _tryDisposeCameraController(controller).whenComplete(() {
      if (identical(_cameraControllerDisposals[controller], operation)) {
        _cameraControllerDisposals.remove(controller);
      }
    });
    _cameraControllerDisposals[controller] = operation;
    return operation;
  }

  Future<bool> _tryDisposeCameraController(
    CameraController controller,
  ) async {
    final existing = _cameraControllerRawDisposals[controller];
    if (existing != null) {
      return _awaitCameraControllerDisposal(controller, existing);
    }

    late final Future<void> rawDisposal;
    try {
      if (_cameraControllerDisposeStarted.add(controller)) {
        rawDisposal = controller.dispose();
      } else {
        // CameraController marks itself disposed before awaiting the platform
        // teardown. Retrying controller.dispose() after a platform error would
        // therefore be a no-op; retry the exact native camera lease instead.
        rawDisposal = CameraPlatform.instance.dispose(controller.cameraId);
      }
    } catch (error) {
      onLog('Kamera controller kapatılamadı; yeniden denenecek: $error');
      _scheduleCameraControllerDisposalRetry(controller);
      return false;
    }
    _cameraControllerRawDisposals[controller] = rawDisposal;
    rawDisposal.then<void>(
      (_) {
        if (identical(
          _cameraControllerRawDisposals[controller],
          rawDisposal,
        )) {
          _confirmCameraControllerDisposal(controller);
        }
      },
      onError: (Object _, StackTrace __) {
        if (!identical(
          _cameraControllerRawDisposals[controller],
          rawDisposal,
        )) {
          return;
        }
        _cameraControllerRawDisposals.remove(controller);
        _scheduleCameraControllerDisposalRetry(controller);
      },
    );
    return _awaitCameraControllerDisposal(controller, rawDisposal);
  }

  Future<bool> _awaitCameraControllerDisposal(
    CameraController controller,
    Future<void> rawDisposal,
  ) async {
    try {
      await rawDisposal.timeout(mediaLifecycleOperationTimeout);
      _confirmCameraControllerDisposal(controller);
      return true;
    } catch (error) {
      onLog('Kamera controller kapatılamadı; yeniden denenecek: $error');
      _scheduleCameraControllerDisposalRetry(controller);
      return false;
    }
  }

  void _confirmCameraControllerDisposal(CameraController controller) {
    _cameraControllersPendingDisposal.remove(controller);
    _cameraControllerDisposals.remove(controller);
    _cameraControllerRawDisposals.remove(controller);
    _cameraControllerDisposeStarted.remove(controller);
    _pendingCameraControllers.remove(controller);
    if (identical(cameraController, controller)) cameraController = null;
  }

  void _scheduleCameraControllerDisposalRetry(CameraController controller) {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 250), () async {
      if (!_cameraControllersPendingDisposal.contains(controller)) return;
      await _disposeCameraControllerLease(controller);
    }));
  }

  Future<void> _reconcileInjectedMediaSource(
    ServerMediaSource source, {
    bool? video,
    bool? audio,
  }) {
    final videoDemandChanged = video != null && video != _injectedVideoDemand;
    final audioDemandChanged = audio != null && audio != _injectedAudioDemand;
    if (videoDemandChanged) {
      _analysisCoordinator?.markVideoDiscontinuity();
    }
    if (audioDemandChanged) {
      _analysisCoordinator?.markAudioDiscontinuity();
    }
    if (video != null) _injectedVideoDemand = video;
    if (audio != null) _injectedAudioDemand = audio;
    return _injectedMediaOperations.run(
      () => _applyInjectedMediaDemand(source).timeout(
        mediaLifecycleOperationTimeout,
        onTimeout: () => throw TimeoutException(
          'Injected media reconciliation timed out.',
          mediaLifecycleOperationTimeout,
        ),
      ),
    );
  }

  Future<void> _applyInjectedMediaDemand(ServerMediaSource source) async {
    if (_injectedVideoDemand || _injectedAudioDemand) {
      _initializeAnalysisPipeline();
    }
    final ServerAudioChunkMetadataSource? metadataSource =
        source is ServerAudioChunkMetadataSource
            ? source as ServerAudioChunkMetadataSource
            : null;
    await source.reconcile(
      video: _injectedVideoDemand,
      audio: _injectedAudioDemand,
      onVideoFrame: _handleInjectedVideoFrame,
      onAudioChunk: (pcm16le) => _handleInjectedAudioChunk(
        pcm16le,
        metadata: metadataSource?.currentAudioChunkMetadata,
      ),
      onError: (error, _) {
        // A native event-channel/capture error is a media boundary. Reset both
        // analyzers so a fast reconnect cannot join pre/post-failure evidence.
        _analysisCoordinator?.markAudioDiscontinuity();
        _analysisCoordinator?.markVideoDiscontinuity();
        _analysisMetrics?.recordAudioError();
        onLog('Medya kaynağı hata verdi: $error');
      },
    );
    await _updateMediaHostLifecycle();
    await _disposeAnalysisIfIdle();
  }

  void _initializeAnalysisPipeline({
    double? calibratedAmbientDbfs,
    Map<AlertType, int>? cooldownSnapshot,
  }) {
    if (_analysisCoordinator != null) return;
    final motionConfig = MotionAnalysisConfig(
      motionOnThreshold: config.motionThreshold,
      minMotionDurationMs: config.motionMinDurationMs,
    );
    final audioConfig = AudioAnalysisConfig(
      sampleRate: MiuCamServer._audioSampleRate,
      cryOnThreshold: config.cryScoreThreshold,
      cryOffThreshold: AudioAnalysisConfig.hysteresisOffThreshold(
        config.cryScoreThreshold,
      ),
      // EpisodeBasedNotificationAggregator is the single duration policy.
      // Keeping a second gate here would nearly double profile latency.
      minCryDurationMs: 0,
    );
    final alertConfig = AlertConfig(
      cryCooldownMs: config.notifyCooldownMs,
      motionCooldownMs: config.notifyCooldownMs,
      cryAlertThreshold: config.cryScoreThreshold,
      motionAlertThreshold: config.motionThreshold,
    );
    final audioAnalyzer = CryAudioAnalyzerV2(config: audioConfig);
    if (calibratedAmbientDbfs != null) {
      audioAnalyzer.restoreCalibratedAmbient(calibratedAmbientDbfs);
    } else if (enableAudioAutoCalibration) {
      // Anchor calibration to the first media timestamp. This keeps batched
      // PCM and delayed capture startup on the same monotonic signal timeline.
      audioAnalyzer.startCalibration();
    }
    final metrics =
        MediaAnalysisMetrics(motionTargetFps: motionConfig.analysisFps);
    final alertEngine = AlertEngine(
      config: alertConfig,
      strings: strings,
      episodeAggregator: EpisodeBasedNotificationAggregator(
        cryThreshold: config.cryScoreThreshold,
        suspectedCryMs: min(
          config.cryMinDurationMs,
          max(0, config.cryMinDurationMs ~/ 2),
        ),
        confirmedCryMs: config.cryMinDurationMs,
      ),
      networkTierProvider: _activeClientRegistry.effectiveTier,
    );
    if (cooldownSnapshot != null) {
      alertEngine.restoreCooldowns(cooldownSnapshot);
    }
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(config: motionConfig),
      audioAnalyzer: audioAnalyzer,
      alertEngine: alertEngine,
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
    final calibratedAmbientDbfs = _analysisCoordinator?.calibratedAmbientDbfs;
    final cooldownSnapshot = _analysisCoordinator?.cooldownSnapshot;
    await _alertSubscription?.cancel();
    _alertSubscription = null;
    await _analysisCoordinator?.dispose();
    _analysisCoordinator = null;
    _analysisMetrics?.reset();
    _initializeAnalysisPipeline(
      calibratedAmbientDbfs: calibratedAmbientDbfs,
      cooldownSnapshot: cooldownSnapshot,
    );
  }

  Future<bool> _startAudioAnalysis() async {
    _analysisCoordinator?.markAudioDiscontinuity();
    final started = await _microphoneCapture.start(
      onChunk: (chunk) {
        _handleCapturedAudioChunk(
          analysisPcm16le: chunk.rawPcm16le,
          streamPcm16le: chunk.streamPcm16le,
          sampleRate: chunk.sampleRate,
          channels: chunk.channels,
          timestampMs: chunk.timestampMs,
        );
      },
      onError: (error, _) {
        _analysisCoordinator?.markAudioDiscontinuity();
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
    _broadcastText(AlertProtocolAdapter.toJsonText(event));
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary(AlertProtocolAdapter.toLegacyAlertPacket(event));
    }
  }

  void _handleCameraFrame(CameraImage frame) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final capturedAtMonoUs = _mediaTelemetry.nowUs;
    _videoFramesCaptured++;
    _mediaTelemetry.increment(MediaMetricName.videoCapturedCount);
    _lastMotionEnergy = _estimateMotionEnergy(frame);
    _updateContentAwareFrameBudget(nowMs);
    if (!_frameBudget.shouldProcess(nowMs)) return;

    try {
      _analysisCoordinator?.onCameraFrame(
        _toLumaFrame(
          frame,
          nowMs,
          monotonicTimestampMs: capturedAtMonoUs ~/ 1000,
        ),
      );
      final shouldEncodeJpeg = _encodingPolicy.shouldEncodeJpeg(
        hasMjpegClients: _videoStreamService.hasClients,
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
        if (enableLegacyWebSocketMediaPackets) {
          _broadcastBinary([MiuCamProtocol.packetVideoMjpeg, ...jpeg]);
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
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary([MiuCamProtocol.packetVideoMjpeg, ...jpeg]);
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

  void _handleInjectedAudioChunk(
    Uint8List pcm16le, {
    ServerAudioChunkMetadata? metadata,
  }) {
    if (pcm16le.isEmpty) return;
    if (metadata?.discontinuityBefore == true) {
      _analysisCoordinator?.markAudioDiscontinuity();
    }
    final capturedAtMs = metadata?.capturedAtMs;
    _handleCapturedAudioChunk(
      analysisPcm16le: pcm16le,
      streamPcm16le: pcm16le,
      sampleRate: metadata?.sampleRate ?? MiuCamServer._audioSampleRate,
      channels: metadata?.channels ?? MiuCamServer._audioChannels,
      timestampMs: capturedAtMs != null && capturedAtMs > 0
          ? capturedAtMs
          : DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _handleCapturedAudioChunk({
    required Uint8List analysisPcm16le,
    required Uint8List streamPcm16le,
    required int sampleRate,
    required int channels,
    required int timestampMs,
  }) {
    _mediaTelemetry.increment(MediaMetricName.audioCapturedCount);
    if (_features.roomAudio.mode == RoomAudioMode.idle) {
      _analysisCoordinator?.onAudioChunk(AudioChunk(
        pcm16le: analysisPcm16le,
        sampleRate: sampleRate,
        channels: channels,
        timestampMs: timestampMs,
      ));
    } else {
      // Both Android's service source and iOS/Dart capture can hear local room
      // output. Suppress analysis but keep the parent audio stream continuous.
      _selfAudioSuppressedChunks++;
    }
    if (enableLegacyWebSocketMediaPackets) {
      _broadcastBinary([MiuCamProtocol.packetAudioPcm16Le, ...streamPcm16le]);
    }
    _audioStreamService.broadcast(streamPcm16le);
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
    _lastMotionEnergy = result.normalizedMotionEnergy;
  }

  LumaFrame _toLumaFrame(
    CameraImage frame,
    int timestampMs, {
    int? monotonicTimestampMs,
  }) {
    final yPlane = frame.planes.first;
    final isBgra = frame.format.group == ImageFormatGroup.bgra8888 ||
        (frame.planes.length == 1 && (yPlane.bytesPerPixel ?? 1) >= 4);
    return LumaFrame(
      yPlane: yPlane.bytes,
      width: frame.width,
      height: frame.height,
      rowStride: yPlane.bytesPerRow,
      pixelStride: yPlane.bytesPerPixel ?? (isBgra ? 4 : 1),
      pixelFormat: isBgra ? LumaPixelFormat.bgra8888 : LumaPixelFormat.luma8,
      timestampMs: timestampMs,
      monotonicTimestampMs: monotonicTimestampMs,
    );
  }
}

/// Owns adaptive media policy, profile application and status projection.
extension _MiuCamServerMediaPolicyController on MiuCamServer {
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
            _sessions.requestedDemands.any((value) => value.audio) ||
            _sessions.standaloneDemands.any((value) => value.audio),
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
    final captureGeneration = _videoCaptureIntentGeneration;
    if (!_ownsVideoCaptureIntent(captureGeneration)) return false;
    final operationToken = ++_cameraOperationToken;
    _analysisCoordinator?.markVideoDiscontinuity();
    _cameraEncodeGeneration++;
    _pendingCameraEncode = null;
    final previousController = cameraController;
    if (previousController == null) return true;
    if (!identical(cameraController, previousController)) return false;
    cameraController = null;
    _latestJpeg = null;
    _frameBudget.reset();
    _resourcePolicyCoordinator.resetDecision();
    CameraController? nextController;
    var installed = false;
    try {
      _pendingCameraControllers.putIfAbsent(
        previousController,
        () => captureGeneration,
      );
      final previousDisposed =
          await _disposeCameraControllerLease(previousController);
      if (!previousDisposed) {
        throw TimeoutException(
          'Previous camera profile disposal timed out.',
          mediaLifecycleOperationTimeout,
        );
      }
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !_ownsVideoCaptureOperation(captureGeneration, operationToken)) {
        return false;
      }
      await _ensureCameraPermission();
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !_ownsVideoCaptureOperation(captureGeneration, operationToken)) {
        return false;
      }
      final cameras = await availableCameras();
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !_ownsVideoCaptureOperation(captureGeneration, operationToken)) {
        return false;
      }
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
      _pendingCameraControllers[nextController] = captureGeneration;
      await _awaitCameraControllerOperation(
        nextController.initialize(),
        controller: nextController,
        label: 'initialize camera profile',
      );
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !_ownsVideoCaptureOperation(captureGeneration, operationToken) ||
          cameraController != null) {
        await _disposeCameraControllerLease(nextController);
        return false;
      }
      await _awaitCameraControllerOperation(
        nextController.startImageStream(_handleCameraFrame),
        controller: nextController,
        label: 'start camera profile stream',
      );
      if (!_isCurrentMediaProfileApply(applyGeneration) ||
          !_ownsVideoCaptureOperation(captureGeneration, operationToken) ||
          cameraController != null) {
        await _disposeCameraControllerLease(nextController);
        return false;
      }
      cameraController = nextController;
      installed = true;
      return true;
    } catch (error, stackTrace) {
      if (nextController != null &&
          identical(cameraController, nextController)) {
        cameraController = null;
      }
      if (nextController != null) {
        await _disposeCameraControllerLease(nextController);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!installed &&
          _videoCaptureDesired &&
          !_disposed &&
          _ownsVideoCaptureOperation(captureGeneration, operationToken) &&
          cameraController == null) {
        try {
          await startVideoRuntime();
          onLog('Camera profile restart rolled back to the previous profile.');
        } catch (recoveryError) {
          onLog('Camera profile rollback failed: $recoveryError');
        }
      }
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
        'connectionLimits': {
          'mediaPerClient': maxMediaConnectionsPerClient,
          'mediaTotal': maxTotalMediaConnections,
          'eventsPerClient': maxEventSocketsPerClient,
          'eventsTotal': maxTotalEventSockets,
        },
        'maxChildren': 4,
        'comfortAudio': true,
        'nightLight': true,
        'twoWayTalk': true,
        'talkAudio': {
          'codec': 'pcm_s16le',
          'sampleRate': MiuCamServer._audioSampleRate,
          'channels': MiuCamServer._audioChannels,
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

  Map<String, Object?> _audioDetectionStatus() => {
        'paused': _features.roomAudio.mode != RoomAudioMode.idle,
        'reason': _features.roomAudio.mode == RoomAudioMode.idle
            ? null
            : _features.roomAudio.mode.name,
      };

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
      'audioDetection': _audioDetectionStatus(),
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
}

int? _ageMs(int nowMs, int? eventAtMs) =>
    eventAtMs == null ? null : max(0, nowMs - eventAtMs);
