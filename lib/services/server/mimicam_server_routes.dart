part of '../mimicam_server.dart';

List<_RouteSpec> _buildMimiCamRoutes(MimiCamServer server) => [
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.pairConfirm,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handlePairConfirm(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.authRenew,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleAuthRenew(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.sessionStart,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleSessionStart(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.sessionStop,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleSessionStop(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.webRtcOffer,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleWebRtcOffer,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.webRtcIce,
        _AuthMode.bearer,
        const {HttpMethod.get, HttpMethod.post},
        server._handleWebRtcIce,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.webRtcClose,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleWebRtcClose,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.qualityReport,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleQualityReport(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.comfortState,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handleComfortState(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.comfortCommand,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleComfortCommand(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.nightLightState,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handleNightLightState(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.nightLightCommand,
        _AuthMode.bearer,
        const {HttpMethod.post},
        (request, _) => server._handleNightLightCommand(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.talkStart,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleTalkStart,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.talkStop,
        _AuthMode.bearer,
        const {HttpMethod.post},
        server._handleTalkStop,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.talkAudio,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleTalkAudio(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.talkVideo,
        _AuthMode.none,
        const {HttpMethod.post},
        (request, _) => server._handleTalkVideo(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.statusPublic,
        _AuthMode.none,
        const {HttpMethod.get},
        (request, _) => server._handlePublicStatus(request),
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.video,
        _AuthMode.streamToken,
        const {HttpMethod.get},
        server._handleVideoRoute,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.audio,
        _AuthMode.streamToken,
        const {HttpMethod.get},
        server._handleAudioRoute,
      ),
      _RouteSpec(
        protocol_v2.MimiCamProtocolV2.status,
        _AuthMode.bearer,
        const {HttpMethod.get},
        (request, _) => server._handlePrivateStatus(request),
      ),
    ];
