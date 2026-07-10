import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/device_feature_models.dart';
import '../../../core/protocol/mimicam_protocol.dart';
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
  })  : _microphone = microphone ??
            MicrophoneCaptureService(sampleRate: 16000, channels: 1),
        _clientFactory = clientFactory ?? HttpClient.new;

  final MicrophoneCaptureService _microphone;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  final _states = StreamController<ClientRoomControlSnapshot>.broadcast();
  ClientRoomControlSnapshot _state = const ClientRoomControlSnapshot();
  HttpClient? _talkClient;
  HttpClientRequest? _talkRequest;
  PairingSession? _talkSession;
  String? _talkToken;
  Future<void>? _startInFlight;
  Future<void>? _flushInFlight;
  int _chunksSinceFlush = 0;
  bool _disposed = false;

  ClientRoomControlSnapshot get currentState => _state;
  Stream<ClientRoomControlSnapshot> get states => _states.stream;

  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    final json = await _requestJson(
      session,
      MimiCamProtocolV2.comfortState,
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
      MimiCamProtocolV2.comfortCommand,
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
    if (_disposed || _state.talking) return;
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
    final start = await _requestJson(
      session,
      MimiCamProtocolV2.talkStart,
      method: 'POST',
      body: const {
        'sampleRate': 16000,
        'channels': 1,
        'codec': 'pcm_s16le',
      },
    );
    final sessionJson = start?['session'];
    final token =
        sessionJson is Map ? sessionJson['talkToken']?.toString().trim() : null;
    if (token == null || token.isEmpty) {
      throw StateError('Talk start did not return a talk token.');
    }
    if (_disposed) throw StateError('Room controls are disposed.');

    final client = _clientFactory()..connectionTimeout = timeout;
    final uri = ServerEndpointBuilder(session).http(
      MimiCamProtocolV2.talkAudio,
      query: {'talkToken': token},
    );
    final request = await client.postUrl(uri).timeout(timeout);
    request.headers
      ..contentType = ContentType('audio', 'L16', parameters: {
        'rate': '16000',
        'channels': '1',
      })
      ..set(HttpHeaders.acceptHeader, 'application/json');
    _talkClient = client;
    _talkRequest = request;
    _talkSession = session;
    _talkToken = token;
    _chunksSinceFlush = 0;

    try {
      final started = await _microphone.start(
        onChunk: (chunk) {
          final activeRequest = _talkRequest;
          if (activeRequest == null) return;
          if (_flushInFlight != null) {
            _emit(ClientRoomControlSnapshot(
              comfort: _state.comfort,
              talking: true,
              talkBytesSent: _state.talkBytesSent,
              talkBytesDropped:
                  _state.talkBytesDropped + chunk.streamPcm16le.length,
            ));
            return;
          }
          activeRequest.add(chunk.streamPcm16le);
          _chunksSinceFlush++;
          _emit(ClientRoomControlSnapshot(
            comfort: _state.comfort,
            talking: true,
            talkBytesSent: _state.talkBytesSent + chunk.streamPcm16le.length,
            talkBytesDropped: _state.talkBytesDropped,
          ));
          if (_chunksSinceFlush >= 5 && _flushInFlight == null) {
            _chunksSinceFlush = 0;
            late final Future<void> flush;
            flush = activeRequest.flush().whenComplete(() {
              if (identical(_flushInFlight, flush)) _flushInFlight = null;
            });
            _flushInFlight = flush;
          }
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

  Future<void> stopTalking() async {
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
    try {
      await _microphone.stop();
      await _flushInFlight;
      final request = _talkRequest;
      _talkRequest = null;
      if (request != null) {
        final response = await request.close().timeout(timeout);
        final body = await utf8.decoder.bind(response).join().timeout(timeout);
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'Talk audio failed: ${response.statusCode} ${body.trim()}',
          );
        }
      }
      await _requestJson(
        session,
        MimiCamProtocolV2.talkStop,
        method: 'POST',
        body: {'talkToken': token},
      );
    } catch (caught) {
      error = caught;
    } finally {
      _talkClient?.close(force: true);
      _talkClient = null;
      _talkRequest = null;
      _talkSession = null;
      _talkToken = null;
      _flushInFlight = null;
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: false,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped,
        lastError: error,
      ));
    }
    if (error != null) throw error;
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
          MimiCamProtocolV2.talkStop,
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
  }

  void _emit(ClientRoomControlSnapshot state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
