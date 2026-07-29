import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analysis/audio/test_audio_generators.dart';

void main() {
  test(
      'native audio drop boundary keeps two short sounds separate while later continuous cry still alerts',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.cry_score_threshold': .45,
      'config.cry_min_duration_ms': 2500,
      'config.notify_cooldown_ms': 10000,
    });
    final preferences = await SharedPreferences.getInstance();
    final source = _TimedAudioMediaSource();
    final alerts = <String>[];
    final server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: alerts.add,
      mediaSource: source,
      startMediaOnSessionStart: false,
    );
    addTearDown(server.dispose);
    await server.startAudioRuntime();

    const baseTimestampMs = 1800000000000;
    source.emit(
      generateSinePcm16le(
        sampleRate: 16000,
        frequencyHz: 440,
        durationMs: 31000,
        amplitude: 0,
      ),
      metadata: const ServerAudioChunkMetadata(
        capturedAtMs: baseTimestampMs + 31000,
        capturedAtMonoUs: 31000000,
        sequence: 1,
        sampleRate: 16000,
        channels: 1,
      ),
    );

    var sequence = 2;
    sequence = _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 2200,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 32020,
      firstSequence: sequence,
    );
    sequence = _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 2200,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 34520,
      firstSequence: sequence + 4,
      discontinuityBefore: true,
    );
    await _settle();

    expect(
      alerts,
      isEmpty,
      reason: 'Kuyrukta kaybolan sessizlik iki kısa sesi tek ağlama yapmamalı.',
    );

    _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 6000,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 40020,
      firstSequence: sequence,
      discontinuityBefore: true,
    );
    await _settle();

    expect(
      alerts,
      hasLength(1),
      reason: 'Discontinuity koruması gerçek sürekli ağlamayı engellememeli.',
    );
  });

  test(
      'media lifecycle error keeps pre and post reconnect audio evidence separate',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.cry_score_threshold': .45,
      'config.cry_min_duration_ms': 2500,
      'config.notify_cooldown_ms': 10000,
    });
    final preferences = await SharedPreferences.getInstance();
    final source = _TimedAudioMediaSource();
    final alerts = <String>[];
    final server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: alerts.add,
      mediaSource: source,
      startMediaOnSessionStart: false,
    );
    addTearDown(server.dispose);
    await server.startAudioRuntime();

    const baseTimestampMs = 1800000100000;
    source.emit(
      generateSinePcm16le(
        sampleRate: 16000,
        frequencyHz: 440,
        durationMs: 31000,
        amplitude: 0,
      ),
      metadata: const ServerAudioChunkMetadata(
        capturedAtMs: baseTimestampMs + 31000,
        capturedAtMonoUs: 131000000,
        sequence: 1,
        sampleRate: 16000,
        channels: 1,
      ),
    );

    var sequence = _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 2200,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 32020,
      firstSequence: 2,
    );
    source.signalStreamDiscontinuity();
    sequence = _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 2200,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 34220,
      firstSequence: sequence,
    );
    await _settle();

    expect(
      alerts,
      isEmpty,
      reason: 'Reconnect öncesi ve sonrası kısa sesler birleştirilmemeli.',
    );

    _emitPcmIn20MsChunks(
      source,
      generateCryLikePcm16le(
        sampleRate: 16000,
        durationMs: 6000,
        amplitude: .8,
      ),
      firstChunkEndAtMs: baseTimestampMs + 40020,
      firstSequence: sequence,
      discontinuityBefore: true,
    );
    await _settle();

    expect(alerts, hasLength(1));
  });
}

int _emitPcmIn20MsChunks(
  _TimedAudioMediaSource source,
  Uint8List pcm16le, {
  required int firstChunkEndAtMs,
  required int firstSequence,
  bool discontinuityBefore = false,
}) {
  const chunkBytes = 16000 * 2 * 20 ~/ 1000;
  var sequence = firstSequence;
  var offset = 0;
  while (offset < pcm16le.length) {
    final end = offset + chunkBytes < pcm16le.length
        ? offset + chunkBytes
        : pcm16le.length;
    final chunk = Uint8List.sublistView(pcm16le, offset, end);
    final chunkIndex = offset ~/ chunkBytes;
    source.emit(
      chunk,
      metadata: ServerAudioChunkMetadata(
        capturedAtMs: firstChunkEndAtMs + chunkIndex * 20,
        capturedAtMonoUs: (firstChunkEndAtMs + chunkIndex * 20) * 1000,
        sequence: sequence,
        sampleRate: 16000,
        channels: 1,
        discontinuityBefore: discontinuityBefore && chunkIndex == 0,
      ),
    );
    sequence++;
    offset = end;
  }
  return sequence;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

class _TimedAudioMediaSource extends ServerMediaSource
    implements ServerAudioChunkMetadataSource {
  ServerAudioChunkSink? _audioSink;
  ServerMediaErrorSink? _errorSink;
  ServerAudioChunkMetadata? _currentMetadata;
  bool _active = false;
  int _audioChunks = 0;
  int? _lastAudioChunkAtMs;
  int _lastAudioChunkBytes = 0;

  @override
  bool get isActive => _active;

  @override
  ServerAudioChunkMetadata? get currentAudioChunkMetadata => _currentMetadata;

  @override
  ServerMediaSourceSnapshot get snapshot => ServerMediaSourceSnapshot(
        active: _active,
        videoFrames: 0,
        audioChunks: _audioChunks,
        lastVideoFrameAtMs: null,
        lastVideoFrameBytes: 0,
        lastAudioChunkAtMs: _lastAudioChunkAtMs,
        lastAudioChunkBytes: _lastAudioChunkBytes,
        lastError: null,
      );

  @override
  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) async {
    _active = video || audio;
    _audioSink = audio ? onAudioChunk : null;
    _errorSink = onError;
  }

  void signalStreamDiscontinuity() {
    final sink = _errorSink;
    if (!_active || sink == null) {
      throw StateError('Media source is not active.');
    }
    sink(
      const ServerMediaStreamDiscontinuity('test event stream restart'),
      StackTrace.current,
    );
  }

  void emit(
    Uint8List pcm16le, {
    required ServerAudioChunkMetadata metadata,
  }) {
    final sink = _audioSink;
    if (!_active || sink == null) {
      throw StateError('Audio source is not active.');
    }
    _currentMetadata = metadata;
    try {
      sink(pcm16le);
      _audioChunks++;
      _lastAudioChunkAtMs = metadata.capturedAtMs;
      _lastAudioChunkBytes = pcm16le.length;
    } finally {
      _currentMetadata = null;
    }
  }

  @override
  Future<void> stop() async {
    _active = false;
    _audioSink = null;
    _errorSink = null;
    _currentMetadata = null;
  }

  @override
  void resetDiagnostics() {
    _audioChunks = 0;
    _lastAudioChunkAtMs = null;
    _lastAudioChunkBytes = 0;
  }
}
