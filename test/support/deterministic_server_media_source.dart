import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:miucam/features/server/media/server_media_source.dart';

/// Predictable media producer used by endpoint and runtime scenario tests.
///
/// Keeping this fixture under `test/` prevents synthetic camera and microphone
/// behavior from becoming part of the shipped application.
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
