import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../services/server/stream_backpressure_gate.dart';
import '../../../services/server/wav_pcm16.dart';

class WavAudioStreamService {
  WavAudioStreamService({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    void Function(String clientId)? onClientDetached,
  }) : _onClientDetached = onClientDetached;

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final void Function(String clientId)? _onClientDetached;

  final _clients = <HttpResponse>{};
  final _clientIds = <HttpResponse, String>{};
  final _busyClientIds = <String>{};
  final _backpressure =
      StreamBackpressureGate<HttpResponse>(kind: StreamBackpressureKind.audio);

  int _chunksStreamed = 0;
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
        lastClientWriteAtMs: _lastClientWriteAtMs,
        lastClientWriteBytes: _lastClientWriteBytes,
        backpressure: _backpressure.aggregateMetrics(),
      );

  Future<void> attachClient(HttpResponse response, String clientId) async {
    response.headers
      ..contentType = ContentType('audio', 'wav')
      ..chunkedTransferEncoding = true
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set(HttpHeaders.acceptRangesHeader, 'none')
      ..set('X-Audio-Sample-Rate', '$sampleRate')
      ..set('X-Audio-Channels', '$channels')
      ..set('X-Audio-Bits-Per-Sample', '$bitsPerSample');
    response.add(WavPcm16.header(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    ));
    _clients.add(response);
    _clientIds[response] = clientId;
    response.done.catchError((Object _) {}).whenComplete(() {
      removeClient(response);
    });
    try {
      await response.flush();
    } catch (_) {
      removeClient(response);
      rethrow;
    }
  }

  void broadcast(Uint8List pcm16le) {
    if (pcm16le.isEmpty || _clients.isEmpty) return;
    for (final client in _clients.toList()) {
      final clientId = _clientIds[client];
      if (!_backpressure.tryMarkBusy(client)) continue;
      if (clientId != null) _busyClientIds.add(clientId);
      final startedAt = DateTime.now();
      try {
        client.add(pcm16le);
        unawaited(client.flush().then<void>((_) {
          _chunksStreamed++;
          _lastClientWriteAtMs = DateTime.now().millisecondsSinceEpoch;
          _lastClientWriteBytes = pcm16le.length;
          _backpressure.recordSuccess(
            client,
            duration: DateTime.now().difference(startedAt),
          );
        }).catchError((Object _) {
          _backpressure.recordFailure(client);
          removeClient(client);
        }).whenComplete(() {
          _backpressure.markIdle(client);
          if (clientId != null) _busyClientIds.remove(clientId);
        }));
      } catch (_) {
        _backpressure.recordFailure(client);
        removeClient(client);
        if (clientId != null) _busyClientIds.remove(clientId);
      }
    }
  }

  void removeClient(HttpResponse response) {
    final hadClient = _clients.remove(response);
    final clientId = _clientIds.remove(response);
    if (clientId != null) _busyClientIds.remove(clientId);
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
    _busyClientIds.clear();
    _backpressure.clear();
  }

  void resetDiagnostics() {
    _chunksStreamed = 0;
    _lastClientWriteAtMs = null;
    _lastClientWriteBytes = 0;
    _backpressure.clear();
    _busyClientIds.clear();
  }
}

class WavAudioStreamSnapshot {
  const WavAudioStreamSnapshot({
    required this.clientCount,
    required this.clientIds,
    required this.busyClientIds,
    required this.chunksStreamed,
    required this.lastClientWriteAtMs,
    required this.lastClientWriteBytes,
    required this.backpressure,
  });

  final int clientCount;
  final List<String> clientIds;
  final List<String> busyClientIds;
  final int chunksStreamed;
  final int? lastClientWriteAtMs;
  final int lastClientWriteBytes;
  final StreamBackpressureMetrics backpressure;
}
