import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/media/media_session_telemetry.dart';
import '../../../services/server/stream_backpressure_gate.dart';
import '../../../services/server/wav_pcm16.dart';

typedef AudioResponseFlusher = Future<void> Function(HttpResponse response);

Future<void> _flushAudioResponse(HttpResponse response) => response.flush();

class WavAudioStreamService {
  WavAudioStreamService({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    this.frameDuration = const Duration(milliseconds: 20),
    this.maxQueuedAudio = const Duration(milliseconds: 160),
    this.flushTimeout = const Duration(milliseconds: 300),
    AudioResponseFlusher? responseFlusher,
    void Function(String clientId)? onClientDetached,
    MediaSessionTelemetry? telemetry,
  })  : _onClientDetached = onClientDetached,
        _responseFlusher = responseFlusher ?? _flushAudioResponse,
        _telemetry = telemetry ?? MediaSessionTelemetry.shared,
        _framePacketizer = PcmAudioFramePacketizer(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          frameDuration: frameDuration,
        );

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Duration frameDuration;
  final Duration maxQueuedAudio;
  final Duration flushTimeout;
  final void Function(String clientId)? _onClientDetached;
  final AudioResponseFlusher _responseFlusher;
  final MediaSessionTelemetry _telemetry;
  final PcmAudioFramePacketizer _framePacketizer;

  final _clients = <HttpResponse>{};
  final _clientIds = <HttpResponse, String>{};
  final _clientDetachCallbacks = <HttpResponse, void Function()>{};
  final _busyClientIds = <String>{};
  final _clientQueues = <HttpResponse, BoundedAudioFrameQueue>{};
  final _backpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.audio);

  int _chunksStreamed = 0;
  int _bytesStreamed = 0;
  int _sourceChunksAccepted = 0;
  int _sourceBytesAccepted = 0;
  int _lastSequence = 0;
  int? _lastSourceChunkAtMs;
  int _lastSourceChunkBytes = 0;
  int? _lastClientWriteAtMs;
  int _lastClientWriteBytes = 0;

  int get clientCount => _clients.length;
  bool get hasClients => _clients.isNotEmpty;
  StreamBackpressureMetrics get backpressureMetrics =>
      _backpressure.aggregateMetrics();
  WavAudioStreamSnapshot get snapshot => WavAudioStreamSnapshot(
        clientCount: _clients.length,
        clientIds: List.unmodifiable(_clientIds.values),
        busyClientIds: List.unmodifiable(_busyClientIds),
        chunksStreamed: _chunksStreamed,
        bytesStreamed: _bytesStreamed,
        sourceChunksAccepted: _sourceChunksAccepted,
        sourceBytesAccepted: _sourceBytesAccepted,
        lastSequence: _lastSequence,
        lastSourceChunkAtMs: _lastSourceChunkAtMs,
        lastSourceChunkBytes: _lastSourceChunkBytes,
        lastClientWriteAtMs: _lastClientWriteAtMs,
        lastClientWriteBytes: _lastClientWriteBytes,
        backpressure: _backpressure.aggregateMetrics(),
      );

  Future<void> attachClient(
    HttpResponse response,
    String clientId, {
    void Function()? onDetached,
  }) async {
    response.bufferOutput = false;
    response.headers
      ..contentType = ContentType('audio', 'wav')
      ..chunkedTransferEncoding = true
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set(HttpHeaders.acceptRangesHeader, 'none')
      ..set('X-Audio-Sample-Rate', '$sampleRate')
      ..set('X-Audio-Channels', '$channels')
      ..set('X-Audio-Bits-Per-Sample', '$bitsPerSample')
      ..set('X-Audio-Frame-Duration-Ms', '${frameDuration.inMilliseconds}')
      ..set('X-Audio-Max-Queue-Ms', '${maxQueuedAudio.inMilliseconds}');
    response.add(WavPcm16.header(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    ));
    _clients.add(response);
    _clientIds[response] = clientId;
    if (onDetached != null) {
      _clientDetachCallbacks[response] = onDetached;
    }
    _clientQueues[response] = BoundedAudioFrameQueue(
      maxFrames: max(
        1,
        maxQueuedAudio.inMicroseconds ~/ frameDuration.inMicroseconds,
      ),
    );
    _backpressure.tryMarkBusy(response);
    _busyClientIds.add(clientId);
    response.done.catchError((Object _) {}).whenComplete(() {
      removeClient(response);
    });
    try {
      await _flushWithTimeout(response);
    } on TimeoutException {
      _backpressure.recordFailure(response);
      removeClient(response);
      await _closeResponseBestEffort(response);
    } catch (_) {
      removeClient(response);
      rethrow;
    } finally {
      _backpressure.markIdle(response);
      _busyClientIds.remove(clientId);
      _startDrainIfQueued(response);
    }
  }

  void broadcast(Uint8List pcm16le) {
    if (pcm16le.isEmpty) return;
    _sourceChunksAccepted++;
    _sourceBytesAccepted += pcm16le.length;
    _lastSourceChunkAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastSourceChunkBytes = pcm16le.length;
    if (_clients.isEmpty) {
      _framePacketizer.reset();
      return;
    }

    for (final frame in _framePacketizer.add(pcm16le)) {
      _lastSequence++;
      for (final client in _clients.toList()) {
        final queue = _clientQueues[client];
        if (queue == null) continue;
        final droppedFrames = queue.add(frame);
        for (var index = 0; index < droppedFrames; index++) {
          _backpressure.recordSkippedAudioChunk(client);
        }
        if (droppedFrames > 0) {
          _telemetry.increment(
            MediaMetricName.audioDroppedCount,
            droppedFrames,
          );
        }
        if (droppedFrames > 0) {
          _detachSlowClient(client);
          continue;
        }
        if (!_backpressure.isBusy(client) &&
            _backpressure.tryMarkBusy(client)) {
          unawaited(_drainClient(client));
        }
      }
    }
  }

  Future<void> _drainClient(HttpResponse client) async {
    final clientId = _clientIds[client];
    if (clientId != null) _busyClientIds.add(clientId);
    try {
      while (_clients.contains(client)) {
        final frame = _clientQueues[client]?.takeNext();
        if (frame == null) break;
        final startedAt = DateTime.now();
        client.add(frame);
        await _flushWithTimeout(client);
        if (!_clients.contains(client)) break;
        _chunksStreamed++;
        _bytesStreamed += frame.length;
        _lastClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
        _lastClientWriteBytes = frame.length;
        _backpressure.recordSuccess(
          client,
          duration: DateTime.now().difference(startedAt),
        );
        _telemetry.recordDuration(
          MediaMetricName.audioSend,
          DateTime.now().difference(startedAt),
        );
      }
    } catch (_) {
      if (_clients.contains(client)) {
        _backpressure.recordFailure(client);
        removeClient(client);
      }
      await _closeResponseBestEffort(client);
    } finally {
      _backpressure.markIdle(client);
      if (clientId != null) _busyClientIds.remove(clientId);
      _startDrainIfQueued(client);
    }
  }

  void _startDrainIfQueued(HttpResponse client) {
    if (_clients.contains(client) &&
        (_clientQueues[client]?.hasData ?? false) &&
        !_backpressure.isBusy(client) &&
        _backpressure.tryMarkBusy(client)) {
      unawaited(_drainClient(client));
    }
  }

  Future<void> _flushWithTimeout(HttpResponse response) =>
      _responseFlusher(response).timeout(flushTimeout);

  void _detachSlowClient(HttpResponse response) {
    removeClient(response);
    unawaited(_closeResponseBestEffort(response));
  }

  Future<void> _closeResponseBestEffort(HttpResponse response) async {
    try {
      await response.close().timeout(flushTimeout);
    } catch (_) {}
  }

  void removeClient(HttpResponse response) {
    final hadClient = _clients.remove(response);
    final clientId = _clientIds.remove(response);
    final detach = _clientDetachCallbacks.remove(response);
    _clientQueues.remove(response);
    if (clientId != null) _busyClientIds.remove(clientId);
    _backpressure.remove(response);
    if (hadClient && clientId != null) {
      if (detach != null) {
        detach();
      } else {
        _onClientDetached?.call(clientId);
      }
    }
  }

  Future<void> closeClient(String clientId) async {
    final responses = _clientIds.entries
        .where((entry) => entry.value == clientId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final response in responses) {
      removeClient(response);
      await _closeResponseBestEffort(response);
    }
  }

  Future<void> closeAll() async {
    for (final response in _clients.toList()) {
      removeClient(response);
      try {
        await response.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
    _clients.clear();
    _clientIds.clear();
    _clientDetachCallbacks.clear();
    _clientQueues.clear();
    _busyClientIds.clear();
    _backpressure.clear();
  }

  void resetDiagnostics() {
    _chunksStreamed = 0;
    _bytesStreamed = 0;
    _sourceChunksAccepted = 0;
    _sourceBytesAccepted = 0;
    _lastSequence = 0;
    _lastSourceChunkAtMs = null;
    _lastSourceChunkBytes = 0;
    _lastClientWriteAtMs = null;
    _lastClientWriteBytes = 0;
    _framePacketizer.reset();
    _backpressure.clear();
    _busyClientIds.clear();
  }
}

/// Converts arbitrary recorder chunks to stable real-time PCM frames.
/// RFC 3551 recommends a 20 ms default packetization interval for audio.
class PcmAudioFramePacketizer {
  PcmAudioFramePacketizer({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    this.frameDuration = const Duration(milliseconds: 20),
  })  : bytesPerSampleFrame = max(1, channels * bitsPerSample ~/ 8),
        frameBytes = max(
          1,
          sampleRate *
              max(1, channels * bitsPerSample ~/ 8) *
              frameDuration.inMicroseconds ~/
              Duration.microsecondsPerSecond,
        );

  final Duration frameDuration;
  final int bytesPerSampleFrame;
  final int frameBytes;
  Uint8List _pending = Uint8List(0);

  int get pendingBytes => _pending.length;

  List<Uint8List> add(Uint8List pcm) {
    if (pcm.isEmpty) return const [];
    final combined = Uint8List(_pending.length + pcm.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + pcm.length, pcm);
    final alignedFrameBytes = frameBytes - (frameBytes % bytesPerSampleFrame);
    final safeFrameBytes = max(bytesPerSampleFrame, alignedFrameBytes);
    final frameCount = combined.length ~/ safeFrameBytes;
    if (frameCount == 0) {
      _pending = combined;
      return const [];
    }
    final frames = List<Uint8List>.generate(
      frameCount,
      (index) => Uint8List.sublistView(
        combined,
        index * safeFrameBytes,
        (index + 1) * safeFrameBytes,
      ),
      growable: false,
    );
    final consumed = frameCount * safeFrameBytes;
    _pending = consumed == combined.length
        ? Uint8List(0)
        : Uint8List.fromList(Uint8List.sublistView(combined, consumed));
    return frames;
  }

  void reset() => _pending = Uint8List(0);
}

/// Per-client overwrite-oldest queue: bounded latency is preferred to
/// replaying stale baby-monitor audio after a temporary network stall.
class BoundedAudioFrameQueue {
  BoundedAudioFrameQueue({required this.maxFrames})
      : assert(maxFrames > 0, 'maxFrames must be positive');

  final int maxFrames;
  final ListQueue<Uint8List> _frames = ListQueue<Uint8List>();

  int get length => _frames.length;
  bool get hasData => _frames.isNotEmpty;

  int add(Uint8List frame) {
    if (frame.isEmpty) return 0;
    var dropped = 0;
    while (_frames.length >= maxFrames) {
      _frames.removeFirst();
      dropped++;
    }
    _frames.addLast(frame);
    return dropped;
  }

  Uint8List? takeNext() => _frames.isEmpty ? null : _frames.removeFirst();
}

class WavAudioStreamSnapshot {
  const WavAudioStreamSnapshot({
    required this.clientCount,
    required this.clientIds,
    required this.busyClientIds,
    required this.chunksStreamed,
    required this.bytesStreamed,
    required this.sourceChunksAccepted,
    required this.sourceBytesAccepted,
    required this.lastSequence,
    required this.lastSourceChunkAtMs,
    required this.lastSourceChunkBytes,
    required this.lastClientWriteAtMs,
    required this.lastClientWriteBytes,
    required this.backpressure,
  });

  final int clientCount;
  final List<String> clientIds;
  final List<String> busyClientIds;
  final int chunksStreamed;
  final int bytesStreamed;
  final int sourceChunksAccepted;
  final int sourceBytesAccepted;
  final int lastSequence;
  final int? lastSourceChunkAtMs;
  final int lastSourceChunkBytes;
  final int? lastClientWriteAtMs;
  final int lastClientWriteBytes;
  final StreamBackpressureMetrics backpressure;
}
