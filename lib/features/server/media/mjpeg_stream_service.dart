import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../services/server/stream_backpressure_gate.dart';

class MjpegStreamService {
  MjpegStreamService({
    void Function(String clientId)? onClientDetached,
  }) : _onClientDetached = onClientDetached;

  final void Function(String clientId)? _onClientDetached;
  final _clients = <HttpResponse>{};
  final _clientIds = <HttpResponse, String>{};
  final _backpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.video);

  int _framesStreamed = 0;
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
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/x-mixed-replace; boundary=frame',
    );
    _clients.add(response);
    _clientIds[response] = clientId;
    response.done.catchError((Object _) {}).whenComplete(() {
      removeClient(response);
    });
    if (firstFrame == null) return;

    final startedAt = DateTime.now();
    try {
      await _writeFrame(response, firstFrame);
      _recordSuccess(response, duration: DateTime.now().difference(startedAt));
    } catch (_) {
      _backpressure.recordFailure(response);
      removeClient(response);
      rethrow;
    }
  }

  void broadcast(Uint8List jpeg) {
    if (jpeg.isEmpty || _clients.isEmpty) return;
    for (final client in _clients.toList()) {
      if (!_backpressure.tryMarkBusy(client)) continue;
      final startedAt = DateTime.now();
      unawaited(_writeFrame(client, jpeg).then<void>((_) {
        _recordSuccess(client, duration: DateTime.now().difference(startedAt));
      }).catchError((Object _) {
        _backpressure.recordFailure(client);
        removeClient(client);
      }).whenComplete(() => _backpressure.markIdle(client)));
    }
  }

  void removeClient(HttpResponse response) {
    final hadClient = _clients.remove(response);
    final clientId = _clientIds.remove(response);
    _backpressure.remove(response);
    if (hadClient && clientId != null) _onClientDetached?.call(clientId);
  }

  Future<void> closeAll() async {
    for (final response in _clients.toList()) {
      removeClient(response);
      try {
        await response.close();
      } catch (_) {}
    }
    _clients.clear();
    _clientIds.clear();
    _backpressure.clear();
  }

  void resetDiagnostics() {
    _framesStreamed = 0;
    _lastClientWriteAtMs = null;
    _backpressure.clear();
  }

  void _recordSuccess(HttpResponse response, {required Duration duration}) {
    _framesStreamed++;
    _lastClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
    _backpressure.recordSuccess(response, duration: duration);
  }

  Future<void> _writeFrame(HttpResponse response, Uint8List jpeg) async {
    response.add(utf8.encode(
      '--frame\r\nContent-Type: image/jpeg\r\n'
      'Content-Length: ${jpeg.length}\r\n\r\n',
    ));
    response.add(jpeg);
    response.add(utf8.encode('\r\n'));
    await response.flush();
  }
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
