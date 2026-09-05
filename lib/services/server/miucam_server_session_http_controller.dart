part of '../miucam_server.dart';

extension MiuCamServerSessionHttpController on MiuCamServer {
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
    late final String streamAttemptId;
    try {
      streamAttemptId = _streamAttemptIdForRequest(json);
    } on FormatException {
      await _rejectInvalidAttemptId(
        request,
        code: protocol_v2.MiuCamProtocolV2.invalidStreamAttemptIdCode,
        field: protocol_v2.MiuCamProtocolV2.streamAttemptId,
      );
      return;
    }

    await _drainExpiredClientSessionsLocked();
    // Authorization may have been revoked while this request waited for the
    // session queue or while its body was being read.
    final auth = await _requireTrustedAuth(request);
    if (auth == null) return;
    final clientId = auth.clientId;
    if (_sessionController.isStreamAttemptCancelled(
      clientId,
      streamAttemptId,
    )) {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'SESSION_START_CANCELLED',
        'message': 'The media session start was already cancelled.',
      });
      return;
    }
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
    // beginSession can await storage. Never allocate a slot using credentials
    // that were removed during that await.
    if (_authGuard.trusted(request) == null) {
      accessSnapshot = await _broadcastAccess?.endSession(
        _broadcastAccessSessionId(clientId),
      );
      _notifyBroadcastAccessChanged(accessSnapshot);
      _scheduleBroadcastAccessTimer(accessSnapshot);
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
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
    var rollbackSession = previousSession;
    final hadRuntimeSession = previousSession?.runtimeOwned ?? false;
    final sameRuntimeRequest = hadExistingSession &&
        _sessions.requestMatches(
          sessionClientId,
          demand: demand,
          mediaTransport: mediaTransport,
        );
    var runtimeMutationApplied = false;
    try {
      // A newly issued stream token supersedes signaling already admitted by
      // the previous token. Invalidate it synchronously so a late offer cannot
      // publish or deactivate resources owned by this replacement.
      _invalidateWebRtcOffer(sessionClientId);
      final gateway = webRtcGateway;
      if (gateway != null) {
        _cancelPendingWebRtcOffer(gateway, sessionClientId);
      }

      final previousPeer = previousSession?.webRtcPeer;
      if (previousPeer != null && !sameRuntimeRequest) {
        final activeGateway = webRtcGateway;
        if (activeGateway == null) {
          throw StateError(
            'The current WebRTC peer cannot be retired without its gateway.',
          );
        }
        await _closeWebRtcPeerStrict(
          activeGateway,
          clientId: sessionClientId,
          peerId: previousPeer.peerId,
        );
        final retired = _sessions.takeWebRtcPeer(
          sessionClientId,
          peerId: previousPeer.peerId,
        );
        if (!identical(retired, previousPeer)) {
          throw const _StaleWebRtcPeerOwnership();
        }
        retired!.release();
        rollbackSession = _sessions.snapshot(sessionClientId);
        _updateResourceWatchdog();

        // Closing the physical peer is not enough: ServerRuntime must release
        // its external-capture owner before a legacy callback may acquire the
        // camera or microphone. This path is strict by design.
        await _endWebRtcCaptureStrict(sessionClientId);
      }

      _sessions.recordRequest(
        sessionClientId,
        demand: demand,
        mediaTransport: mediaTransport,
        streamAttemptId: streamAttemptId,
      );
      await _runBoundedStreamSessionLifecycle(
        _applyMediaProfileForCurrentDemand,
      );
      final callback = onStreamSessionStarted;
      if (callback != null) {
        if (!sameRuntimeRequest) {
          // Native capture may already be mutated even when its Future never
          // settles. Claim rollback ownership before awaiting the callback.
          runtimeMutationApplied = true;
          await _runBoundedStreamSessionLifecycle(
            () => callback(
              sessionClientId,
              video: demand.video,
              audio: demand.audio,
              mediaTransport: mediaTransport,
            ),
          );
        }
        _sessions.markRuntimeOwned(sessionClientId, owned: true);
      } else if (startMediaOnSessionStart) {
        if (!sameRuntimeRequest) {
          _sessions.setStandaloneDemand(sessionClientId, runtimeDemand);
          runtimeMutationApplied = true;
          await _runBoundedStreamSessionLifecycle(
            _reconcileStandaloneSessionDemand,
          );
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
        protocol_v2.MiuCamProtocolV2.streamAttemptId: streamAttemptId,
        if (accessSnapshot != null) 'broadcastAccess': accessSnapshot.toJson(),
      });
    } catch (error) {
      if (hadExistingSession) {
        _sessions.restore(sessionClientId, rollbackSession);

        if (runtimeMutationApplied) {
          try {
            final callback = onStreamSessionStarted;
            final previous = rollbackSession;
            if (hadRuntimeSession && callback != null && previous != null) {
              await _runBoundedStreamSessionLifecycle(
                () => callback(
                  sessionClientId,
                  video: previous.demand.video,
                  audio: previous.demand.audio,
                  mediaTransport: previous.mediaTransport,
                ),
              );
            } else if (hadRuntimeSession && startMediaOnSessionStart) {
              await _runBoundedStreamSessionLifecycle(
                _reconcileStandaloneSessionDemand,
              );
            } else if (!hadRuntimeSession) {
              final stopCallback = onStreamSessionStopped;
              if (stopCallback != null) {
                await _runBoundedStreamSessionLifecycle(
                  () => stopCallback(sessionClientId),
                );
              } else if (startMediaOnSessionStart) {
                await _runBoundedStreamSessionLifecycle(
                  _reconcileStandaloneSessionDemand,
                );
              }
            }
          } catch (rollbackError) {
            onLog('Session replacement rollback failed: $rollbackError');
          }
        }
        try {
          await _runBoundedStreamSessionLifecycle(
            _applyMediaProfileForCurrentDemand,
          );
        } catch (rollbackError) {
          onLog('Session media profile rollback failed: $rollbackError');
        }
        _sessionController.rollbackActiveSession(startResult);
      } else if (runtimeMutationApplied) {
        _sessions.markRuntimeOwned(sessionClientId, owned: false);
        try {
          final callback = onStreamSessionStopped;
          if (callback != null) {
            await _runBoundedStreamSessionLifecycle(
              () => callback(sessionClientId),
            );
          } else {
            _sessions.setStandaloneDemand(sessionClientId, null);
            await _runBoundedStreamSessionLifecycle(
              _reconcileStandaloneSessionDemand,
            );
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

  Future<void> _runBoundedStreamSessionLifecycle(
    FutureOr<void> Function() operation,
  ) =>
      Future<void>.sync(operation).timeout(streamSessionLifecycleTimeout);

  Future<void> _drainExpiredClientSessionsLocked() async {
    final expiredClientIds =
        _activeClientRegistry.expiredSessionClientIdsReadyForCleanup();
    for (final expiredClientId in expiredClientIds) {
      if (!_activeClientRegistry.isExpiredSessionReady(expiredClientId)) {
        continue;
      }
      final errors = await _cleanupClientSession(
        expiredClientId,
        closeWebRtc: true,
      );
      if (errors.isNotEmpty) {
        onLog(
          'Expired stream-session pre-start cleanup completed with errors '
          '($expiredClientId): ${errors.join(' | ')}',
        );
      }
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
    late final String streamAttemptId;
    try {
      streamAttemptId = _streamAttemptIdForRequest(json);
    } on FormatException {
      await _rejectInvalidAttemptId(
        request,
        code: protocol_v2.MiuCamProtocolV2.invalidStreamAttemptIdCode,
        field: protocol_v2.MiuCamProtocolV2.streamAttemptId,
      );
      return;
    }

    final auth = await _requireTrustedAuth(request);
    if (auth == null) return;
    final clientId = auth.clientId;
    _sessionController.cancelStreamAttempt(clientId, streamAttemptId);
    if (_sessions.snapshot(clientId)?.streamAttemptId != streamAttemptId) {
      await _writeSessionStopSuccess(request);
      return;
    }
    final errors = await _cleanupClientSession(clientId, closeWebRtc: true);
    if (errors.isEmpty) {
      await _writeSessionStopSuccess(request);
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

  Future<void> _writeSessionStopSuccess(HttpRequest request) =>
      _writeJson(request.response, {
        'ok': true,
        'activeStreamClients': _activeClientRegistry.activeClientCount,
        'mediaProfile': _effectiveMediaProfile().toJson(),
      });

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
    final initialSession = _sessions.snapshot(clientId);
    if (initialSession == null || initialSession.mediaTransport != 'webrtc') {
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, const {
        'ok': false,
        'code': 'WEBRTC_SESSION_REQUIRED',
        'message': 'Start a WebRTC media session before sending an offer.',
      });
      return;
    }
    final offerGeneration = _nextWebRtcOfferGeneration(clientId);
    final previousPeer = initialSession.webRtcPeer;
    var captureStartAttempted = false;
    var shouldEndExternalOnFailure = previousPeer == null;
    StreamAttachResult? peerTransportLease;
    String? createdPeerId;

    Future<void> cleanupFailedOffer() async {
      final unboundLease = peerTransportLease;
      peerTransportLease = null;
      unboundLease?.release();
      final peerId = createdPeerId;
      if (peerId != null) {
        _sessions.takeWebRtcPeer(clientId, peerId: peerId)?.release();
        await _closeWebRtcPeerBestEffort(
          gateway,
          clientId: clientId,
          peerId: peerId,
        );
      }
      if (captureStartAttempted && shouldEndExternalOnFailure) {
        await _endWebRtcCaptureBestEffort(clientId);
      }
      _updateResourceWatchdog();
    }

    try {
      final body = await _readJsonObjectBody(request);
      final offer = WebRtcOfferRequest.fromJson(body);
      captureStartAttempted = true;
      final captureStart = Future<void>.sync(() async {
        await onWebRtcCaptureStarting?.call(clientId);
      });
      try {
        await captureStart.timeout(webRtcNegotiationTimeout);
      } on TimeoutException {
        unawaited(captureStart.then<void>(
          (_) async {
            if (shouldEndExternalOnFailure &&
                (_isCurrentWebRtcOffer(clientId, offerGeneration) ||
                    _sessions.snapshot(clientId) == null)) {
              await _endWebRtcCaptureBestEffort(clientId);
            }
          },
          onError: (Object _, StackTrace __) {},
        ));
        rethrow;
      }

      if (previousPeer != null) {
        // Retire the exact old peer before its replacement is created. This
        // keeps the per-client connection limit at one and prevents the
        // gateway's client-wide cleanup from ever targeting a later peer.
        await _closeWebRtcPeerStrict(
          gateway,
          clientId: clientId,
          peerId: previousPeer.peerId,
        );
        final retired = _sessions.takeWebRtcPeer(
          clientId,
          peerId: previousPeer.peerId,
        );
        if (!identical(retired, previousPeer)) {
          throw const _StaleWebRtcPeerOwnership();
        }
        retired!.release();
        shouldEndExternalOnFailure = true;
        _updateResourceWatchdog();
      }

      final answerOperation = Future<WebRtcOfferResponse>.sync(
        () => gateway.acceptOffer(
          clientId: clientId,
          request: offer,
        ),
      );
      late final WebRtcOfferResponse answer;
      try {
        answer = await answerOperation.timeout(webRtcNegotiationTimeout);
      } on TimeoutException {
        _cancelPendingWebRtcOffer(gateway, clientId);
        _discardLateWebRtcAnswer(
          gateway: gateway,
          clientId: clientId,
          generation: offerGeneration,
          answerOperation: answerOperation,
        );
        rethrow;
      }
      createdPeerId = answer.peerId;
      if (!_isCurrentWebRtcOffer(clientId, offerGeneration)) {
        throw const _StaleWebRtcOffer();
      }
      // WebRTC has no MJPEG/WAV socket to call attachStream. Keep an explicit
      // transport lease so the 90-second bootstrap token expiry cannot prune
      // a healthy peer from capacity and paywall cleanup accounting.
      peerTransportLease = _activeClientRegistry.attachStream(clientId);
      _sessions.bindWebRtcPeer(
        clientId,
        peerId: answer.peerId,
        transportLease: peerTransportLease!,
      );
      // Ownership moved into ServerSessionRegistry. From here every failure
      // must take it back with a peer-id CAS before releasing it.
      peerTransportLease = null;
      _updateResourceWatchdog();
      await _writeJson(request.response, answer.toJson());
    } on RequestBodyTooLargeException catch (error) {
      await cleanupFailedOffer();
      await _rejectInvalidJsonBody(request, error);
    } on RequestBodyReadTimeoutException catch (error) {
      await cleanupFailedOffer();
      await _rejectInvalidJsonBody(request, error);
    } on FormatException catch (error) {
      await cleanupFailedOffer();
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'INVALID_WEBRTC_OFFER',
        'message': error.message,
      });
    } on WebRtcPilotCapacityException {
      await cleanupFailedOffer();
      request.response.statusCode = HttpStatus.conflict;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_PILOT_CAPACITY',
        'message': 'WebRTC capacity is currently full.',
        'fallback': 'mjpeg_wav',
      });
    } on WebRtcPilotUnavailableException {
      await cleanupFailedOffer();
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await _writeJson(request.response, {
        'ok': false,
        'code': 'WEBRTC_UNAVAILABLE',
        'message': 'WebRTC is currently unavailable.',
        'fallback': 'mjpeg_wav',
      });
    } on TimeoutException catch (error) {
      onLog('WebRTC negotiation timed out: $error');
      _cancelPendingWebRtcOffer(gateway, clientId);
      await cleanupFailedOffer();
      request.response.statusCode = HttpStatus.gatewayTimeout;
      await _writeJsonBestEffort(
        request.response,
        statusCode: HttpStatus.gatewayTimeout,
        body: const {
          'ok': false,
          'code': 'WEBRTC_NEGOTIATION_TIMEOUT',
          'message': 'WebRTC negotiation timed out.',
          'fallback': 'mjpeg_wav',
        },
      );
    } on ConnectionLimitException catch (error) {
      await cleanupFailedOffer();
      await _writeConnectionLimitError(request.response, error);
    } catch (error) {
      onLog('WebRTC negotiation failed: $error');
      await cleanupFailedOffer();
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
        await gateway
            .addRemoteCandidate(
              clientId: authenticatedClientId!,
              peerId: peerId,
              candidate: candidate,
            )
            .timeout(webRtcCleanupTimeout);
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
    } on TimeoutException {
      request.response.statusCode = HttpStatus.gatewayTimeout;
      await _writeJsonBestEffort(
        request.response,
        statusCode: HttpStatus.gatewayTimeout,
        body: const {
          'ok': false,
          'code': 'WEBRTC_SIGNALING_TIMEOUT',
        },
      );
    }
  }

  int _nextWebRtcOfferGeneration(String clientId) {
    final generation = (_webRtcOfferGenerations[clientId] ?? 0) + 1;
    _webRtcOfferGenerations[clientId] = generation;
    return generation;
  }

  bool _isCurrentWebRtcOffer(String clientId, int generation) =>
      _webRtcOfferGenerations[clientId] == generation;

  void _invalidateWebRtcOffer(String clientId) {
    _webRtcOfferGenerations[clientId] =
        (_webRtcOfferGenerations[clientId] ?? 0) + 1;
  }

  void _cancelPendingWebRtcOffer(
    WebRtcServerGateway gateway,
    String clientId,
  ) {
    if (gateway is! WebRtcPendingOfferController) return;
    final controller = gateway as WebRtcPendingOfferController;
    try {
      final cancellation = controller.cancelPendingOffer(clientId);
      unawaited(
        cancellation.timeout(webRtcCleanupTimeout).catchError((Object error) {
          onLog('Pending WebRTC offer cleanup failed: $error');
        }),
      );
    } catch (error) {
      onLog('Pending WebRTC offer cancellation failed: $error');
    }
  }

  void _discardLateWebRtcAnswer({
    required WebRtcServerGateway gateway,
    required String clientId,
    required int generation,
    required Future<WebRtcOfferResponse> answerOperation,
  }) {
    unawaited(answerOperation.then<void>(
      (lateAnswer) async {
        final currentPeerId = _sessions.snapshot(clientId)?.webRtcPeerId;
        if (!_isCurrentWebRtcOffer(clientId, generation) &&
            currentPeerId == lateAnswer.peerId) {
          return;
        }
        await _closeWebRtcPeerBestEffort(
          gateway,
          clientId: clientId,
          peerId: lateAnswer.peerId,
        );
      },
      onError: (Object _, StackTrace __) {},
    ));
  }

  Future<Object?> _closeWebRtcPeerBestEffort(
    WebRtcServerGateway gateway, {
    required String clientId,
    required String peerId,
  }) async {
    try {
      await gateway
          .closePeer(
            clientId: clientId,
            peerId: peerId,
          )
          .timeout(webRtcCleanupTimeout);
      return null;
    } on WebRtcPeerNotFoundException {
      return null;
    } catch (error) {
      onLog('WebRTC peer cleanup failed: $error');
      return error;
    }
  }

  Future<void> _closeWebRtcPeerStrict(
    WebRtcServerGateway gateway, {
    required String clientId,
    required String peerId,
  }) async {
    try {
      await gateway
          .closePeer(
            clientId: clientId,
            peerId: peerId,
          )
          .timeout(webRtcCleanupTimeout);
    } on WebRtcPeerNotFoundException {
      // The physical peer is already gone, so its exact ownership can be
      // retired safely.
    }
  }

  Future<void> _endWebRtcCaptureStrict(String clientId) async {
    final callback = onWebRtcCaptureEnded;
    if (callback == null) return;
    await Future<void>.sync(() async {
      await callback(clientId);
    }).timeout(webRtcCleanupTimeout);
  }

  Future<void> _endWebRtcCaptureBestEffort(String clientId) async {
    final callback = onWebRtcCaptureEnded;
    if (callback == null) return;
    try {
      await Future<void>.sync(() async {
        await callback(clientId);
      }).timeout(webRtcCleanupTimeout);
    } catch (error) {
      onLog('WebRTC capture cleanup failed: $error');
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
    final clientId = authenticatedClientId!;
    final peerId = request.uri.queryParameters['peerId']?.trim() ?? '';
    final ownsCurrentSession =
        _sessions.snapshot(clientId)?.webRtcPeerId == peerId;
    final peerCloseError = await _closeWebRtcPeerBestEffort(
      gateway,
      clientId: clientId,
      peerId: peerId,
    );
    final errors = ownsCurrentSession && peerCloseError == null
        ? await _cleanupClientSession(
            clientId,
            closeWebRtc: false,
          )
        : const <Object>[];
    await _writeJson(request.response, {
      'ok': peerCloseError == null && errors.isEmpty,
      if (peerCloseError != null) 'peerCloseError': peerCloseError.toString(),
      if (errors.isNotEmpty) 'cleanupError': errors.first.toString(),
    });
  }

  Future<void> pauseExternalMediaForPlatform(String reason) async {
    final gateway = webRtcGateway;
    if (gateway == null || gateway.activePeerCount == 0) return;
    if (gateway is WebRtcBackgroundMediaController) {
      await (gateway as WebRtcBackgroundMediaController)
          .suspendVideoForBackground()
          .timeout(webRtcCleanupTimeout);
    } else {
      for (final clientId in _activeClientRegistry.activeClientIds) {
        await gateway.closeClient(clientId).timeout(webRtcCleanupTimeout);
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
        .reconnectPeersForForeground()
        .timeout(webRtcCleanupTimeout);
    onLog('WebRTC peers reconnecting after foreground recovery: $reason');
  }

  void _handleWebRtcPeerLifecycleEvent(WebRtcPeerLifecycleEvent event) {
    if (_disposed) return;
    unawaited(_sessionOperations.run(() async {
      final session = _sessions.snapshot(event.clientId);
      if (session?.webRtcPeerId != event.peerId) {
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
    _invalidateWebRtcOffer(clientId);
    final gateway = webRtcGateway;
    if (gateway != null) {
      _cancelPendingWebRtcOffer(gateway, clientId);
    }
    final session = _sessions.snapshot(clientId);
    final currentPeer = session?.webRtcPeer;
    if (closeWebRtc && currentPeer != null) {
      if (gateway == null) {
        return <Object>[
          StateError(
            'The current WebRTC peer cannot be closed without its gateway.',
          ),
        ];
      }
      try {
        await _closeWebRtcPeerStrict(
          gateway,
          clientId: clientId,
          peerId: currentPeer.peerId,
        );
      } catch (error) {
        // Keep the session and its exact lease authoritative. A retry or the
        // peer lifecycle event can finish cleanup without risking a successor.
        return <Object>[error];
      }
    }
    if (currentPeer != null) {
      final retired = _sessions.takeWebRtcPeer(
        clientId,
        peerId: currentPeer.peerId,
      );
      retired?.release();
    }
    _sessionController.stopActiveSession(clientId);
    final removedSession = _sessions.remove(clientId);
    final ownedRuntimeSession = removedSession?.runtimeOwned ?? false;
    _updateResourceWatchdog();

    final cleanup = BestEffortOperationCollector();
    Future<void> boundedAttempt(
      String label,
      FutureOr<void> Function() operation,
    ) =>
        cleanup.attempt(
          label,
          () => Future<void>.sync(() async {
            await operation();
          }).timeout(webRtcCleanupTimeout),
        );

    await Future.wait([
      boundedAttempt(
        'video stream client',
        () => _videoStreamService.closeClient(clientId),
      ),
      boundedAttempt(
        'audio stream client',
        () => _audioStreamService.closeClient(clientId),
      ),
      if (ownedRuntimeSession)
        if (onStreamSessionStopped case final callback?)
          boundedAttempt(
            'media runtime session',
            () => callback(clientId),
          )
        else
          boundedAttempt(
            'standalone media demand',
            _reconcileStandaloneSessionDemand,
          ),
      boundedAttempt('broadcast access session', () async {
        final accessSnapshot = await _broadcastAccess?.endSession(
          _broadcastAccessSessionId(clientId),
        );
        _notifyBroadcastAccessChanged(accessSnapshot);
        _scheduleBroadcastAccessTimer(accessSnapshot);
      }),
    ]);
    if (_activeClientRegistry.activeClientCount > 0) {
      await boundedAttempt(
        'remaining client media profile',
        _applyMediaProfileForCurrentDemand,
      );
    }
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
    var available = gateway.isAvailable;
    if (!available) {
      try {
        available =
            await gateway.initialize().timeout(webRtcNegotiationTimeout);
      } catch (error) {
        onLog('WebRTC initialization failed: $error');
        available = false;
      }
    }
    if (!available) {
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

class _StaleWebRtcOffer implements Exception {
  const _StaleWebRtcOffer();
}

class _StaleWebRtcPeerOwnership implements Exception {
  const _StaleWebRtcPeerOwnership();
}
