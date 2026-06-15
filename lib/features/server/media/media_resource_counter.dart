class MediaResourceCounter {
  int activeVideoClients = 0;
  int activeAudioClients = 0;
  int activeEventClients = 0;
  bool wantsCryDetection = false;
  bool wantsMotionDetection = false;

  bool get needsVideoCapture => activeVideoClients > 0 || wantsMotionDetection;
  bool get needsAudioCapture => activeAudioClients > 0 || wantsCryDetection;
  bool get needsVideoEncoding => activeVideoClients > 0;
  bool get needsAudioStreaming => activeAudioClients > 0;
  bool get hasLiveWatch => activeVideoClients > 0 || activeAudioClients > 0;
  bool get hasNotificationDemand => wantsCryDetection || wantsMotionDetection || activeEventClients > 0;
}
