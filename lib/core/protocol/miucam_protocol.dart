class MiuCamProtocolV2 {
  // Version 2 makes operation-attempt ownership mandatory for stream and
  // talk lifecycle safety. Version-1 peers are intentionally rejected at
  // pairing so a staged update cannot reintroduce stop-before-start races.
  static const schemaVersion = 2;
  static const pairConfirm = '/pair/confirm';
  static const authRenew = '/auth/renew';
  static const sessionStart = '/session/start';
  static const sessionStop = '/session/stop';
  static const streamAttemptId = 'streamAttemptId';
  static const invalidStreamAttemptIdCode = 'INVALID_STREAM_ATTEMPT_ID';
  static const qualityReport = '/quality/report';
  static const comfortState = '/comfort/state';
  static const comfortCommand = '/comfort/command';
  static const nightLightState = '/night-light/state';
  static const nightLightCommand = '/night-light/command';
  static const talkStart = '/talk/start';
  static const talkStop = '/talk/stop';
  static const talkAudio = '/talk/audio';
  static const talkVideo = '/talk/video';
  static const talkAttemptId = 'talkAttemptId';
  static const invalidTalkAttemptIdCode = 'INVALID_TALK_ATTEMPT_ID';
  static const video = '/video';
  static const audio = '/audio';
  static const webRtcOffer = '/webrtc/offer';
  static const webRtcIce = '/webrtc/ice';
  static const webRtcClose = '/webrtc/close';
  static const events = '/ws/events';
  static const alertReplayVersionQuery = 'alertReplayV';
  static const alertReplayVersion = '1';
  static const alertCursorQuery = 'afterAlertId';
  static const alertAckType = 'alertAck';
  static const alertAckId = 'alertId';
  static const alertDetachType = 'alertDetach';
  static const status = '/status';
  static const statusPublic = '/status/public';
}
