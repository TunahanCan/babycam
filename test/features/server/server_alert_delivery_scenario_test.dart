import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/alert_event_dto.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/core/security/trusted_client_token.dart';
import 'package:mimicam/features/client/alerts/client_alert_delivery_coordinator.dart';
import 'package:mimicam/features/client/alerts/client_alert_history.dart';
import 'package:mimicam/features/client/alerts/client_alert_listener.dart';
import 'package:mimicam/features/client/alerts/client_notification_service.dart';
import 'package:mimicam/features/client/media/wav_pcm_stream_parser.dart';
import 'package:mimicam/features/server/media/server_media_source.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:mimicam/services/platform/pcm_audio_output.dart';
import 'package:mimicam/services/server/baby_monitor_feature_controller.dart';
import 'package:mimicam/services/server/room_audio_coordinator.dart';
import 'package:mimicam/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analysis/audio/test_audio_generators.dart';

void main() {
  test('oda sesi bastırılır; gerçek ağlama PCM zinciri client bildirimi üretir',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.cry_score_threshold': .50,
      'config.cry_min_duration_ms': 1000,
      'config.notify_cooldown_ms': 60000,
    });
    final preferences = await SharedPreferences.getInstance();
    final tokenService = PairingTokenService();
    final source = _ManualAudioMediaSource();
    final roomAudio = RoomAudioCoordinator(sink: _RecordingPcmAudioSink());
    final features = BabyMonitorFeatureController(roomAudio: roomAudio);
    final localAlerts = <String>[];
    final server = MimiCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: localAlerts.add,
      tokenService: tokenService,
      mediaSource: source,
      featureController: features,
      httpPort: 0,
      startMediaOnSessionStart: false,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final history = ClientAlertHistory(preferences: preferences);
    addTearDown(history.dispose);
    final notifications = _RecordingClientNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    final received = <AlertEventDto>[];
    final firstAlert = Completer<AlertEventDto>();
    final listener = ClientAlertListener(onAlert: (alert) {
      received.add(alert);
      unawaited(delivery.deliver(alert));
      if (!firstAlert.isCompleted) firstAlert.complete(alert);
    });
    addTearDown(listener.stop);
    await listener.start(_session(base.port, trusted));
    await server.startAudioRuntime();

    source.emitAudio(_quietRoomCalibration());
    await _settleEvents();
    expect(received, isEmpty, reason: 'Sessiz oda bildirim üretmemeli.');

    final session = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId, 'video': false, 'audio': true},
      bearerToken: trusted.token,
    );
    expect(session.statusCode, HttpStatus.ok);
    final audioProbe = await _AudioStreamProbe.open(
      base.port,
      session.body['streamToken'] as String,
    );
    addTearDown(audioProbe.close);

    final comfortStarted = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.comfortCommand,
      const {'action': 'play', 'trackId': 'white_noise', 'volume': .3},
      bearerToken: trusted.token,
    );
    expect(comfortStarted.statusCode, HttpStatus.ok);
    expect((comfortStarted.body['state'] as Map)['playing'], isTrue);
    source.emitAudio(_sustainedCry());
    final streamedAudio = await audioProbe.firstPcm.timeout(
      const Duration(seconds: 2),
    );
    expect(streamedAudio, isNotEmpty,
        reason: 'Self-audio bastırması ebeveyn ses akışını kesmemeli.');
    await _settleEvents();
    expect(received, isEmpty, reason: 'Ninni kendi kendini ağlama sanmamalı.');

    final comfortStopped = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.comfortCommand,
      const {'action': 'stop'},
      bearerToken: trusted.token,
    );
    expect((comfortStopped.body['state'] as Map)['playing'], isFalse);
    final talkStarted = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.talkStart,
      const {},
      bearerToken: trusted.token,
    );
    expect(talkStarted.statusCode, HttpStatus.ok);
    final talkToken =
        ((talkStarted.body['session'] as Map)['talkToken'] as String?) ?? '';
    expect(talkToken, isNotEmpty);
    source.emitAudio(_sustainedCry());
    await _settleEvents();
    expect(received, isEmpty, reason: 'Ebeveyn konuşması analiz edilmemeli.');
    final talkStopped = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.talkStop,
      {'talkToken': talkToken},
      bearerToken: trusted.token,
    );
    expect(talkStopped.body['ok'], isTrue);

    source.emitAudio(_sustainedCry());
    final alert = await firstAlert.future.timeout(const Duration(seconds: 3));
    await _settleEvents(const Duration(milliseconds: 120));
    await delivery.drain();
    final status = await _getJson(
      client,
      base.port,
      MimiCamProtocolV2.status,
      trusted.token,
    );

    expect(received, hasLength(1));
    expect(localAlerts, hasLength(1));
    expect(history.alerts, hasLength(1));
    expect(notifications.alerts, hasLength(1));
    expect(notifications.alerts.single.id, alert.id);
    expect(alert.type, 'cryDetected');
    expect(alert.messageKey, 'parentEpisodeCryAlert');
    expect(alert.sourceDeviceId, 'server');
    expect(alert.category, AlertCategory.audio);
    expect(alert.metadata['event'], 'baby_event');
    expect(alert.metadata['durationMs'], inInclusiveRange(1000, 1500));
    expect(alert.message, localAlerts.single);
    expect(
      (status['streamHealth'] as Map)['selfAudioSuppressedChunks'],
      2,
    );
  });

  test('query string tokeni tarayıcı kalıntısı olarak event socket açamaz',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final tokenService = PairingTokenService();
    final server = MimiCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokenService,
      httpPort: 0,
      startMediaOnSessionStart: false,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Tarayıcı',
      deviceId: 'browser',
    );

    await expectLater(
      WebSocket.connect(
        Uri(
          scheme: 'ws',
          host: '127.0.0.1',
          port: base.port,
          path: MimiCamProtocolV2.events,
          queryParameters: {'token': trusted.token},
        ).toString(),
      ),
      throwsA(isA<WebSocketException>()),
    );
  });
}

PairingSession _session(int port, TrustedClientToken trusted) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MimiCamProtocolV2.schemaVersion,
        host: '127.0.0.1',
        port: port,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'unused',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: trusted.token,
      clientId: trusted.clientId,
      trustedClientTokenExpiresAtMs: trusted.expiresAtMs,
    );

Uint8List _quietRoomCalibration() => generateSinePcm16le(
      sampleRate: 16000,
      frequencyHz: 440,
      durationMs: 31000,
      amplitude: 0,
    );

Uint8List _sustainedCry() => generateCryLikePcm16le(
      sampleRate: 16000,
      durationMs: 8000,
      amplitude: .8,
    );

Future<void> _settleEvents([
  Duration duration = const Duration(milliseconds: 30),
]) =>
    Future<void>.delayed(duration);

Future<_JsonResponse> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body, {
  required String bearerToken,
}) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.contentType = ContentType.json;
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer $bearerToken',
  );
  request.write(jsonEncode(body));
  final response = await request.close();
  final decoded = jsonDecode(await utf8.decoder.bind(response).join());
  return _JsonResponse(
    response.statusCode,
    Map<String, Object?>.from(decoded as Map),
  );
}

Future<Map<String, Object?>> _getJson(
  HttpClient client,
  int port,
  String path,
  String bearerToken,
) async {
  final request = await client.getUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'Bearer $bearerToken',
  );
  final response = await request.close();
  expect(response.statusCode, HttpStatus.ok);
  return Map<String, Object?>.from(
    jsonDecode(await utf8.decoder.bind(response).join()) as Map,
  );
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

class _AudioStreamProbe {
  _AudioStreamProbe._(this._client, this._subscription, this.firstPcm);

  final HttpClient _client;
  final StreamSubscription<List<int>> _subscription;
  final Future<Uint8List> firstPcm;

  static Future<_AudioStreamProbe> open(int port, String streamToken) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: MimiCamProtocolV2.audio,
      queryParameters: {'streamToken': streamToken},
    ));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final parser = WavPcmStreamParser();
    final pcm = Completer<Uint8List>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      (chunk) {
        if (pcm.isCompleted) return;
        final parsed = parser.add(Uint8List.fromList(chunk));
        if (parsed.pcm16le.isNotEmpty) pcm.complete(parsed.pcm16le);
      },
      onError: (Object error, StackTrace stack) {
        if (!pcm.isCompleted) pcm.completeError(error, stack);
      },
      onDone: () {
        if (!pcm.isCompleted) {
          pcm.completeError(StateError('Audio stream ended before PCM.'));
        }
      },
      cancelOnError: true,
    );
    return _AudioStreamProbe._(client, subscription, pcm.future);
  }

  Future<void> close() async {
    _client.close(force: true);
    await _subscription.cancel();
  }
}

class _ManualAudioMediaSource extends ServerMediaSource {
  ServerAudioChunkSink? _audioSink;
  bool _active = false;
  int _audioChunks = 0;
  int? _lastAudioChunkAtMs;
  int _lastAudioChunkBytes = 0;

  @override
  bool get isActive => _active;

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
  }

  void emitAudio(Uint8List pcm16le) {
    final sink = _audioSink;
    if (!_active || sink == null) {
      throw StateError('Audio source is not active.');
    }
    _audioChunks++;
    _lastAudioChunkAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastAudioChunkBytes = pcm16le.length;
    sink(pcm16le);
  }

  @override
  Future<void> stop() async {
    _active = false;
    _audioSink = null;
  }

  @override
  void resetDiagnostics() {
    _audioChunks = 0;
    _lastAudioChunkAtMs = null;
    _lastAudioChunkBytes = 0;
  }
}

class _RecordingPcmAudioSink implements PcmAudioSink {
  @override
  Future<void> start({required int sampleRate, required int channels}) async {}

  @override
  Future<Map<String, Object?>> status() async => const {};

  @override
  Future<void> stop() async {}

  @override
  Future<bool> write(Uint8List pcm16le) async => pcm16le.isNotEmpty;
}

class _RecordingClientNotificationService extends ClientNotificationService {
  final alerts = <AlertEventDto>[];

  @override
  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) async {
    alerts.add(alert);
    return NotificationDeliveryReceipt(
      notificationId: NotificationService.notificationIdFor(alert.id),
      posted: true,
      verifiedActive: true,
    );
  }
}
