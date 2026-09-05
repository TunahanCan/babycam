part of '../miucam_server.dart';

/// Domain endpoint controller kept separate from the socket dispatcher.
extension _MiuCamHttpEndpointController on MiuCamServer {
  Future<void> _handlePublicStatus(HttpRequest request) async {
    if (!_pairingModeActive) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final pairingNonce = tokenService.createPairingNonce();
    final descriptorHost = _hostFromHeader(request.headers.host) ??
        _httpServer?.address.address ??
        InternetAddress.loopbackIPv4.address;
    final deviceId = await _serverDeviceIdentityResolver.resolve();
    await _writeJson(request.response, {
      'service': 'miucam',
      'pairing': true,
      'serverDeviceId': deviceId,
      'serverName': 'Bebek Odası',
      'pairingNonce': pairingNonce,
      'transport': transportConfig.payloadTransport,
      'capabilities': _mediaCapabilities(),
      'discovery': {
        'dnsSd': _serviceAdvertiser?.isAdvertising == true,
        'serviceType': MiuCamDiscoveryConfig.serviceType,
        'host': descriptorHost,
        'port': _httpServer?.port ?? httpPort,
      },
    });
  }

  Future<void> _handlePrivateStatus(HttpRequest request) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final battery = await _refreshServerBattery();
    await _writeJson(request.response, {
      'videoClients': _videoStreamService.clientCount,
      'audioClients': _audioStreamService.clientCount,
      'webSocketClients': _eventSockets.clientCount,
      'mediaConnections': _activeClientRegistry.mediaConnectionCount,
      'eventSocketConnections': _activeClientRegistry.eventSocketCount,
      'activeStreamClients': _activeClientRegistry.activeClientCount,
      'qualityReportClients': _activeClientRegistry.qualityReportCount,
      'hasFrame': _latestJpeg != null,
      'deviceTier': _deviceTier.name,
      'mediaProfile': _effectiveMediaProfile().toJson(),
      'jpegBytesPerSecond': _jpegByteBudgetController.lastActualBytesPerSecond(
        _activeMediaProfile,
      ),
      'battery': battery.toJson(),
      'clientBatteries': {
        for (final entry in _clientBatterySnapshots.entries)
          entry.key: entry.value.toJson(),
      },
      'transport': _transportStatus(),
      'streamHealth': _streamHealthStatus(nowMs),
      'comfort': _features.comfortAudio.state.toJson(),
      'audioDetection': _audioDetectionStatus(),
      'nightLight': _features.nightLight.state.toJson(),
      'talk': _talkStatus(),
      if (_broadcastAccess != null)
        'broadcastAccess': (await _broadcastAccess.snapshot()).toJson(),
      if (_analysisCoordinator != null) ..._analysisCoordinator!.diagnostics(),
    });
  }

  Future<void> _handleComfortState(HttpRequest request) async {
    await _writeJson(request.response, {
      'ok': true,
      'state': _features.comfortAudio.state.toJson(),
      'audioDetection': _audioDetectionStatus(),
      'tracks': _features.comfortAudio.trackCatalog,
    });
  }

  Future<void> _handleComfortCommand(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (error) {
      await _rejectInvalidJsonBody(request, error);
      return;
    }
    final state = await _features.applyComfortCommand(body);
    _updateResourceWatchdog();
    await _writeJson(request.response, {
      'ok': state.lastError == null,
      'state': state.toJson(),
      'audioDetection': _audioDetectionStatus(),
      'tracks': _features.comfortAudio.trackCatalog,
    });
  }

  Future<void> _handleNightLightState(HttpRequest request) async {
    await _writeJson(request.response, {
      'ok': true,
      'state': _features.nightLight.state.toJson(),
    });
  }

  Future<void> _handleNightLightCommand(HttpRequest request) async {
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (error) {
      await _rejectInvalidJsonBody(request, error);
      return;
    }
    final state = await _features.nightLight.applyCommand(
      body,
      torchSetter: _setTorchEnabled,
    );
    await _writeJson(request.response, {
      'ok': state.lastError == null ||
          state.lastError == 'TORCH_UNAVAILABLE_SCREEN_GLOW_FALLBACK',
      'state': state.toJson(),
    });
  }

  Future<void> _handleTalkStart(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    try {
      Map<Object?, Object?>? body;
      try {
        body = await _readJsonObjectBody(request);
      } catch (error) {
        await _rejectInvalidJsonBody(request, error);
        return;
      }
      late final String attemptId;
      try {
        attemptId = _talkAttemptIdForRequest(body);
      } on FormatException {
        await _rejectInvalidAttemptId(
          request,
          code: protocol_v2.MiuCamProtocolV2.invalidTalkAttemptIdCode,
          field: protocol_v2.MiuCamProtocolV2.talkAttemptId,
        );
        return;
      }
      final session = await _features.startTalk(
        clientId: clientId,
        attemptId: attemptId,
        sampleRate: (body?['sampleRate'] as num?)?.toInt() ??
            MiuCamServer._audioSampleRate,
        channels:
            (body?['channels'] as num?)?.toInt() ?? MiuCamServer._audioChannels,
      );
      _updateResourceWatchdog();
      await _writeJson(request.response, {
        'ok': true,
        'session': session.toJson(includeToken: true),
      });
    } on TalkSessionBusyException catch (error) {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'TALK_SESSION_BUSY',
        'activeSession': error.activeSession.toJson(),
      });
    } on TalkSessionCancelledException {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'TALK_START_CANCELLED',
        'message': 'The talk session start was already cancelled.',
      });
    }
  }

  Future<void> _handleTalkStop(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    Map<Object?, Object?>? body;
    try {
      body = await _readJsonObjectBody(request);
    } catch (error) {
      await _rejectInvalidJsonBody(request, error);
      return;
    }
    late final String attemptId;
    try {
      attemptId = _talkAttemptIdForRequest(body);
    } on FormatException {
      await _rejectInvalidAttemptId(
        request,
        code: protocol_v2.MiuCamProtocolV2.invalidTalkAttemptIdCode,
        field: protocol_v2.MiuCamProtocolV2.talkAttemptId,
      );
      return;
    }
    final stopped = await _features.stopTalk(
      clientId: clientId,
      token: body?['talkToken']?.toString(),
      attemptId: attemptId,
    );
    _updateResourceWatchdog();
    await _writeJson(request.response, {
      'ok': stopped,
      'talk': _talkStatus(),
    });
  }

  Future<void> _handleTalkAudio(HttpRequest request) async {
    final token = _talkTokenFromRequest(request);
    if (token == null || !_features.isTalkTokenActive(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    var totalBytes = 0;
    TalkSession? session;
    var playedChunks = 0;
    var rejected = false;
    final frameBytes = max(
      2,
      (MiuCamServer._audioSampleRate *
              MiuCamServer._audioChannels *
              2 *
              20 /
              1000)
          .round(),
    );
    final assembler = Pcm16FrameAssembler(frameBytes: frameBytes);

    Future<bool> play(Uint8List bytes) async {
      final result = await _features.acceptTalkAudio(token, bytes);
      session = result.session;
      rejected = session == null;
      if (result.played) playedChunks++;
      return session != null;
    }

    await for (final chunk in request) {
      if (chunk.isEmpty) continue;
      totalBytes += chunk.length;
      for (final frame in assembler.add(chunk)) {
        if (!await play(frame)) break;
      }
      if (rejected) break;
    }
    if (!rejected) {
      final tail = assembler.flushAlignedTail();
      if (tail != null && tail.isNotEmpty) await play(tail);
    }
    if (assembler.hasPartialSample) {
      onLog('Talk upload ended with one incomplete PCM16 byte.');
    }
    if (session == null && totalBytes > 0) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    session ??= _features.talkSessions.activeSession;
    await _writeJson(request.response, {
      'ok': session != null,
      'audioBytesReceived': totalBytes,
      'audioChunksPlayed': playedChunks,
      'talk': session?.toJson(),
    });
  }

  Future<void> _handleTalkVideo(HttpRequest request) async {
    await _handleTalkBytes(
      request,
      recorder: _features.acceptTalkVideo,
      mediaKey: 'videoBytesReceived',
    );
  }

  Future<void> _handleTalkBytes(
    HttpRequest request, {
    required TalkSession? Function(String token, Uint8List bytes) recorder,
    required String mediaKey,
  }) async {
    final token = _talkTokenFromRequest(request);
    if (token == null || !_features.isTalkTokenActive(token)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    var totalBytes = 0;
    TalkSession? session;
    await for (final chunk in request) {
      if (chunk.isEmpty) continue;
      final bytes = Uint8List.fromList(chunk);
      totalBytes += bytes.length;
      session = recorder(token, bytes);
      if (session == null) break;
    }
    if (session == null && totalBytes > 0) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    session ??= _features.talkSessions.activeSession;
    await _writeJson(request.response, {
      'ok': session != null,
      mediaKey: totalBytes,
      'talk': session?.toJson(),
    });
  }

  Future<void> _handleVideoRoute(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) return;
    final connectionLease =
        await _reserveMediaConnection(request.response, clientId);
    if (connectionLease == null) return;
    try {
      await startVideoRuntime();
      await _handleMjpeg(
        request.response,
        clientId,
        onDetached: connectionLease.release,
      );
    } catch (_) {
      connectionLease.release();
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleAudioRoute(
    HttpRequest request,
    String? clientId,
  ) async {
    if (clientId == null) return;
    final connectionLease =
        await _reserveMediaConnection(request.response, clientId);
    if (connectionLease == null) return;
    try {
      await startAudioRuntime();
      await _handleAudio(
        request.response,
        clientId,
        onDetached: connectionLease.release,
      );
    } catch (_) {
      connectionLease.release();
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handlePairConfirm(HttpRequest request) async {
    try {
      if (!_pairingModeActive) {
        request.response.statusCode = HttpStatus.notFound;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_NOT_ACTIVE',
          'message': 'Pairing is not active on this room device.',
        });
        return;
      }
      if (!tokenService.consumePairConfirmAttempt(
        _pairConfirmAttemptKey(request),
      )) {
        request.response.statusCode = HttpStatus.tooManyRequests;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIR_CONFIRM_RATE_LIMITED',
          'message': 'Pairing attempts are temporarily rate limited.',
        });
        return;
      }
      final json = await _readJsonObjectBody(request);
      if (json == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_REQUEST_INVALID',
          'message': 'Pairing request is invalid.',
        });
        return;
      }
      final serverDeviceId = await _serverDeviceIdentityResolver.resolve();
      final originServerDeviceId =
          json['originServerDeviceId']?.toString().trim() ?? '';
      if (originServerDeviceId.isNotEmpty &&
          originServerDeviceId == serverDeviceId) {
        request.response.statusCode = HttpStatus.conflict;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'SELF_PAIRING_NOT_ALLOWED',
          'message': 'A device cannot pair with its own room.',
        });
        return;
      }
      if (tokenService.validateAndConsumeNonce(
              json['pairingNonce']?.toString() ?? '') ==
          false) {
        request.response.statusCode = HttpStatus.unauthorized;
        await _writeJson(request.response, {
          'ok': false,
          'code': 'PAIRING_NONCE_INVALID_OR_EXPIRED',
          'message': 'This pairing QR has expired or was already used.',
        });
        return;
      }
      final token = await tokenService.issueTrustedClientTokenPersisted(
          clientName: json['clientName']?.toString() ?? 'Client',
          deviceId: json['deviceId']?.toString() ?? 'client');
      await _writeJson(request.response, {
        'serverDeviceId': serverDeviceId,
        'serverName': 'Bebek Odası',
        'clientId': token.clientId,
        'trustedClientToken': token.token,
        'trustedClientTokenExpiresAtMs': token.expiresAtMs,
        'capabilities': _mediaCapabilities(),
        'sessionToken': token.token,
      });
    } on RequestBodyTooLargeException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } on RequestBodyReadTimeoutException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } on TrustedClientLimitException {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': TrustedClientLimitException.code,
        'message': TrustedClientLimitException.userMessage,
      });
    } on TrustedClientPersistenceException {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'ok': false,
        'code': TrustedClientPersistenceException.code,
        'message': 'Pairing could not be saved on this room device.',
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'PAIRING_REQUEST_INVALID',
        'message': 'Pairing request is invalid.',
      });
    }
  }

  Future<void> _handleAuthRenew(HttpRequest request) async {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : null;
    if (token == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    TrustedClientToken? renewed;
    try {
      renewed = await tokenService.renewTrustedClientTokenPersisted(token);
    } on TrustedClientPersistenceException {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'ok': false,
        'code': TrustedClientPersistenceException.code,
        'message': 'The renewed session could not be saved.',
      });
      return;
    }
    if (renewed == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    await _writeJson(request.response, {
      'clientId': renewed.clientId,
      'trustedClientToken': renewed.token,
      'expiresAtMs': renewed.expiresAtMs,
    });
  }
}

/// Serializes session and WebRTC lifecycle operations behind one boundary.
