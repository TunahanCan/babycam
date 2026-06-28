import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'pcm_audio_output.dart';
import 'wav_pcm_stream_parser.dart';

class ClientLiveAudioPipeline {
  ClientLiveAudioPipeline({
    PcmAudioSink audioOutput = const PcmAudioOutput(),
    HttpClient Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 5),
    this.retryDelay = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 4),
    this.maxBufferedAudio = const Duration(milliseconds: 1200),
  })  : _audioOutput = audioOutput,
        _clientFactory = clientFactory;

  final PcmAudioSink _audioOutput;
  final HttpClient Function()? _clientFactory;
  final Duration connectTimeout;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Duration maxBufferedAudio;

  HttpClient? _client;
  _PipelineRun? _run;
  int _generation = 0;
  bool _outputStarted = false;
  ClientAudioJitterBuffer? _buffer;

  bool get isRunning => _run != null;

  Future<void> start({
    required Uri uri,
    required String pairedServerHost,
    required int pairedServerPort,
    String? bearerToken,
    VoidCallback? onAudioChunkWritten,
    ValueChanged<ClientLiveAudioStatus>? onStatus,
    ValueChanged<Object>? onError,
  }) async {
    await stop();
    final generation = ++_generation;
    final run = _PipelineRun(
      uri: uri,
      pairedServerHost: pairedServerHost,
      pairedServerPort: pairedServerPort,
      bearerToken: bearerToken,
      onAudioChunkWritten: onAudioChunkWritten,
      onStatus: onStatus,
      onError: onError,
    );
    _run = run;
    unawaited(_runLoop(generation, run));
  }

  Future<void> stop() async {
    _generation++;
    _run = null;
    _closeClient();
    _buffer = null;
    if (_outputStarted) {
      _outputStarted = false;
      try {
        await _audioOutput.stop();
      } catch (_) {}
    }
  }

  Future<void> _runLoop(int generation, _PipelineRun run) async {
    var nextRetry = retryDelay;
    while (_isCurrent(generation, run)) {
      try {
        await _connectAndPump(generation, run);
        nextRetry = retryDelay;
      } catch (error) {
        if (!_isCurrent(generation, run)) return;
        run.lastError = error;
        run.reconnects++;
        run.onError?.call(error);
        _emitStatus(run, 'error');
        await Future<void>.delayed(nextRetry);
        nextRetry = Duration(
          milliseconds: min(
            maxRetryDelay.inMilliseconds,
            (nextRetry.inMilliseconds * 1.7).round(),
          ),
        );
      }
    }
  }

  Future<void> _connectAndPump(int generation, _PipelineRun run) async {
    _validateUri(run.uri, run.pairedServerHost, run.pairedServerPort);
    if (_outputStarted) {
      _outputStarted = false;
      try {
        await _audioOutput.stop();
      } catch (_) {}
    }
    final client = (_clientFactory?.call() ?? HttpClient())
      ..connectionTimeout = connectTimeout;
    _client = client;
    final parser = WavPcmStreamParser();
    _buffer = null;
    run.connectedAtMs = _nowMs();
    _emitStatus(run, 'connecting');

    try {
      final request = await client.getUrl(run.uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'audio/wav, audio/x-wav, application/octet-stream',
      );
      final bearerToken = run.bearerToken;
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Audio stream failed with HTTP ${response.statusCode}',
          uri: run.uri,
        );
      }

      await for (final chunk in response) {
        if (!_isCurrent(generation, run)) return;
        run.networkBytesReceived += chunk.length;
        final parsed = parser.add(Uint8List.fromList(chunk));
        if (!_outputStarted && parsed.isConfigured) {
          await _audioOutput.start(
            sampleRate: parsed.sampleRate,
            channels: parsed.channels,
          );
          _outputStarted = true;
          _buffer = ClientAudioJitterBuffer(
            bytesPerFrame: parsed.channels * 2,
            maxBytes: _bufferBytesFor(
              sampleRate: parsed.sampleRate,
              channels: parsed.channels,
            ),
          );
          run.sampleRate = parsed.sampleRate;
          run.channels = parsed.channels;
          _emitStatus(run, 'started');
        }
        if (parsed.pcm16le.isEmpty || !_outputStarted) continue;
        final buffer = _buffer;
        if (buffer == null) continue;
        final beforeDropped = buffer.droppedBytes;
        buffer.add(parsed.pcm16le);
        run.droppedBufferBytes += buffer.droppedBytes - beforeDropped;
        await _drainBuffer(generation, run);
      }
      throw HttpException('Audio stream ended', uri: run.uri);
    } finally {
      if (_client == client) _client = null;
      client.close(force: true);
    }
  }

  Future<void> _drainBuffer(int generation, _PipelineRun run) async {
    final buffer = _buffer;
    if (buffer == null || run.draining) return;
    run.draining = true;
    try {
      while (_isCurrent(generation, run) && buffer.hasData) {
        final frame = buffer.takeNext(maxBytes: run.preferredWriteBytes);
        if (frame.isEmpty) return;
        final accepted = await _audioOutput.write(frame);
        run.chunksWritten++;
        run.bytesWritten += frame.length;
        if (accepted) {
          run.lastWriteAtMs = _nowMs();
          run.onAudioChunkWritten?.call();
        } else {
          run.droppedNativeWrites++;
        }
        if (run.chunksWritten == 1 || run.chunksWritten % 25 == 0) {
          await _emitStatus(run, 'write');
        }
      }
    } finally {
      run.draining = false;
    }
  }

  Future<void> _emitStatus(_PipelineRun run, String event) async {
    Map<String, Object?> nativeStatus = const {};
    if (_outputStarted || event == 'error') {
      try {
        nativeStatus = await _audioOutput.status();
      } catch (_) {}
    }
    final status = ClientLiveAudioStatus(
      event: event,
      connectedAtMs: run.connectedAtMs,
      sampleRate: run.sampleRate,
      channels: run.channels,
      networkBytesReceived: run.networkBytesReceived,
      bytesWritten: run.bytesWritten,
      chunksWritten: run.chunksWritten,
      bufferedBytes: _buffer?.bufferedBytes ?? 0,
      droppedBufferBytes: run.droppedBufferBytes,
      droppedNativeWrites: run.droppedNativeWrites,
      reconnects: run.reconnects,
      lastWriteAtMs: run.lastWriteAtMs,
      lastError: run.lastError,
      nativeStatus: nativeStatus,
    );
    run.onStatus?.call(status);
    debugPrint('MimiCam live audio ${status.toJson()}');
  }

  bool _isCurrent(int generation, _PipelineRun run) =>
      generation == _generation && identical(_run, run);

  void _validateUri(Uri uri, String pairedHost, int pairedPort) {
    final allowed = (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host == pairedHost &&
        uri.port == pairedPort;
    if (!allowed) {
      throw StateError('Audio stream host is not the paired server.');
    }
  }

  int _bufferBytesFor({required int sampleRate, required int channels}) {
    final bytesPerSecond = sampleRate * channels * 2;
    return max(2048, bytesPerSecond * maxBufferedAudio.inMilliseconds ~/ 1000);
  }

  void _closeClient() {
    _client?.close(force: true);
    _client = null;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}

class ClientAudioJitterBuffer {
  ClientAudioJitterBuffer({
    required this.bytesPerFrame,
    required this.maxBytes,
  });

  final int bytesPerFrame;
  final int maxBytes;
  final _chunks = <Uint8List>[];
  int _bufferedBytes = 0;
  int droppedBytes = 0;

  int get bufferedBytes => _bufferedBytes;
  bool get hasData => _bufferedBytes > 0;

  void add(Uint8List bytes) {
    final alignedLength = bytes.length - (bytes.length % bytesPerFrame);
    if (alignedLength <= 0) return;
    var aligned = Uint8List.sublistView(bytes, 0, alignedLength);
    final alignedMaxBytes = maxBytes - (maxBytes % bytesPerFrame);
    if (aligned.length > alignedMaxBytes) {
      final keepBytes = max(bytesPerFrame, alignedMaxBytes);
      droppedBytes += aligned.length - keepBytes;
      aligned = Uint8List.sublistView(
        bytes,
        alignedLength - keepBytes,
        alignedLength,
      );
    }
    _chunks.add(aligned);
    _bufferedBytes += aligned.length;
    _trimToBudget();
  }

  Uint8List takeNext({required int maxBytes}) {
    if (_chunks.isEmpty) return Uint8List(0);
    final first = _chunks.removeAt(0);
    if (first.length <= maxBytes) {
      _bufferedBytes -= first.length;
      return first;
    }

    final alignedMax =
        max(bytesPerFrame, maxBytes - (maxBytes % bytesPerFrame));
    final head = Uint8List.sublistView(first, 0, alignedMax);
    final tail = Uint8List.sublistView(first, alignedMax);
    _chunks.insert(0, tail);
    _bufferedBytes -= head.length;
    return head;
  }

  void _trimToBudget() {
    while (_bufferedBytes > maxBytes && _chunks.isNotEmpty) {
      final overflow = _bufferedBytes - maxBytes;
      final alignedOverflow =
          max(bytesPerFrame, overflow - (overflow % bytesPerFrame));
      final first = _chunks.first;
      if (first.length <= alignedOverflow) {
        final dropped = _chunks.removeAt(0);
        _bufferedBytes -= dropped.length;
        droppedBytes += dropped.length;
      } else {
        _chunks[0] = Uint8List.sublistView(first, alignedOverflow);
        _bufferedBytes -= alignedOverflow;
        droppedBytes += alignedOverflow;
      }
    }
  }
}

class ClientLiveAudioStatus {
  const ClientLiveAudioStatus({
    required this.event,
    required this.connectedAtMs,
    required this.sampleRate,
    required this.channels,
    required this.networkBytesReceived,
    required this.bytesWritten,
    required this.chunksWritten,
    required this.bufferedBytes,
    required this.droppedBufferBytes,
    required this.droppedNativeWrites,
    required this.reconnects,
    required this.lastWriteAtMs,
    required this.lastError,
    required this.nativeStatus,
  });

  final String event;
  final int? connectedAtMs;
  final int? sampleRate;
  final int? channels;
  final int networkBytesReceived;
  final int bytesWritten;
  final int chunksWritten;
  final int bufferedBytes;
  final int droppedBufferBytes;
  final int droppedNativeWrites;
  final int reconnects;
  final int? lastWriteAtMs;
  final Object? lastError;
  final Map<String, Object?> nativeStatus;

  Map<String, Object?> toJson() => {
        'event': event,
        'connectedAtMs': connectedAtMs,
        'sampleRate': sampleRate,
        'channels': channels,
        'networkBytesReceived': networkBytesReceived,
        'bytesWritten': bytesWritten,
        'chunksWritten': chunksWritten,
        'bufferedBytes': bufferedBytes,
        'droppedBufferBytes': droppedBufferBytes,
        'droppedNativeWrites': droppedNativeWrites,
        'reconnects': reconnects,
        'lastWriteAtMs': lastWriteAtMs,
        if (lastError != null) 'lastError': lastError.toString(),
        'native': nativeStatus,
      };
}

class _PipelineRun {
  _PipelineRun({
    required this.uri,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.bearerToken,
    required this.onAudioChunkWritten,
    required this.onStatus,
    required this.onError,
  });

  final Uri uri;
  final String pairedServerHost;
  final int pairedServerPort;
  final String? bearerToken;
  final VoidCallback? onAudioChunkWritten;
  final ValueChanged<ClientLiveAudioStatus>? onStatus;
  final ValueChanged<Object>? onError;

  int? connectedAtMs;
  int? sampleRate;
  int? channels;
  int networkBytesReceived = 0;
  int bytesWritten = 0;
  int chunksWritten = 0;
  int droppedBufferBytes = 0;
  int droppedNativeWrites = 0;
  int reconnects = 0;
  int? lastWriteAtMs;
  Object? lastError;
  bool draining = false;

  int get preferredWriteBytes {
    final safeSampleRate = sampleRate ?? 16000;
    final safeChannels = channels ?? 1;
    return max(1024, safeSampleRate * safeChannels * 2 ~/ 8);
  }
}
