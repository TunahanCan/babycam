import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/webrtc_signaling.dart';
import 'package:miucam/features/server/media/webrtc/webrtc_server_gateway.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('WebRTC offer, ICE and close routes use the active stream session',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway();
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final started = await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
      },
      bearer: trusted.token,
    );
    final streamToken = started['streamToken']!.toString();

    final answer = await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcOffer,
      {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {'streamToken': streamToken},
    );
    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcIce,
      {
        'candidate': {
          'candidate': 'candidate:1 1 UDP 1 192.168.1.2 5000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      },
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );
    final ice = await _get(
      client,
      base.port,
      MiuCamProtocolV2.webRtcIce,
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );
    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );

    expect(started['mediaTransport'], 'webrtc');
    expect(answer['peerId'], 'peer-1');
    expect((answer['answer'] as Map)['type'], 'answer');
    expect((ice['iceCandidates'] as List), hasLength(1));
    expect(gateway.remoteCandidates, hasLength(1));
    expect(gateway.closedPeers, ['peer-1']);
  });

  test('healthy WebRTC peer remains authoritative after stream token expiry',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026);
    final tokens = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(milliseconds: 10),
    );
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: _FakeWebRtcServerGateway(),
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final started = await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
      },
      bearer: trusted.token,
    );
    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcOffer,
      const {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {'streamToken': started['streamToken']!.toString()},
    );

    now = now.add(const Duration(seconds: 2));
    final status = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(status['activeStreamClients'], 1);
  });

  test('late lifecycle event from replaced peer keeps current session active',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway(
      peerIds: const ['peer-old', 'peer-current'],
    );
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final oldSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-old',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: oldSession['streamToken']!.toString(),
    );
    final currentSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentSession['streamToken']!.toString(),
    );

    gateway.emitPeerClosed('peer-old');
    // A mismatched attempt stop is serialized behind the lifecycle event and
    // acts as a deterministic barrier without stopping the current session.
    await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      const {
        MiuCamProtocolV2.streamAttemptId: 'attempt-old',
      },
      bearer: trusted.token,
    );
    final status = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(status['activeStreamClients'], 1);
  });

  test('explicit close for replaced peer keeps current session active',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway(
      peerIds: const ['peer-old', 'peer-current'],
    );
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final oldSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-old',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: oldSession['streamToken']!.toString(),
    );
    final currentSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentSession['streamToken']!.toString(),
    );

    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': currentSession['streamToken']!.toString(),
        'peerId': 'peer-old',
      },
    );
    final afterOldClose = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );
    expect(afterOldClose['activeStreamClients'], 1);

    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': currentSession['streamToken']!.toString(),
        'peerId': 'peer-current',
      },
    );
    final afterCurrentClose = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(afterCurrentClose['activeStreamClients'], 0);
    expect(gateway.closedPeers, ['peer-old', 'peer-current']);
  });

  test('repeated offers transfer one exact media lease between peers',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway(
      peerIds: const ['peer-1', 'peer-2', 'peer-3', 'peer-4'],
    );
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      maxMediaConnectionsPerClient: 1,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final session = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-reconnect',
    );
    final streamToken = session['streamToken']!.toString();
    for (final expectedPeer in const [
      'peer-1',
      'peer-2',
      'peer-3',
      'peer-4',
    ]) {
      final answer = await _offerWebRtc(
        client,
        base.port,
        bearer: trusted.token,
        streamToken: streamToken,
      );
      expect(answer['peerId'], expectedPeer);
      expect(gateway.activePeerCount, 1);
    }

    expect(gateway.closedPeers, ['peer-1', 'peer-2', 'peer-3']);
    await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': streamToken,
        'peerId': 'peer-4',
      },
    );
    expect(gateway.activePeerCount, 0);
    expect(gateway.closedPeers, ['peer-1', 'peer-2', 'peer-3', 'peer-4']);
  });

  test('WebRTC to legacy waits for exact peer close and external release',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _ControllableWebRtcServerGateway(
      hangingClosePeerId: 'peer-old',
    );
    final lifecycle = <String>[];
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      webRtcCleanupTimeout: const Duration(milliseconds: 40),
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {
        lifecycle.add('session:$mediaTransport');
      },
      onWebRtcCaptureStarting: (_) => lifecycle.add('external:start'),
      onWebRtcCaptureEnded: (_) => lifecycle.add('external:end'),
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    addTearDown(gateway.releaseHangingClose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final webRtcSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-webrtc',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: webRtcSession['streamToken']!.toString(),
    );

    final blockedReplacement = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': true,
        'mediaTransport': 'mjpeg_wav',
        MiuCamProtocolV2.streamAttemptId: 'attempt-legacy-blocked',
      },
      bearer: trusted.token,
    );
    final whileUnconfirmed = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(blockedReplacement, HttpStatus.internalServerError);
    expect(whileUnconfirmed['activeStreamClients'], 1);
    expect(lifecycle, ['session:webrtc', 'external:start']);

    gateway.releaseHangingClose();
    await gateway.oldPeerCloseSettled.future.timeout(
      const Duration(seconds: 1),
    );
    final legacySession = await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': true,
        'mediaTransport': 'mjpeg_wav',
        MiuCamProtocolV2.streamAttemptId: 'attempt-legacy-current',
      },
      bearer: trusted.token,
    );

    expect(legacySession['mediaTransport'], 'mjpeg_wav');
    expect(
      lifecycle,
      [
        'session:webrtc',
        'external:start',
        'external:end',
        'session:mjpeg_wav',
      ],
    );
    expect(gateway.activePeerIds, isEmpty);
  });

  test('replaced stream token cannot reach current media or WebRTC owner',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway(
      peerIds: const ['peer-current'],
    );
    var captureStarts = 0;
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      onWebRtcCaptureStarting: (_) => captureStarts++,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final replaced = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-replaced',
    );
    final current = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    final replacedToken = replaced['streamToken']!.toString();
    final currentToken = current['streamToken']!.toString();

    final staleOfferStatus = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.webRtcOffer,
      const {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {'streamToken': replacedToken},
    );
    expect(staleOfferStatus, HttpStatus.unauthorized);
    expect(captureStarts, 0);
    expect(gateway.activePeerCount, 0);

    final answer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentToken,
    );
    expect(answer['peerId'], 'peer-current');

    final staleIceStatus = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.webRtcIce,
      const {
        'candidate': {
          'candidate': 'candidate:old',
        },
      },
      bearer: trusted.token,
      query: {
        'streamToken': replacedToken,
        'peerId': 'peer-current',
      },
    );
    final staleCloseStatus = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': replacedToken,
        'peerId': 'peer-current',
      },
    );
    final staleVideoStatus = await _getStatus(
      client,
      base.port,
      MiuCamProtocolV2.video,
      query: {'streamToken': replacedToken},
    );
    final staleAudioStatus = await _getStatus(
      client,
      base.port,
      MiuCamProtocolV2.audio,
      query: {'streamToken': replacedToken},
    );
    final status = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(staleIceStatus, HttpStatus.unauthorized);
    expect(staleCloseStatus, HttpStatus.unauthorized);
    expect(staleVideoStatus, HttpStatus.unauthorized);
    expect(staleAudioStatus, HttpStatus.unauthorized);
    expect(captureStarts, 1);
    expect(gateway.remoteCandidates, isEmpty);
    expect(gateway.closedPeers, isEmpty);
    expect(gateway.activePeerCount, 1);
    expect(status['activeStreamClients'], 1);
  });

  test('failed replacement restores previous stream token ownership', () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway(
      peerIds: const ['peer-restored'],
    );
    var captureStarts = 0;
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {
        if (audio) throw StateError('replacement failed');
      },
      onWebRtcCaptureStarting: (_) => captureStarts++,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final original = await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': false,
        'mediaTransport': 'webrtc',
        MiuCamProtocolV2.streamAttemptId: 'attempt-original',
      },
      bearer: trusted.token,
    );
    final failedReplacementStatus = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
        MiuCamProtocolV2.streamAttemptId: 'attempt-failed',
      },
      bearer: trusted.token,
    );
    final restoredAnswer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: original['streamToken']!.toString(),
    );

    expect(failedReplacementStatus, HttpStatus.internalServerError);
    expect(restoredAnswer['peerId'], 'peer-restored');
    expect(captureStarts, 1);
    expect(gateway.activePeerCount, 1);
  });

  test('hanging offer times out without blocking stop or a newer peer',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _ControllableWebRtcServerGateway(hangFirstOffer: true);
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      webRtcNegotiationTimeout: const Duration(milliseconds: 40),
      webRtcCleanupTimeout: const Duration(milliseconds: 40),
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final oldSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-hanging',
    );
    final hangingOffer = _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.webRtcOffer,
      const {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {
        'streamToken': oldSession['streamToken']!.toString(),
      },
    );
    await gateway.firstOfferEntered.future.timeout(const Duration(seconds: 1));
    final liveStatus = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );
    final queuedStop = _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      const {
        MiuCamProtocolV2.streamAttemptId: 'attempt-hanging',
      },
      bearer: trusted.token,
    );

    expect(liveStatus['activeStreamClients'], 1);
    expect(
      await hangingOffer.timeout(const Duration(seconds: 1)),
      HttpStatus.gatewayTimeout,
    );
    final stopped = await queuedStop.timeout(const Duration(seconds: 1));
    expect(stopped['activeStreamClients'], 0);
    expect(gateway.cancelPendingOfferCalls, greaterThanOrEqualTo(1));

    final currentSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    final currentAnswer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentSession['streamToken']!.toString(),
    );
    expect(currentAnswer['peerId'], 'peer-current');

    gateway.completeFirstOffer('peer-late');
    await gateway.latePeerClosed.future.timeout(const Duration(seconds: 1));
    final finalStatus = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(finalStatus['activeStreamClients'], 1);
    expect(gateway.activePeerIds, {'peer-current'});
    expect(gateway.closedPeers, contains('peer-late'));
    expect(gateway.closedPeers, isNot(contains('peer-current')));
  });

  test('hanging peer and runtime cleanup cannot block close or newer peer',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _ControllableWebRtcServerGateway(
      hangingClosePeerId: 'peer-old',
    );
    final oldRuntimeStop = Completer<void>();
    var runtimeStopCalls = 0;
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      webRtcNegotiationTimeout: const Duration(milliseconds: 200),
      webRtcCleanupTimeout: const Duration(milliseconds: 40),
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {},
      onStreamSessionStopped: (_) {
        runtimeStopCalls++;
        if (runtimeStopCalls == 1) return oldRuntimeStop.future;
      },
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    addTearDown(() {
      if (!oldRuntimeStop.isCompleted) oldRuntimeStop.complete();
      gateway.releaseHangingClose();
    });
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final oldSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-old',
    );
    final oldAnswer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: oldSession['streamToken']!.toString(),
    );
    expect(oldAnswer['peerId'], 'peer-old');

    final closeResponse = await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': oldSession['streamToken']!.toString(),
        'peerId': 'peer-old',
      },
    ).timeout(const Duration(seconds: 1));
    final afterClose = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(closeResponse['ok'], isFalse);
    expect(afterClose['activeStreamClients'], 1);
    expect(runtimeStopCalls, 0);

    gateway.releaseHangingClose();
    oldRuntimeStop.complete();
    await gateway.oldPeerCloseSettled.future.timeout(
      const Duration(seconds: 1),
    );
    final confirmedClose = await _post(
      client,
      base.port,
      MiuCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {
        'streamToken': oldSession['streamToken']!.toString(),
        'peerId': 'peer-old',
      },
    );
    expect(confirmedClose['ok'], isTrue);
    expect(runtimeStopCalls, 1);

    final currentSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    final currentAnswer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentSession['streamToken']!.toString(),
    );
    expect(currentAnswer['peerId'], 'peer-current');

    final finalStatus = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(finalStatus['activeStreamClients'], 1);
    expect(gateway.activePeerIds, {'peer-current'});
    expect(gateway.closedPeers, contains('peer-old'));
    expect(gateway.closedPeers, isNot(contains('peer-current')));
  });

  test('unconfirmed session teardown retains exact peer until a retry',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _ControllableWebRtcServerGateway(
      hangingClosePeerId: 'peer-old',
    );
    final server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      webRtcNegotiationTimeout: const Duration(milliseconds: 200),
      webRtcCleanupTimeout: const Duration(milliseconds: 40),
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    addTearDown(gateway.releaseHangingClose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final oldSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-old',
    );
    await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: oldSession['streamToken']!.toString(),
    );

    final stopStatus = await _postStatus(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      const {
        MiuCamProtocolV2.streamAttemptId: 'attempt-old',
      },
      bearer: trusted.token,
    ).timeout(const Duration(seconds: 1));
    final afterStop = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(stopStatus, HttpStatus.internalServerError);
    expect(afterStop['activeStreamClients'], 1);

    gateway.releaseHangingClose();
    await gateway.oldPeerCloseSettled.future.timeout(
      const Duration(seconds: 1),
    );
    final confirmedStop = await _post(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      const {
        MiuCamProtocolV2.streamAttemptId: 'attempt-old',
      },
      bearer: trusted.token,
    );
    expect(confirmedStop['activeStreamClients'], 0);

    final currentSession = await _startWebRtcSession(
      client,
      base.port,
      bearer: trusted.token,
      attemptId: 'attempt-current',
    );
    final currentAnswer = await _offerWebRtc(
      client,
      base.port,
      bearer: trusted.token,
      streamToken: currentSession['streamToken']!.toString(),
    );
    expect(currentAnswer['peerId'], 'peer-current');

    final finalStatus = await _get(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(finalStatus['activeStreamClients'], 1);
    expect(gateway.activePeerIds, {'peer-current'});
    expect(gateway.closedPeers, contains('peer-old'));
    expect(gateway.closedPeers, isNot(contains('peer-current')));
  });
}

class _FakeWebRtcServerGateway
    implements WebRtcServerGateway, WebRtcPeerLifecycleSource {
  _FakeWebRtcServerGateway({
    this.peerIds = const ['peer-1'],
  });

  final List<String> peerIds;
  final _peerEvents = StreamController<WebRtcPeerLifecycleEvent>.broadcast(
    sync: true,
  );
  int _nextPeerIndex = 0;
  final remoteCandidates = <WebRtcIceCandidateSignal>[];
  final closedPeers = <String>[];
  final _peerClients = <String, String>{};
  final _activePeerIds = <String>{};
  final localCandidates = <WebRtcIceCandidateSignal>[
    const WebRtcIceCandidateSignal(
      candidate: 'candidate:2 1 UDP 1 192.168.1.3 5001 typ host',
    ),
  ];

  @override
  int get activePeerCount => _activePeerIds.length;

  @override
  bool get isAvailable => true;

  @override
  Stream<WebRtcPeerLifecycleEvent> get peerEvents => _peerEvents.stream;

  @override
  Future<void> addRemoteCandidate({
    required String clientId,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  }) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  }) async {
    final peerId = peerIds[_nextPeerIndex++];
    _peerClients[peerId] = clientId;
    _activePeerIds.add(peerId);
    return WebRtcOfferResponse(
      peerId: peerId,
      answer: const WebRtcSignalDescription(
        type: 'answer',
        sdp: 'v=0\r\n',
      ),
    );
  }

  @override
  Future<void> closeClient(String clientId) async {
    final peerIds = _peerClients.entries
        .where(
          (entry) =>
              entry.value == clientId && _activePeerIds.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final peerId in peerIds) {
      await closePeer(clientId: clientId, peerId: peerId);
    }
  }

  @override
  Future<void> closePeer({
    required String clientId,
    required String peerId,
  }) async {
    if (!_activePeerIds.contains(peerId) || _peerClients[peerId] != clientId) {
      throw const WebRtcPeerNotFoundException();
    }
    _activePeerIds.remove(peerId);
    closedPeers.add(peerId);
  }

  void emitPeerClosed(String peerId) {
    _activePeerIds.remove(peerId);
    _peerEvents.add(WebRtcPeerLifecycleEvent(
      clientId: _peerClients[peerId]!,
      peerId: peerId,
      reason: WebRtcPeerCloseReason.connectionClosed,
    ));
  }

  @override
  List<WebRtcIceCandidateSignal> drainLocalCandidates({
    required String clientId,
    required String peerId,
  }) {
    final result = List<WebRtcIceCandidateSignal>.of(localCandidates);
    localCandidates.clear();
    return result;
  }

  @override
  Future<void> dispose() async {
    _activePeerIds.clear();
    _peerClients.clear();
    await _peerEvents.close();
  }

  @override
  Future<bool> initialize() async => true;
}

class _ControllableWebRtcServerGateway
    implements WebRtcServerGateway, WebRtcPendingOfferController {
  _ControllableWebRtcServerGateway({
    this.hangFirstOffer = false,
    this.hangingClosePeerId,
  });

  final bool hangFirstOffer;
  final String? hangingClosePeerId;
  final firstOfferEntered = Completer<void>();
  final latePeerClosed = Completer<void>();
  final oldPeerCloseSettled = Completer<void>();
  final _firstOffer = Completer<WebRtcOfferResponse>();
  final _hangingCloseRelease = Completer<void>();
  final activePeerIds = <String>{};
  final closedPeers = <String>[];
  final _peerClients = <String, String>{};
  var _offerCalls = 0;
  var cancelPendingOfferCalls = 0;

  @override
  int get activePeerCount => activePeerIds.length;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  }) async {
    _offerCalls++;
    late final WebRtcOfferResponse answer;
    if (hangFirstOffer && _offerCalls == 1) {
      if (!firstOfferEntered.isCompleted) firstOfferEntered.complete();
      answer = await _firstOffer.future;
    } else {
      final peerId = _offerCalls == 1 ? 'peer-old' : 'peer-current';
      answer = WebRtcOfferResponse(
        peerId: peerId,
        answer: const WebRtcSignalDescription(
          type: 'answer',
          sdp: 'v=0\r\n',
        ),
      );
    }
    activePeerIds.add(answer.peerId);
    _peerClients[answer.peerId] = clientId;
    return answer;
  }

  void completeFirstOffer(String peerId) {
    if (_firstOffer.isCompleted) return;
    _firstOffer.complete(WebRtcOfferResponse(
      peerId: peerId,
      answer: const WebRtcSignalDescription(
        type: 'answer',
        sdp: 'v=0\r\n',
      ),
    ));
  }

  @override
  Future<void> cancelPendingOffer(String clientId) async {
    cancelPendingOfferCalls++;
  }

  @override
  Future<void> addRemoteCandidate({
    required String clientId,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  }) async {
    if (!activePeerIds.contains(peerId)) {
      throw const WebRtcPeerNotFoundException();
    }
  }

  @override
  List<WebRtcIceCandidateSignal> drainLocalCandidates({
    required String clientId,
    required String peerId,
  }) =>
      const [];

  @override
  Future<void> closePeer({
    required String clientId,
    required String peerId,
  }) async {
    if (!activePeerIds.contains(peerId) || _peerClients[peerId] != clientId) {
      throw const WebRtcPeerNotFoundException();
    }
    if (peerId == hangingClosePeerId && !_hangingCloseRelease.isCompleted) {
      await _hangingCloseRelease.future;
    }
    activePeerIds.remove(peerId);
    _peerClients.remove(peerId);
    closedPeers.add(peerId);
    if (peerId == 'peer-late' && !latePeerClosed.isCompleted) {
      latePeerClosed.complete();
    }
    if (peerId == 'peer-old' && !oldPeerCloseSettled.isCompleted) {
      oldPeerCloseSettled.complete();
    }
  }

  @override
  Future<void> closeClient(String clientId) async {
    final peerIds = _peerClients.entries
        .where((entry) => entry.value == clientId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final peerId in peerIds) {
      await closePeer(clientId: clientId, peerId: peerId);
    }
  }

  void releaseHangingClose() {
    if (!_hangingCloseRelease.isCompleted) {
      _hangingCloseRelease.complete();
    }
  }

  @override
  Future<void> dispose() async {
    releaseHangingClose();
    activePeerIds.clear();
    _peerClients.clear();
  }
}

Future<Map<String, Object?>> _startWebRtcSession(
  HttpClient client,
  int port, {
  required String bearer,
  required String attemptId,
}) =>
    _post(
      client,
      port,
      MiuCamProtocolV2.sessionStart,
      {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
        MiuCamProtocolV2.streamAttemptId: attemptId,
      },
      bearer: bearer,
    );

Future<Map<String, Object?>> _offerWebRtc(
  HttpClient client,
  int port, {
  required String bearer,
  required String streamToken,
}) =>
    _post(
      client,
      port,
      MiuCamProtocolV2.webRtcOffer,
      const {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: bearer,
      query: {'streamToken': streamToken},
    );

Future<Map<String, Object?>> _post(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body, {
  required String bearer,
  Map<String, String>? query,
}) async {
  final request = await client.postUrl(_uri(port, path, query));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  request.write(jsonEncode(_withV2AttemptFixture(path, body)));
  return _read(await request.close());
}

Future<int> _postStatus(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body, {
  required String bearer,
  Map<String, String>? query,
}) async {
  final request = await client.postUrl(_uri(port, path, query));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  request.write(jsonEncode(_withV2AttemptFixture(path, body)));
  final response = await request.close();
  await utf8.decoder.bind(response).join();
  return response.statusCode;
}

Map<String, Object?> _withV2AttemptFixture(
  String path,
  Map<String, Object?> body,
) {
  final fixture = Map<String, Object?>.of(body);
  if (path == MiuCamProtocolV2.sessionStart ||
      path == MiuCamProtocolV2.sessionStop) {
    fixture.putIfAbsent(
      MiuCamProtocolV2.streamAttemptId,
      () => 'webrtc-fixture-attempt',
    );
  }
  return fixture;
}

Future<Map<String, Object?>> _get(
  HttpClient client,
  int port,
  String path, {
  required String bearer,
  Map<String, String>? query,
}) async {
  final request = await client.getUrl(_uri(port, path, query));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  return _read(await request.close());
}

Future<int> _getStatus(
  HttpClient client,
  int port,
  String path, {
  Map<String, String>? query,
}) async {
  final request = await client.getUrl(_uri(port, path, query));
  final response = await request.close();
  await utf8.decoder.bind(response).join();
  return response.statusCode;
}

Future<Map<String, Object?>> _read(HttpClientResponse response) async {
  final body = await utf8.decoder.bind(response).join();
  expect(response.statusCode, HttpStatus.ok, reason: body);
  return Map<String, Object?>.from(jsonDecode(body) as Map);
}

Uri _uri(int port, String path, Map<String, String>? query) => Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: query,
    );
