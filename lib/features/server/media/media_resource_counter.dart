class MediaResourceCounter {
  int activeVideoClients = 0;
  int activeAudioClients = 0;
  int externalVideoClients = 0;
  int externalAudioClients = 0;
  int activeEventClients = 0;
  bool localPreviewActive = false;
  bool wantsCryDetection = false;
  bool wantsMotionDetection = false;

  bool get needsVideoCapture =>
      localPreviewActive ||
      activeVideoClients > externalVideoClients ||
      wantsMotionDetection;
  bool get needsAudioCapture =>
      activeAudioClients > externalAudioClients || wantsCryDetection;
  bool get needsVideoEncoding =>
      localPreviewActive || activeVideoClients > externalVideoClients;
  bool get needsAudioStreaming => activeAudioClients > 0;
  bool get hasLiveWatch => activeVideoClients > 0 || activeAudioClients > 0;
  bool get hasNotificationDemand =>
      wantsCryDetection || wantsMotionDetection || activeEventClients > 0;
}
