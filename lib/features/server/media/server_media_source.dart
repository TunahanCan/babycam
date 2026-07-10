import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../analysis/video/luma_frame.dart';

typedef ServerVideoFrameSink = void Function(Uint8List jpeg);
typedef ServerAudioChunkSink = void Function(Uint8List pcm16le);
typedef ServerMediaErrorSink = void Function(Object error, StackTrace stack);

abstract class ServerMediaSource {
  bool get isActive;
  ServerMediaSourceSnapshot get snapshot;

  Future<void> start({
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) =>
      reconcile(
        video: true,
        audio: true,
        onVideoFrame: onVideoFrame,
        onAudioChunk: onAudioChunk,
        onError: onError,
      );

  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  });

  Future<void> stop();
  void resetDiagnostics();
}

/// Optional local-preview surface for media engines that do not expose a
/// Flutter camera controller (for example Android's service-owned CameraX
/// engine).
abstract interface class ServerJpegPreviewSource {
  Uint8List? get latestPreviewFrame;
  Stream<Uint8List> get previewFrames;
}

/// Optional analysis plane exposed by service-owned/native video sources.
/// Keeping this separate from JPEG delivery avoids decoding compressed frames
/// on the Dart isolate just to run motion detection.
abstract interface class ServerLumaFrameSource {
  Stream<LumaFrame> get lumaFrames;
}

/// Optional capture/encode policy sink for native media engines. The thermal
/// governor uses this to reduce work at the producer instead of dropping
/// already-encoded frames after they cross the platform channel.
abstract interface class ServerMediaPolicySink {
  Future<void> applyMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  });
}

class ServerMediaSourceSnapshot {
  const ServerMediaSourceSnapshot({
    required this.active,
    required this.videoFrames,
    required this.audioChunks,
    required this.lastVideoFrameAtMs,
    required this.lastVideoFrameBytes,
    required this.lastAudioChunkAtMs,
    required this.lastAudioChunkBytes,
    required this.lastError,
  });

  final bool active;
  final int videoFrames;
  final int audioChunks;
  final int? lastVideoFrameAtMs;
  final int lastVideoFrameBytes;
  final int? lastAudioChunkAtMs;
  final int lastAudioChunkBytes;
  final String? lastError;

  Map<String, Object?> toJson() => {
        'active': active,
        'videoFrames': videoFrames,
        'audioChunks': audioChunks,
        'lastVideoFrameAtMs': lastVideoFrameAtMs,
        'lastVideoFrameBytes': lastVideoFrameBytes,
        'lastAudioChunkAtMs': lastAudioChunkAtMs,
        'lastAudioChunkBytes': lastAudioChunkBytes,
        'lastError': lastError,
      };
}

class DeterministicServerMediaSource extends ServerMediaSource {
  DeterministicServerMediaSource({
    this.videoInterval = const Duration(milliseconds: 120),
    this.audioInterval = const Duration(milliseconds: 40),
    this.sampleRate = 16000,
    this.channels = 1,
    this.frequencyHz = 440,
    this.amplitude = .30,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Duration videoInterval;
  final Duration audioInterval;
  final int sampleRate;
  final int channels;
  final int frequencyHz;
  final double amplitude;
  final int Function() _nowMs;

  Timer? _videoTimer;
  Timer? _audioTimer;
  ServerVideoFrameSink? _videoSink;
  ServerAudioChunkSink? _audioSink;
  ServerMediaErrorSink? _errorSink;
  bool _active = false;
  int _videoFrames = 0;
  int _audioChunks = 0;
  int _audioSampleCursor = 0;
  int? _lastVideoFrameAtMs;
  int _lastVideoFrameBytes = 0;
  int? _lastAudioChunkAtMs;
  int _lastAudioChunkBytes = 0;
  String? _lastError;

  @override
  bool get isActive => _active;

  @override
  ServerMediaSourceSnapshot get snapshot => ServerMediaSourceSnapshot(
        active: _active,
        videoFrames: _videoFrames,
        audioChunks: _audioChunks,
        lastVideoFrameAtMs: _lastVideoFrameAtMs,
        lastVideoFrameBytes: _lastVideoFrameBytes,
        lastAudioChunkAtMs: _lastAudioChunkAtMs,
        lastAudioChunkBytes: _lastAudioChunkBytes,
        lastError: _lastError,
      );

  @override
  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) async {
    _videoSink = onVideoFrame;
    _audioSink = onAudioChunk;
    _errorSink = onError;
    _active = video || audio;
    if (video && _videoTimer == null) {
      _emitVideoFrame();
      _videoTimer = Timer.periodic(videoInterval, (_) => _emitVideoFrame());
    } else if (!video) {
      _videoTimer?.cancel();
      _videoTimer = null;
    }
    if (audio && _audioTimer == null) {
      _emitAudioChunk();
      _audioTimer = Timer.periodic(audioInterval, (_) => _emitAudioChunk());
    } else if (!audio) {
      _audioTimer?.cancel();
      _audioTimer = null;
    }
    if (!_active) {
      _videoSink = null;
      _audioSink = null;
      _errorSink = null;
    }
  }

  @override
  Future<void> stop() async {
    _videoTimer?.cancel();
    _audioTimer?.cancel();
    _videoTimer = null;
    _audioTimer = null;
    _videoSink = null;
    _audioSink = null;
    _errorSink = null;
    _active = false;
  }

  @override
  void resetDiagnostics() {
    _videoFrames = 0;
    _audioChunks = 0;
    _audioSampleCursor = 0;
    _lastVideoFrameAtMs = null;
    _lastVideoFrameBytes = 0;
    _lastAudioChunkAtMs = null;
    _lastAudioChunkBytes = 0;
    _lastError = null;
  }

  void _emitVideoFrame() {
    final sink = _videoSink;
    if (!_active || sink == null) return;
    try {
      final frame = Uint8List.fromList(_tinyJpeg);
      _videoFrames++;
      _lastVideoFrameAtMs = _nowMs();
      _lastVideoFrameBytes = frame.length;
      sink(frame);
    } catch (error, stack) {
      _recordError(error, stack);
    }
  }

  void _emitAudioChunk() {
    final sink = _audioSink;
    if (!_active || sink == null) return;
    try {
      final chunk = _sineChunk();
      _audioChunks++;
      _lastAudioChunkAtMs = _nowMs();
      _lastAudioChunkBytes = chunk.length;
      sink(chunk);
    } catch (error, stack) {
      _recordError(error, stack);
    }
  }

  Uint8List _sineChunk() {
    final safeChannels = max(1, channels);
    final sampleCount =
        max(1, sampleRate * audioInterval.inMilliseconds ~/ 1000);
    final output = Uint8List(sampleCount * safeChannels * 2);
    final view = ByteData.sublistView(output);
    final amplitudeInt = (32767 * amplitude.clamp(.02, .80)).round();
    for (var sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
      final sample = (sin(
                2 *
                    pi *
                    frequencyHz *
                    (_audioSampleCursor + sampleIndex) /
                    sampleRate,
              ) *
              amplitudeInt)
          .round();
      for (var channel = 0; channel < safeChannels; channel++) {
        final offset = (sampleIndex * safeChannels + channel) * 2;
        view.setInt16(offset, sample, Endian.little);
      }
    }
    _audioSampleCursor += sampleCount;
    return output;
  }

  void _recordError(Object error, StackTrace stack) {
    _lastError = error.toString();
    _errorSink?.call(error, stack);
  }
}

final _tinyJpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////'
  '2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/'
  '8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/'
  '9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/ASP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/ASP/'
  'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Ap//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IV//2gAMAwEAAgADAAAAEP/'
  'EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8QH//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8QH//EABQQAQAAAAAAAAAAAA'
  'AAAAAAABD/2gAIAQEAAT8QH//Z',
);
