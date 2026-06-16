import 'dart:io';

import '../../core/media/adaptive_media_profile.dart';

class DeviceCapabilityProbe {
  const DeviceCapabilityProbe._();

  static DeviceCapabilityTier detectTier({int? processorCount}) {
    final processors = processorCount ?? Platform.numberOfProcessors;
    if (processors <= 4) return DeviceCapabilityTier.legacy;
    if (processors <= 6) return DeviceCapabilityTier.balanced;
    return DeviceCapabilityTier.modern;
  }
}
