import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/device_feature_models.dart';
import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../server/media/microphone_capture_service.dart';

class ClientRoomControlSnapshot {
  const ClientRoomControlSnapshot({
    this.comfort,
    this.talking = false,
    this.talkBytesSent = 0,
    this.talkBytesDropped = 0,
    this.lastError,
  });

  final ComfortAudioState? comfort;
  final bool talking;
  final int talkBytesSent;
  final int talkBytesDropped;
  final Object? lastError;
}

class ClientRoomControls {
  ClientRoomControls({
    MicrophoneCaptureService? microphone,
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 5),
    Duration? talkFlushTimeout,
    Future<void> Function(HttpClientRequest request)? talkRequestFlusher,
  })  : _microphone = microphone ??
            MicrophoneCaptureService(sampleRate: 16000, channels: 1),
        _clientFactory = clientFactory ?? HttpClient.new,
        talkFlushTimeout = talkFlushTimeout ?? timeout,
        _talkRequestFlusher =
            talkRequestFlusher ?? ((request) => request.flush());

  final MicrophoneCaptureService _microphone;
  final HttpClient Function() _clientFactory;
  final Future<void> Function(HttpClientRequest request) _talkRequestFlusher;
  final Duration timeout;
  final Duration talkFlushTimeout;
  final _states = StreamController<ClientRoomControlSnapshot>.broadcast();
  ClientRoomControlSnapshot _state = const ClientRoomControlSnapshot();
  HttpClient? _talkClient;
  HttpClientRequest? _talkRequest;
  PairingSession? _talkSession;
  String? _talkToken;
  Future<void>? _startInFlight;
  Future<void>? _stopInFlight;
  Future<void>? _flushInFlight;
  Object? _talkPumpError;
  final _pendingTalkChunks = ListQueue<Uint8List>();
  static const _maxPendingTalkChunks = 12;
  int _chunksSinceFlush = 0;
  bool _disposed = false;

  ClientRoomControlSnapshot get currentState => _state;
  Stream<ClientRoomControlSnapshot> get states => _states.stream;

  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    final json = await _requestJson(
      session,
      MiuCamProtocolV2.comfortState,
      method: 'GET',
    );
    final comfort = ComfortAudioState.fromJson(json?['state']);
    _emit(ClientRoomControlSnapshot(
      comfort: comfort,
      talking: _state.talking,
      talkBytesSent: _state.talkBytesSent,
      talkBytesDropped: _state.talkBytesDropped,
    ));
    return comfort;
  }

  Future<ComfortAudioState?> setComfort(
    PairingSession session, {
    required String action,
    String? trackId,
    double? volume,
    bool? loop,
  }) async {
    final json = await _requestJson(
      session,
      MiuCamProtocolV2.comfortCommand,
      method: 'POST',
      body: {
        'action': action,
        if (trackId != null) 'trackId': trackId,
        if (volume != null) 'volume': volume,
        if (loop != null) 'loop': loop,
      },
    );
    final comfort = ComfortAudioState.fromJson(json?['state']);
    _emit(ClientRoomControlSnapshot(
      comfort: comfort ?? _state.comfort,
      talking: _state.talking,
      talkBytesSent: _state.talkBytesSent,
      talkBytesDropped: _state.talkBytesDropped,
    ));
    return comfort;
  }

  Future<void> startTalking(PairingSession session) async {
    if (_disposed || _state.talking || _stopInFlight != null) return;
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final operation = _startTalking(session);
    _startInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_startInFlight, operation)) _startInFlight = null;
    }
  }

  Future<void> _startTalking(PairingSession session) async {
    String token;
    try {
      final start = await _requestJson(
        session,
        MiuCamProtocolV2.talkStart,
        method: 'POST',
        body: const {
          'sampleRate': 16000,
          'channels': 1,
          'codec': 'pcm_s16le',
        },
      );
      final sessionJson = start?['session'];
      final candidate = sessionJson is Map
          ? sessionJson['talkToken']?.toString().trim()
          : null;
      if (candidate == null || candidate.isEmpty) {
        throw StateError('Talk start did not return a talk token.');
      }
      token = candidate;
    } catch (error, stackTrace) {
      await _stopUncertainTalkStart(session);
      Error.throwWithStackTrace(error, stackTrace);
    }
    // Store cleanup ownership as soon as the room has created the session.
    // Every following failure can now issue /talk/stop instead of orphaning it.
    _talkSession = session;
    _talkToken = token;
    _chunksSinceFlush = 0;
    _talkPumpError = null;
    _pendingTalkChunks.clear();

    try {
      if (_disposed) throw StateError('Room controls are disposed.');
      final client = _clientFactory()..connectionTimeout = timeout;
      _talkClient = client;
      final uri = ServerEndpointBuilder(session).http(
        MiuCamProtocolV2.talkAudio,
        query: {'talkToken': token},
      );
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers
        ..contentType = ContentType('audio', 'L16', parameters: {
          'rate': '16000',
          'channels': '1',
        })
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.sessionToken}',
        );
      _talkRequest = request;
      final started = await _microphone.start(
        onChunk: (chunk) {
          _enqueueTalkChunk(chunk.streamPcm16le);
        },
        onError: (error, _) {
          _emit(ClientRoomControlSnapshot(
            comfort: _state.comfort,
            talking: false,
            talkBytesSent: _state.talkBytesSent,
            talkBytesDropped: _state.talkBytesDropped,
            lastError: error,
          ));
          unawaited(stopTalking().catchError((_) {}));
        },
      );
      if (!started) {
        throw StateError('Microphone permission is required for talk.');
      }
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped,
      ));
    } catch (error) {
      await _abortTalk();
      rethrow;
    }
  }

  Future<void> _stopUncertainTalkStart(PairingSession session) async {
    try {
      // The server permits the authenticated owning client to stop without a
      // token, which is exactly what is needed when the start response is lost
      // or malformed after room output already switched to talk mode.
      await _requestJson(
        session,
        MiuCamProtocolV2.talkStop,
        method: 'POST',
        body: const {},
      );
    } catch (_) {}
  }

  Future<void> stopTalking() {
    final inFlight = _stopInFlight;
    if (inFlight != null) return inFlight;

    late final Future<void> operation;
    operation = _stopTalking().whenComplete(() {
      if (identical(_stopInFlight, operation)) _stopInFlight = null;
    });
    _stopInFlight = operation;
    return operation;
  }

  Future<void> _stopTalking() async {
    final starting = _startInFlight;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        return;
      }
    }
    final session = _talkSession;
    final token = _talkToken;
    if (session == null || token == null) return;
    Object? error;

    Future<bool> attempt(Future<void> Function() operation) async {
      try {
        await operation();
        return true;
      } catch (caught) {
        error ??= caught;
        return false;
      }
    }

    try {
      await attempt(_microphone.stop);
      final pumpDrained = await attempt(
        () => _drainTalkPump().timeout(talkFlushTimeout),
      );
      if (!pumpDrained) {
        // A blocked socket must not retain stop ownership. Force-closing the
        // streaming client lets the independent /talk/stop request proceed.
        _talkClient?.close(force: true);
        _talkClient = null;
        _talkRequest = null;
      } else {
        final request = _talkRequest;
        _talkRequest = null;
        if (request != null) {
          await attempt(() async {
            final response = await request.close().timeout(timeout);
            final body =
                await utf8.decoder.bind(response).join().timeout(timeout);
            if (response.statusCode != HttpStatus.ok) {
              throw StateError(
                'Talk audio failed: ${response.statusCode} ${body.trim()}',
              );
            }
          });
        }
      }
      await attempt(() async {
        await _requestJson(
          session,
          MiuCamProtocolV2.talkStop,
          method: 'POST',
          body: {'talkToken': token},
        );
      });
    } finally {
      _talkClient?.close(force: true);
      _talkClient = null;
      _talkRequest = null;
      _talkSession = null;
      _talkToken = null;
      _flushInFlight = null;
      _talkPumpError = null;
      _pendingTalkChunks.clear();
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: false,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped,
        lastError: error,
      ));
    }
    final terminalError = error;
    if (terminalError != null) throw terminalError;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stopTalking();
    } catch (_) {}
    await _microphone.dispose();
    await _states.close();
  }

  Future<Map<String, Object?>?> _requestJson(
    PairingSession session,
    String path, {
    required String method,
    Map<String, Object?>? body,
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final uri = ServerEndpointBuilder(session).http(path);
      final request = method == 'GET'
          ? await client.getUrl(uri).timeout(timeout)
          : await client.postUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('$path failed: ${response.statusCode} $responseBody');
      }
      if (responseBody.trim().isEmpty) return null;
      final decoded = jsonDecode(responseBody);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _abortTalk() async {
    final session = _talkSession;
    final token = _talkToken;
    try {
      await _microphone.stop();
    } catch (_) {}
    try {
      await _talkRequest?.close().timeout(timeout);
    } catch (_) {}
    if (session != null && token != null) {
      try {
        await _requestJson(
          session,
          MiuCamProtocolV2.talkStop,
          method: 'POST',
          body: {'talkToken': token},
        );
      } catch (_) {}
    }
    _talkClient?.close(force: true);
    _talkClient = null;
    _talkRequest = null;
    _talkSession = null;
    _talkToken = null;
    _flushInFlight = null;
    _talkPumpError = null;
    _pendingTalkChunks.clear();
  }

  void _enqueueTalkChunk(Uint8List chunk) {
    if (_talkRequest == null || chunk.isEmpty) return;
    if (_pendingTalkChunks.length >= _maxPendingTalkChunks) {
      final dropped = _pendingTalkChunks.removeFirst();
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped + dropped.length,
      ));
    }
    _pendingTalkChunks.addLast(Uint8List.fromList(chunk));
    _ensureTalkPump();
  }

  void _ensureTalkPump() {
    if (_flushInFlight != null) return;
    if (_pendingTalkChunks.isEmpty || _talkRequest == null) return;
    late final Future<void> pump;
    pump = _pumpTalkChunks().catchError((Object error) {
      _talkPumpError = error;
      _pendingTalkChunks.clear();
    }).whenComplete(() {
      if (identical(_flushInFlight, pump)) _flushInFlight = null;
      if (_talkPumpError == null &&
          _pendingTalkChunks.isNotEmpty &&
          _talkRequest != null) {
        scheduleMicrotask(_ensureTalkPump);
      } else if (_talkPumpError != null && _talkSession != null) {
        scheduleMicrotask(() {
          unawaited(stopTalking().catchError((_) {}));
        });
      }
    });
    _flushInFlight = pump;
  }

  Future<void> _drainTalkPump() async {
    while (_flushInFlight != null || _pendingTalkChunks.isNotEmpty) {
      _ensureTalkPump();
      final current = _flushInFlight;
      if (current == null) break;
      await current;
    }
    final error = _talkPumpError;
    if (error != null) throw error;
  }

  Future<void> _pumpTalkChunks() async {
    final request = _talkRequest;
    if (request == null) return;
    while (_pendingTalkChunks.isNotEmpty && identical(_talkRequest, request)) {
      final chunk = _pendingTalkChunks.removeFirst();
      request.add(chunk);
      _chunksSinceFlush++;
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent + chunk.length,
        talkBytesDropped: _state.talkBytesDropped,
      ));
    }
    if (_chunksSinceFlush > 0 && identical(_talkRequest, request)) {
      _chunksSinceFlush = 0;
      await _talkRequestFlusher(request).timeout(talkFlushTimeout);
    }
  }

  void _emit(ClientRoomControlSnapshot state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
