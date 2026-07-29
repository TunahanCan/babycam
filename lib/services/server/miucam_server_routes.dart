part of '../miucam_server.dart';

List<_RouteSpec> _buildMiuCamRoutes(MiuCamServer server) => [
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.pairConfirm,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handlePairConfirm(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.authRenew,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleAuthRenew(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.sessionStart,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleSessionStart(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.sessionStop,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleSessionStop(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.webRtcOffer,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleWebRtcOffer,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.webRtcIce,
        _AuthMode.bearer,
        const {HttpMethod.get, HttpMethod.post},
        server._handleWebRtcIce,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.webRtcClose,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleWebRtcClose,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.qualityReport,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleQualityReport(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.comfortState,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handleComfortState(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.comfortCommand,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleComfortCommand(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.nightLightState,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handleNightLightState(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.nightLightCommand,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleNightLightCommand(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.talkStart,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleTalkStart,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.talkStop,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleTalkStop,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.talkAudio,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleTalkAudio(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.talkVideo,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleTalkVideo(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.statusPublic,
        _AuthMode.none,
        const {HttpMethod.get},
        (request, _) => server._handlePublicStatus(request),
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.video,
        _AuthMode.streamToken,
        const {HttpMethod.get},
        server._handleVideoRoute,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.audio,
        _AuthMode.streamToken,
        const {HttpMethod.get},
        server._handleAudioRoute,
      ),
      _RouteSpec(
        protocol_v2.MiuCamProtocolV2.status,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handlePrivateStatus(request),
      ),
    ];
