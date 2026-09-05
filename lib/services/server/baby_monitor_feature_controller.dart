import 'dart:async';
import 'dart:typed_data';

import '../../core/protocol/device_feature_models.dart';
import 'baby_monitor_feature_services.dart';
import 'room_audio_coordinator.dart';

class TalkAudioWriteResult {
  const TalkAudioWriteResult({
    required this.session,
    required this.played,
  });

  final TalkSession? session;
  final bool played;
}

/// Facade for room-side comfort, light and talk features. HTTP routing remains
/// transport-only; device output ownership lives here.
class BabyMonitorFeatureController {
  BabyMonitorFeatureController({
    ComfortAudioService? comfortAudio,
    NightLightController? nightLight,
    TalkSessionRegistry? talkSessions,
    RoomAudioCoordinator? roomAudio,
  })  : comfortAudio = comfortAudio ?? ComfortAudioService(),
        nightLight = nightLight ?? NightLightController(),
        talkSessions = talkSessions ?? TalkSessionRegistry(),
        roomAudio = roomAudio ?? RoomAudioCoordinator() {
    _comfortFailureSubscription =
        this.roomAudio.comfortPlaybackFailures.listen((error) {
      if (!_disposed && this.comfortAudio.state.playing) {
        this.comfortAudio.markPlaybackFailed(error);
      }
    });
  }

  final ComfortAudioService comfortAudio;
  final NightLightController nightLight;
  final TalkSessionRegistry talkSessions;
  final RoomAudioCoordinator roomAudio;
  late final StreamSubscription<Object> _comfortFailureSubscription;
  Timer? _talkExpiryTimer;
  bool _disposed = false;

  Future<ComfortAudioState> applyComfortCommand(
    Map<Object?, Object?>? command,
  ) async {
    final state = comfortAudio.applyCommand(command);
    try {
      await roomAudio.applyComfort(
        playing: state.playing,
        trackId: state.trackId,
        volume: state.volume,
      );
      return state;
    } catch (error) {
      return comfortAudio.markPlaybackFailed(error);
    }
  }

  Future<TalkSession> startTalk({
    required String clientId,
    String? attemptId,
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    final session = talkSessions.start(
      clientId: clientId,
      attemptId: attemptId,
    );
    try {
      await roomAudio.beginTalk(
        sampleRate: sampleRate.clamp(8000, 48000),
        channels: channels.clamp(1, 2),
      );
      final stillOwnsTalk = talkSessions.activeSession?.token == session.token;
      final cancelled = attemptId != null &&
          talkSessions.isAttemptCancelled(clientId, attemptId);
      if (!stillOwnsTalk || cancelled) {
        if (stillOwnsTalk) {
          await stopTalk(
            clientId: clientId,
            token: session.token,
            attemptId: attemptId,
          );
        }
        throw const TalkSessionCancelledException();
      }
    } catch (_) {
      talkSessions.stop(
        clientId: clientId,
        token: session.token,
        attemptId: attemptId,
      );
      rethrow;
    }
    _scheduleTalkExpiry(session);
    return session;
  }

  Future<bool> stopTalk({
    required String clientId,
    String? token,
    String? attemptId,
  }) async {
    final stopped = talkSessions.stop(
      clientId: clientId,
      token: token,
      attemptId: attemptId,
    );
    if (!stopped) return false;
    _talkExpiryTimer?.cancel();
    _talkExpiryTimer = null;
    await roomAudio.endTalk();
    return true;
  }

  Future<TalkAudioWriteResult> acceptTalkAudio(
    String token,
    Uint8List bytes,
  ) async {
    final session = talkSessions.recordAudio(token, bytes);
    if (session == null) {
      // A late chunk from an older upload must not preempt a newer talk
      // generation. Only stop native output when no authoritative session
      // remains.
      if (talkSessions.activeSession == null) await roomAudio.endTalk();
      return const TalkAudioWriteResult(session: null, played: false);
    }
    _scheduleTalkExpiry(session);
    final played = await roomAudio.writeTalk(bytes);
    return TalkAudioWriteResult(session: session, played: played);
  }

  TalkSession? acceptTalkVideo(String token, Uint8List bytes) {
    final session = talkSessions.recordVideo(token, bytes);
    if (session != null) _scheduleTalkExpiry(session);
    return session;
  }

  bool isTalkTokenActive(String token) => talkSessions.isTokenActive(token);

  Map<String, Object?> talkStatus() {
    final active = talkSessions.activeSession;
    return {
      'active': active != null,
      'audioCodec': 'pcm_s16le',
      'sampleRate': roomAudio.sampleRate,
      'channels': roomAudio.channels,
      'videoSupported': false,
      'outputMode': roomAudio.mode.name,
      if (active != null) 'session': active.toJson(),
    };
  }

  Future<void> handleAudioOutputLost(String reason) async {
    _talkExpiryTimer?.cancel();
    _talkExpiryTimer = null;
    final active = talkSessions.activeSession;
    if (active != null) {
      talkSessions.stop(clientId: active.clientId, token: active.token);
    }
    if (comfortAudio.state.playing) {
      comfortAudio.markPlaybackFailed(reason);
    }
    await roomAudio.handleOutputLost();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _talkExpiryTimer?.cancel();
    _talkExpiryTimer = null;
    await _comfortFailureSubscription.cancel();
    await roomAudio.dispose();
  }

  void _scheduleTalkExpiry(TalkSession session) {
    _talkExpiryTimer?.cancel();
    final delay = Duration(
      milliseconds:
          (session.expiresAtMs - DateTime.now().millisecondsSinceEpoch)
              .clamp(0, talkSessions.sessionTtl.inMilliseconds),
    );
    _talkExpiryTimer = Timer(delay, () {
      if (_disposed) return;
      final active = talkSessions.activeSession;
      if (active == null || active.token == session.token) {
        unawaited(roomAudio.endTalk());
      }
    });
  }
}
