part of '../mimicam_server.dart';

extension MimiCamServerSessionHttpController on MimiCamServer {
  Future<void> _handleSessionStart(HttpRequest request) =>
      _sessionOperations.run(() => _handleSessionStartLocked(request));

  Future<void> _handleSessionStartLocked(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonObjectBody(request);
    } catch (error) {
      await _rejectInvalidJsonBody(request, error);
      return;
    }

    final clientId = _clientIdForRequest(request, json);
    final demand = _streamDemandForRequest(json);
    final mediaTransport = _mediaTransportForRequest(json);
    final runtimeDemand =
        mediaTransport == 'webrtc' ? (video: false, audio: false) : demand;
    BroadcastAccessSnapshot? accessSnapshot;
    try {
      accessSnapshot = await _broadcastAccess?.beginSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
    } on BroadcastAccessLockedException catch (error) {
      request.response.statusCode = HttpStatus.paymentRequired;
      await _writeBroadcastAccessLocked(request, error.snapshot);
      return;
    }
    late final ActiveSessionStartResult startResult;
    try {
      startResult = _sessionController.startActiveSession(clientId);
    } on ActiveClientLimitException {
      accessSnapshot = await _broadcastAccess?.endSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
      request.response.statusCode = HttpStatus.tooManyRequests;
      await _writeJson(request.response, {
        'ok': false,
        'code': ActiveClientLimitException.code,
        'message': ActiveClientLimitException.userMessage,
      });
      return;
    }
    final sessionClientId = startResult.clientId;
    final hadExistingSession = !startResult.createdActiveSlot;
    final previousSession = _sessions.snapshot(sessionClientId);
    final hadRuntimeSession = previousSession?.runtimeOwned ?? false;
    final sameRuntimeRequest = hadExistingSession &&
        _sessions.requestMatches(
          sessionClientId,
          demand: demand,
          mediaTransport: mediaTransport,
        );
    var runtimeMutationApplied = false;
    try {
      _sessions.recordRequest(
        sessionClientId,
        demand: demand,
        mediaTransport: mediaTransport,
      );
      await _applyMediaProfileForCurrentDemand();
      final callback = onStreamSessionStarted;
      if (callback != null) {
        if (!sameRuntimeRequest) {
          await callback(
            sessionClientId,
            video: demand.video,
            audio: demand.audio,
            mediaTransport: mediaTransport,
          );
          runtimeMutationApplied = true;
        }
        _sessions.markRuntimeOwned(sessionClientId, owned: true);
      } else if (startMediaOnSessionStart) {
        if (!sameRuntimeRequest) {
          _sessions.setStandaloneDemand(sessionClientId, runtimeDemand);
          await _reconcileStandaloneSessionDemand();
          runtimeMutationApplied = true;
        }
        _sessions.markRuntimeOwned(sessionClientId, owned: true);
      }
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': startResult.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
        'streamToken': startResult.streamToken.token,
        'streamTokenExpiresAtMs': startResult.streamToken.expiresAtMs,
        'video': demand.video,
        'audio': demand.audio,
        'mediaTransport': mediaTransport,
        if (accessSnapshot != null) 'broadcastAccess': accessSnapshot.toJson(),
      });
    } catch (error) {
      if (hadExistingSession) {
        _sessions.restore(sessionClientId, previousSession);

        if (runtimeMutationApplied) {
          try {
            final callback = onStreamSessionStarted;
            if (hadRuntimeSession &&
                callback != null &&
                previousSession != null) {
              await callback(
                sessionClientId,
                video: previousSession.demand.video,
                audio: previousSession.demand.audio,
                mediaTransport: previousSession.mediaTransport,
              );
            } else if (hadRuntimeSession && startMediaOnSessionStart) {
              await _reconcileStandaloneSessionDemand();
            } else if (!hadRuntimeSession) {
              final stopCallback = onStreamSessionStopped;
              if (stopCallback != null) {
                await stopCallback(sessionClientId);
              } else if (startMediaOnSessionStart) {
                await _reconcileStandaloneSessionDemand();
              }
            }
          } catch (rollbackError) {
            onLog('Session replacement rollback failed: $rollbackError');
          }
        }
        try {
          await _applyMediaProfileForCurrentDemand();
        } catch (rollbackError) {
          onLog('Session media profile rollback failed: $rollbackError');
        }
        _sessionController.rollbackActiveSession(startResult);
      } else if (runtimeMutationApplied) {
        _sessions.markRuntimeOwned(sessionClientId, owned: false);
        try {
          final callback = onStreamSessionStopped;
          if (callback != null) {
            await callback(sessionClientId);
          } else {
            _sessions.setStandaloneDemand(sessionClientId, null);
            await _reconcileStandaloneSessionDemand();
          }
        } catch (rollbackError) {
          onLog('Session runtime rollback failed: $rollbackError');
        }
      }
      if (!hadExistingSession) {
        _sessions.remove(sessionClientId);
        _sessionController.rollbackActiveSession(startResult);
        try {
          accessSnapshot = await _broadcastAccess?.endSession(
            _broadcastAccessSessionId(clientId),
          );
          _notifyBroadcastAccessChanged(accessSnapshot);
          _scheduleBroadcastAccessTimer(accessSnapshot);
        } catch (accessError) {
          onLog('Session access rollback failed: $accessError');
        }
      }
      onLog('Medya başlatılamadı: $error');
      await _writeJsonBestEffort(
        request.response,
        statusCode: HttpStatus.internalServerError,
        body: {
          'ok': false,
          'code': 'MEDIA_START_FAILED',
          'message': 'The media session could not be started.',
        },
      );
    }
  }

  Future<void> _handleSessionStop(HttpRequest request) =>
      _sessionOperations.run(() => _handleSessionStopLocked(request));

  Future<void> _handleSessionStopLocked(HttpRequest request) async {
    Object? json;
    try {
      json = await _readJsonObjectBody(request);
    } catch (error) {
      await _rejectInvalidJsonBody(request, error);
      return;
    }

    final clientId = _clientIdForRequest(request, json);
    final errors = await _cleanupClientSession(clientId, closeWebRtc: true);
    if (errors.isEmpty) {
      await _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      });
      return;
    }
    onLog('Session cleanup completed with errors: ${errors.join(' | ')}');
    await _writeJsonBestEffort(
      request.response,
      statusCode: HttpStatus.internalServerError,
      body: {
        'ok': false,
        'code': 'SESSION_CLEANUP_PARTIAL',
        'message': 'The media session could not be fully closed.',
      },
    );
  }

  Future<void> _handleWebRtcOffer(
    HttpRequest request,
    String? authenticatedClientId,
  ) =>
      _sessionOperations.run(
        () => _handleWebRtcOfferLocked(request, authenticatedClientId),
      );

  Future<void> _handleWebRtcOfferLocked(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final clientId = authenticatedClientId!;
    var externalCaptureActivated = false;
    StreamAttachResult? peerTransportLease;
    String? createdPeerId;
    try {
      final body = await _readJsonObjectBody(request);
      final offer = WebRtcOfferRequest.fromJson(body);
      await onWebRtcCaptureStarting?.call(clientId);
      externalCaptureActivated = true;
      final answer = await gateway.acceptOffer(
        clientId: clientId,
        request: offer,
      );
      createdPeerId = answer.peerId;
      // WebRTC has no MJPEG/WAV socket to call attachStream. Keep an explicit
      // transport lease so the 90-second bootstrap token expiry cannot prune
      // a healthy peer from capacity and paywall cleanup accounting.
      peerTransportLease = _activeClientRegistry.attachStream(clientId);
      _updateResourceWatchdog();
      await _writeJson(request.response, answer.toJson());
    } on RequestBodyTooLargeException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
      }
      await _rejectInvalidJsonBody(request, error);
    } on RequestBodyReadTimeoutException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
      }
      await _rejectInvalidJsonBody(request, error);
    } on FormatException catch (error) {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'INVALID_WEBRTC_OFFER',
        'message': error.message,
      });
    } on WebRtcPilotCapacityException {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_PILOT_CAPACITY',
        'message': 'WebRTC capacity is currently full.',
        'fallback': 'mjpeg_wav',
      });
    } on WebRtcPilotUnavailableException {
      if (externalCaptureActivated) {
        await onWebRtcCaptureEnded?.call(clientId);
        externalCaptureActivated = false;
      }
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_UNAVAILABLE',
        'message': 'WebRTC is currently unavailable.',
        'fallback': 'mjpeg_wav',
      });
    } on ConnectionLimitException catch (error) {
      peerTransportLease?.release();
      if (createdPeerId != null) {
        try {
          await gateway.closePeer(
            clientId: clientId,
            peerId: createdPeerId,
          );
        } catch (_) {}
      }
      if (externalCaptureActivated) {
        try {
          await onWebRtcCaptureEnded?.call(clientId);
        } catch (_) {}
      }
      await _writeConnectionLimitError(request.response, error);
    } catch (error) {
      onLog('WebRTC negotiation failed: $error');
      peerTransportLease?.release();
      if (createdPeerId != null) {
        try {
          await gateway.closePeer(
            clientId: clientId,
            peerId: createdPeerId,
          );
        } catch (_) {}
      }
      if (externalCaptureActivated) {
        try {
          await onWebRtcCaptureEnded?.call(clientId);
        } catch (_) {}
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_NEGOTIATION_FAILED',
        'message': 'WebRTC negotiation failed.',
        'fallback': 'mjpeg_wav',
      });
    }
  }

  Future<void> _handleWebRtcIce(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final peerId = request.uri.queryParameters['peerId']?.trim() ?? '';
    if (peerId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    try {
      if (request.method == HttpMethod.post) {
        final body = await _readJsonObjectBody(request);
        final candidate = WebRtcIceCandidateSignal.fromJson(
          body?['candidate'],
        );
        await gateway.addRemoteCandidate(
          clientId: authenticatedClientId!,
          peerId: peerId,
          candidate: candidate,
        );
        await _writeJson(request.response, const {'ok': true});
      } else {
        final candidates = gateway.drainLocalCandidates(
          clientId: authenticatedClientId!,
          peerId: peerId,
        );
        await _writeJson(request.response, {
          'ok': true,
          'iceCandidates': candidates.map((item) => item.toJson()).toList(),
        });
      }
    } on RequestBodyTooLargeException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } on RequestBodyReadTimeoutException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'INVALID_ICE_CANDIDATE',
        'message': error.message,
      });
    } on WebRtcPeerNotFoundException {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleWebRtcClose(
    HttpRequest request,
    String? authenticatedClientId,
  ) =>
      _sessionOperations.run(
        () => _handleWebRtcCloseLocked(request, authenticatedClientId),
      );

  Future<void> _handleWebRtcCloseLocked(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = await _authorizedWebRtcGateway(
      request,
      authenticatedClientId,
    );
    if (gateway == null) return;
    final peerId = request.uri.queryParameters['peerId']?.trim() ?? '';
    try {
      await gateway.closePeer(
        clientId: authenticatedClientId!,
        peerId: peerId,
      );
    } on WebRtcPeerNotFoundException {
      // Close is idempotent from the client's perspective.
    }
    final errors = await _cleanupClientSession(
      authenticatedClientId!,
      closeWebRtc: false,
    );
    await _writeJson(request.response, {
      'ok': errors.isEmpty,
      if (errors.isNotEmpty) 'cleanupError': errors.first.toString(),
    });
  }

  Future<void> pauseExternalMediaForPlatform(String reason) async {
    final gateway = webRtcGateway;
    if (gateway == null || gateway.activePeerCount == 0) return;
    if (gateway is WebRtcBackgroundMediaController) {
      await (gateway as WebRtcBackgroundMediaController)
          .suspendVideoForBackground();
    } else {
      for (final clientId in _activeClientRegistry.activeClientIds) {
        await gateway.closeClient(clientId);
      }
    }
    onLog('WebRTC video paused; background audio preserved: $reason');
  }

  Future<void> recoverExternalMediaForPlatform(String reason) async {
    final gateway = webRtcGateway;
    if (gateway == null ||
        gateway is! WebRtcBackgroundMediaController ||
        gateway.activePeerCount == 0) {
      return;
    }
    await (gateway as WebRtcBackgroundMediaController)
        .reconnectPeersForForeground();
    onLog('WebRTC peers reconnecting after foreground recovery: $reason');
  }

  void _handleWebRtcPeerLifecycleEvent(WebRtcPeerLifecycleEvent event) {
    if (_disposed) return;
    unawaited(_sessionOperations.run(() async {
      if (!_sessions.ownsRuntime(event.clientId) &&
          !_activeClientRegistry.activeClientIds.contains(event.clientId)) {
        return;
      }
      final errors = await _cleanupClientSession(
        event.clientId,
        closeWebRtc: false,
      );
      onLog(
        'WebRTC peer closed (${event.reason.name}); session released'
        '${errors.isEmpty ? '' : ': ${errors.join(' | ')}'}',
      );
    }).catchError((Object error) {
      onLog('WebRTC peer cleanup could not be queued: $error');
    }));
  }

  Future<List<Object>> _cleanupClientSession(
    String clientId, {
    required bool closeWebRtc,
  }) async {
    final cleanup = BestEffortOperationCollector();

    if (closeWebRtc) {
      await cleanup.attempt(
        'WebRTC client',
        () async => webRtcGateway?.closeClient(clientId),
      );
    }
    await cleanup.attempt(
      'video stream client',
      () => _videoStreamService.closeClient(clientId),
    );
    await cleanup.attempt(
      'audio stream client',
      () => _audioStreamService.closeClient(clientId),
    );
    _sessionController.stopActiveSession(clientId);
    final session = _sessions.remove(clientId);
    final ownedRuntimeSession = session?.runtimeOwned ?? false;
    if (ownedRuntimeSession) {
      final callback = onStreamSessionStopped;
      if (callback != null) {
        await cleanup.attempt(
            'media runtime session', () => callback(clientId));
      } else {
        await cleanup.attempt(
          'standalone media demand',
          _reconcileStandaloneSessionDemand,
        );
      }
    }

    await cleanup.attempt('broadcast access session', () async {
      final accessSnapshot = await _broadcastAccess?.endSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
    });
    if (_activeClientRegistry.activeClientCount > 0) {
      await cleanup.attempt(
        'remaining client media profile',
        _applyMediaProfileForCurrentDemand,
      );
    }
    _updateResourceWatchdog();
    return cleanup.errors;
  }

  Future<WebRtcServerGateway?> _authorizedWebRtcGateway(
    HttpRequest request,
    String? authenticatedClientId,
  ) async {
    final gateway = webRtcGateway;
    if (!config.webRtcPilotEnabled || gateway == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return null;
    }
    if (!gateway.isAvailable && !await gateway.initialize()) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, const {
        'ok': false,
        'code': 'WEBRTC_UNAVAILABLE',
        'fallback': 'mjpeg_wav',
      });
      return null;
    }
    final tokenClientId =
        _streamTokenClientId(request.uri.queryParameters['streamToken']);
    if (authenticatedClientId == null ||
        tokenClientId == null ||
        authenticatedClientId != tokenClientId) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return null;
    }
    return gateway;
  }

  Future<void> _handleQualityReport(HttpRequest request) async {
    try {
      final json = await _readJsonObjectBody(request);
      if (json == null) throw const FormatException('Invalid quality report');
      final auth = _authGuard.trusted(request);
      if (auth == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      // Body clientId is telemetry metadata only; the trusted Bearer token owns
      // the identity used for quality decisions and cleanup.
      final report = ClientQualityReport.fromJson(
        Map<Object?, Object?>.from(json),
        clientId: auth.clientId,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      final battery = BatterySnapshot.fromJson(json['battery']);
      if (battery != null) _clientBatterySnapshots[auth.clientId] = battery;
      final serverBattery = await _refreshServerBattery();
      _activeClientRegistry.updateQualityReport(report);
      final pendingProfile = _previewMediaProfileForCurrentDemand();
      _scheduleMediaProfileApplyForCurrentDemand();
      await _writeJson(request.response, {
        'ok': true,
        'deviceTier': _deviceTier.name,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'effectiveNetworkTier': _activeClientRegistry.effectiveTier().name,
        'mediaProfile': _effectiveMediaProfile(pendingProfile).toJson(),
        'battery': serverBattery.toJson(),
        'clientBattery': battery?.toJson(),
        'transport': _transportStatus(),
        'streamHealth': _streamHealthStatus(
          DateTime.now().millisecondsSinceEpoch,
        ),
        'deviceResources': _deviceResources.toJson(),
        'resourceGovernor': _resourceDecision.toJson(),
      });
    } on RequestBodyTooLargeException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } on RequestBodyReadTimeoutException catch (error) {
      await _rejectInvalidJsonBody(request, error);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  }
}
