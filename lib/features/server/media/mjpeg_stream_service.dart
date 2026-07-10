import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/media/media_session_telemetry.dart';
import '../../../services/server/stream_backpressure_gate.dart';

typedef MjpegResponseFlusher = Future<void> Function(HttpResponse response);

Future<void> _flushMjpegResponse(HttpResponse response) => response.flush();

class MjpegStreamService {
  static final _keepAlivePart =
      utf8.encode('--frame\r\nContent-Length: 0\r\n\r\n\r\n');

  MjpegStreamService({
    this.flushTimeout = const Duration(milliseconds: 300),
    MjpegResponseFlusher? responseFlusher,
    void Function(String clientId)? onClientDetached,
    MediaSessionTelemetry? telemetry,
  })  : _responseFlusher = responseFlusher ?? _flushMjpegResponse,
        _onClientDetached = onClientDetached,
        _telemetry = telemetry ?? MediaSessionTelemetry.shared;

  final Duration flushTimeout;
  final MjpegResponseFlusher _responseFlusher;
  final void Function(String clientId)? _onClientDetached;
  final MediaSessionTelemetry _telemetry;
  final _clients = <HttpResponse>{};
  final _clientIds = <HttpResponse, String>{};
  final _pendingFrames = <HttpResponse, _PendingMjpegFrame>{};
  final _backpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.video);

  int _framesStreamed = 0;
  int _lastSequence = 0;
  int? _lastClientWriteAtMs;

  int get clientCount => _clients.length;
  bool get hasClients => _clients.isNotEmpty;
  StreamBackpressureMetrics get backpressureMetrics =>
      _backpressure.aggregateMetrics();
  MjpegStreamSnapshot get snapshot => MjpegStreamSnapshot(
        clientCount: _clients.length,
        framesStreamed: _framesStreamed,
        lastClientWriteAtMs: _lastClientWriteAtMs,
        backpressure: _backpressure.aggregateMetrics(),
      );

  Future<void> attachClient(
    HttpResponse response,
    String clientId, {
    Uint8List? firstFrame,
  }) async {
    // A low-FPS thermal/network profile may not fill dart:io's default output
    // buffer before the client's first-frame deadline. MJPEG is a live stream,
    // so every explicit flush must reach the socket immediately.
    response.bufferOutput = false;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/x-mixed-replace; boundary=frame',
    );
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store, no-transform')
      ..set('X-Accel-Buffering', 'no');
    _clients.add(response);
    _clientIds[response] = clientId;
    response.done.catchError((Object _) {}).whenComplete(() {
      removeClient(response);
    });
    if (firstFrame == null) {
      _backpressure.tryMarkBusy(response);
      try {
        response.add(_keepAlivePart);
        await _flushWithTimeout(response);
      } on TimeoutException {
        _backpressure.recordFailure(response);
        removeClient(response);
        await _closeResponseBestEffort(response);
      } catch (_) {
        _backpressure.recordFailure(response);
        removeClient(response);
        rethrow;
      } finally {
        _backpressure.markIdle(response);
        final pending = _pendingFrames.remove(response);
        if (pending != null && _clients.contains(response)) {
          _startDrain(response, pending);
        }
      }
      return;
    }

    final startedAt = DateTime.now();
    _backpressure.tryMarkBusy(response);
    try {
      await _writeFrame(
        response,
        firstFrame,
        sequence: _lastSequence,
      );
      _recordSuccess(response, duration: DateTime.now().difference(startedAt));
    } on TimeoutException {
      _backpressure.recordFailure(response);
      removeClient(response);
      await _closeResponseBestEffort(response);
    } catch (_) {
      _backpressure.recordFailure(response);
      removeClient(response);
      rethrow;
    } finally {
      _backpressure.markIdle(response);
      final pending = _pendingFrames.remove(response);
      if (pending != null && _clients.contains(response)) {
        _startDrain(response, pending);
      }
    }
  }

  void broadcast(
    Uint8List jpeg, {
    int? capturedAtMs,
    int? capturedAtMonoUs,
    int? encodeDurationUs,
    String? traceId,
  }) {
    if (jpeg.isEmpty) return;
    final sequence = ++_lastSequence;
    if (_clients.isEmpty) return;
    for (final client in _clients.toList()) {
      final frame = _PendingMjpegFrame(
        jpeg: jpeg,
        sequence: sequence,
        capturedAtMs: capturedAtMs,
        capturedAtMonoUs: capturedAtMonoUs,
        encodeDurationUs: encodeDurationUs,
        traceId: traceId,
      );
      if (_backpressure.isBusy(client)) {
        if (_pendingFrames.containsKey(client)) {
          _backpressure.recordSkippedVideoFrame(client);
          _telemetry.increment(MediaMetricName.videoSkippedTransportCount);
        }
        _pendingFrames[client] = frame;
        continue;
      }
      _startDrain(client, frame);
    }
  }

  void _startDrain(HttpResponse client, _PendingMjpegFrame first) {
    if (!_backpressure.tryMarkBusy(client)) {
      if (_pendingFrames.containsKey(client)) {
        _backpressure.recordSkippedVideoFrame(client);
        _telemetry.increment(MediaMetricName.videoSkippedTransportCount);
      }
      _pendingFrames[client] = first;
      return;
    }
    unawaited(_drainClient(client, first));
  }

  Future<void> _drainClient(
    HttpResponse client,
    _PendingMjpegFrame first,
  ) async {
    var current = first;
    try {
      while (_clients.contains(client)) {
        final startedAt = DateTime.now();
        await _writeFrame(
          client,
          current.jpeg,
          sequence: current.sequence,
          capturedAtMs: current.capturedAtMs,
          capturedAtMonoUs: current.capturedAtMonoUs,
          encodeDurationUs: current.encodeDurationUs,
          traceId: current.traceId,
        );
        _recordSuccess(client, duration: DateTime.now().difference(startedAt));
        final next = _pendingFrames.remove(client);
        if (next == null) break;
        current = next;
      }
    } catch (_) {
      if (_clients.contains(client)) {
        _backpressure.recordFailure(client);
        removeClient(client);
      }
      await _closeResponseBestEffort(client);
    } finally {
      _backpressure.markIdle(client);
      final pending = _pendingFrames.remove(client);
      if (pending != null && _clients.contains(client)) {
        _startDrain(client, pending);
      }
    }
  }

  void removeClient(HttpResponse response) {
    final hadClient = _clients.remove(response);
    final clientId = _clientIds.remove(response);
    _pendingFrames.remove(response);
    _backpressure.remove(response);
    if (hadClient && clientId != null) _onClientDetached?.call(clientId);
  }

  Future<void> closeClient(String clientId) async {
    final responses = _clientIds.entries
        .where((entry) => entry.value == clientId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final response in responses) {
      removeClient(response);
      try {
        await response.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
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
    _pendingFrames.clear();
    _backpressure.clear();
  }

  void resetDiagnostics() {
    _framesStreamed = 0;
    _lastSequence = 0;
    _lastClientWriteAtMs = null;
    _backpressure.clear();
  }

  Future<void> _flushWithTimeout(HttpResponse response) =>
      _responseFlusher(response).timeout(flushTimeout);

  Future<void> _closeResponseBestEffort(HttpResponse response) async {
    try {
      await response.close().timeout(flushTimeout);
    } catch (_) {}
  }

  void _recordSuccess(HttpResponse response, {required Duration duration}) {
    _framesStreamed++;
    _lastClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
    _backpressure.recordSuccess(response, duration: duration);
    _telemetry.recordDuration(MediaMetricName.videoSend, duration);
  }

  Future<void> _writeFrame(
    HttpResponse response,
    Uint8List jpeg, {
    required int sequence,
    int? capturedAtMs,
    int? capturedAtMonoUs,
    int? encodeDurationUs,
    String? traceId,
  }) async {
    final sentAtMs = DateTime.now().millisecondsSinceEpoch;
    response.add(utf8.encode(
      '--frame\r\nContent-Type: image/jpeg\r\n'
      'Content-Length: ${jpeg.length}\r\n'
      'X-MimiCam-Sequence: $sequence\r\n'
      '${capturedAtMs == null ? '' : 'X-MimiCam-Captured-At-Ms: $capturedAtMs\r\n'}'
      '${capturedAtMonoUs == null ? '' : 'X-MimiCam-Captured-Mono-Us: $capturedAtMonoUs\r\n'}'
      '${encodeDurationUs == null ? '' : 'X-MimiCam-Encode-Duration-Us: $encodeDurationUs\r\n'}'
      '${traceId == null ? '' : 'X-MimiCam-Trace-Id: $traceId\r\n'}'
      'X-MimiCam-Sent-At-Ms: $sentAtMs\r\n\r\n',
    ));
    response.add(jpeg);
    response.add(utf8.encode('\r\n'));
    await _flushWithTimeout(response);
  }
}

class _PendingMjpegFrame {
  const _PendingMjpegFrame({
    required this.jpeg,
    required this.sequence,
    required this.capturedAtMs,
    required this.capturedAtMonoUs,
    required this.encodeDurationUs,
    required this.traceId,
  });

  final Uint8List jpeg;
  final int sequence;
  final int? capturedAtMs;
  final int? capturedAtMonoUs;
  final int? encodeDurationUs;
  final String? traceId;
}

class MjpegStreamSnapshot {
  const MjpegStreamSnapshot({
    required this.clientCount,
    required this.framesStreamed,
    required this.lastClientWriteAtMs,
    required this.backpressure,
  });

  final int clientCount;
  final int framesStreamed;
  final int? lastClientWriteAtMs;
  final StreamBackpressureMetrics backpressure;
}
