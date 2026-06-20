import '../../core/media/adaptive_media_profile.dart';

class MediaQualitySelector {
  const MediaQualitySelector();

  MediaQualityProfile select({
    required DeviceCapabilityTier deviceTier,
    required NetworkQualityTier networkTier,
    required int activeClientCount,
  }) =>
      MediaQualityProfile.forDeviceTier(deviceTier)
          .adaptForNetwork(networkTier)
          .adaptForClientLoad(activeClientCount);
}
