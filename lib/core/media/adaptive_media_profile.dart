enum DeviceCapabilityTier {
  legacy,
  balanced,
  modern;

  String get label => switch (this) {
        DeviceCapabilityTier.legacy => 'Eski cihaz',
        DeviceCapabilityTier.balanced => 'Dengeli cihaz',
        DeviceCapabilityTier.modern => 'Yeni cihaz',
      };
}

enum NetworkQualityTier {
  unknown,
  excellent,
  good,
  weak,
  critical,
  offline;

  String get label => switch (this) {
        NetworkQualityTier.unknown => 'Ölçülüyor',
        NetworkQualityTier.excellent => 'Çok iyi',
        NetworkQualityTier.good => 'İyi',
        NetworkQualityTier.weak => 'Zayıf',
        NetworkQualityTier.critical => 'Kritik',
        NetworkQualityTier.offline => 'Çevrim dışı',
      };

  bool get shouldPreferAudio =>
      this == NetworkQualityTier.weak ||
      this == NetworkQualityTier.critical ||
      this == NetworkQualityTier.offline;

  static NetworkQualityTier fromName(String? value) =>
      NetworkQualityTier.values.firstWhere(
        (tier) => tier.name == value,
        orElse: () => NetworkQualityTier.unknown,
      );
}

class MediaQualityProfile {
  const MediaQualityProfile({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    required this.targetFps,
    required this.jpegQuality,
    required this.cameraPresetKey,
    required this.audioCodec,
    required this.preferredAudioCodec,
    required this.videoCodec,
    required this.preferredVideoCodec,
    this.audioFirst = false,
  });

  final String id;
  final String label;
  final int width;
  final int height;
  final int targetFps;
  final int jpegQuality;
  final String cameraPresetKey;
  final String audioCodec;
  final String preferredAudioCodec;
  final String videoCodec;
  final String preferredVideoCodec;
  final bool audioFirst;

  Duration get frameInterval =>
      Duration(milliseconds: (1000 / targetFps).round());

  String get summary =>
      '$label · ${width}x$height · ${targetFps}fps · JPG $jpegQuality';

  static MediaQualityProfile forDeviceTier(DeviceCapabilityTier tier) =>
      switch (tier) {
        DeviceCapabilityTier.legacy => const MediaQualityProfile(
            id: 'compat_360p',
            label: 'Uyumluluk',
            width: 640,
            height: 360,
            targetFps: 8,
            jpegQuality: 54,
            cameraPresetKey: 'low',
            audioCodec: 'pcm16le',
            preferredAudioCodec: 'opus',
            videoCodec: 'mjpeg',
            preferredVideoCodec: 'h264-webrtc',
            audioFirst: true,
          ),
        DeviceCapabilityTier.balanced => const MediaQualityProfile(
            id: 'balanced_480p',
            label: 'Dengeli',
            width: 854,
            height: 480,
            targetFps: 10,
            jpegQuality: 62,
            cameraPresetKey: 'medium',
            audioCodec: 'pcm16le',
            preferredAudioCodec: 'opus',
            videoCodec: 'mjpeg',
            preferredVideoCodec: 'h264-webrtc',
          ),
        DeviceCapabilityTier.modern => const MediaQualityProfile(
            id: 'quality_720p',
            label: 'Kaliteli',
            width: 1280,
            height: 720,
            targetFps: 15,
            jpegQuality: 70,
            cameraPresetKey: 'high',
            audioCodec: 'pcm16le',
            preferredAudioCodec: 'opus',
            videoCodec: 'mjpeg',
            preferredVideoCodec: 'h264-webrtc',
          ),
      };

  MediaQualityProfile adaptForNetwork(NetworkQualityTier tier) {
    final baseIsLegacy = cameraPresetKey == 'low';
    return switch (tier) {
      NetworkQualityTier.unknown || NetworkQualityTier.excellent => this,
      NetworkQualityTier.good => copyWith(
          id: '${id}_good',
          label: '$label / stabil',
          targetFps: targetFps.clamp(8, 12),
          jpegQuality: jpegQuality.clamp(56, 68),
        ),
      NetworkQualityTier.weak => copyWith(
          id: 'audio_first_360p',
          label: 'Ses öncelikli',
          width: baseIsLegacy ? width : 640,
          height: baseIsLegacy ? height : 360,
          targetFps: 7,
          jpegQuality: 50,
          cameraPresetKey: baseIsLegacy ? cameraPresetKey : 'low',
          audioFirst: true,
        ),
      NetworkQualityTier.critical || NetworkQualityTier.offline => copyWith(
          id: 'survival_audio_first',
          label: 'Kritik ağ',
          width: 480,
          height: 270,
          targetFps: 4,
          jpegQuality: 42,
          cameraPresetKey: 'low',
          audioFirst: true,
        ),
    };
  }

  MediaQualityProfile copyWith({
    String? id,
    String? label,
    int? width,
    int? height,
    int? targetFps,
    int? jpegQuality,
    String? cameraPresetKey,
    String? audioCodec,
    String? preferredAudioCodec,
    String? videoCodec,
    String? preferredVideoCodec,
    bool? audioFirst,
  }) =>
      MediaQualityProfile(
        id: id ?? this.id,
        label: label ?? this.label,
        width: width ?? this.width,
        height: height ?? this.height,
        targetFps: targetFps ?? this.targetFps,
        jpegQuality: jpegQuality ?? this.jpegQuality,
        cameraPresetKey: cameraPresetKey ?? this.cameraPresetKey,
        audioCodec: audioCodec ?? this.audioCodec,
        preferredAudioCodec: preferredAudioCodec ?? this.preferredAudioCodec,
        videoCodec: videoCodec ?? this.videoCodec,
        preferredVideoCodec: preferredVideoCodec ?? this.preferredVideoCodec,
        audioFirst: audioFirst ?? this.audioFirst,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'width': width,
        'height': height,
        'targetFps': targetFps,
        'jpegQuality': jpegQuality,
        'cameraPresetKey': cameraPresetKey,
        'audioCodec': audioCodec,
        'preferredAudioCodec': preferredAudioCodec,
        'videoCodec': videoCodec,
        'preferredVideoCodec': preferredVideoCodec,
        'audioFirst': audioFirst,
      };

  static MediaQualityProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, Object?>.from(value);
    final id = json['id'];
    final label = json['label'];
    final width = json['width'];
    final height = json['height'];
    final targetFps = json['targetFps'];
    final jpegQuality = json['jpegQuality'];
    final cameraPresetKey = json['cameraPresetKey'];
    final audioCodec = json['audioCodec'];
    final preferredAudioCodec = json['preferredAudioCodec'];
    final videoCodec = json['videoCodec'];
    final preferredVideoCodec = json['preferredVideoCodec'];
    final audioFirst = json['audioFirst'] ?? false;
    if (id is! String ||
        label is! String ||
        width is! int ||
        height is! int ||
        targetFps is! int ||
        jpegQuality is! int ||
        cameraPresetKey is! String ||
        audioCodec is! String ||
        preferredAudioCodec is! String ||
        videoCodec is! String ||
        preferredVideoCodec is! String ||
        audioFirst is! bool) {
      return null;
    }
    return MediaQualityProfile(
      id: id,
      label: label,
      width: width,
      height: height,
      targetFps: targetFps,
      jpegQuality: jpegQuality,
      cameraPresetKey: cameraPresetKey,
      audioCodec: audioCodec,
      preferredAudioCodec: preferredAudioCodec,
      videoCodec: videoCodec,
      preferredVideoCodec: preferredVideoCodec,
      audioFirst: audioFirst,
    );
  }
}

class NetworkQualitySnapshot {
  const NetworkQualitySnapshot({
    required this.tier,
    required this.measuredAtMs,
    this.rttMs,
    this.consecutiveFailures = 0,
  });

  final NetworkQualityTier tier;
  final int measuredAtMs;
  final int? rttMs;
  final int consecutiveFailures;

  static NetworkQualitySnapshot unknown() => NetworkQualitySnapshot(
        tier: NetworkQualityTier.unknown,
        measuredAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  String get summary {
    final rtt = rttMs == null ? '' : ' · ${rttMs}ms';
    return '${tier.label}$rtt';
  }

  Map<String, Object?> toJson() => {
        'tier': tier.name,
        'measuredAtMs': measuredAtMs,
        'rttMs': rttMs,
        'consecutiveFailures': consecutiveFailures,
      };
}

class NetworkQualityClassifier {
  const NetworkQualityClassifier();

  NetworkQualityTier classify({int? rttMs, int consecutiveFailures = 0}) {
    if (consecutiveFailures >= 3) return NetworkQualityTier.offline;
    if (consecutiveFailures >= 2) return NetworkQualityTier.critical;
    final rtt = rttMs;
    if (rtt == null) return NetworkQualityTier.unknown;
    if (rtt >= 900) return NetworkQualityTier.critical;
    if (rtt >= 450) return NetworkQualityTier.weak;
    if (rtt >= 220) return NetworkQualityTier.good;
    return NetworkQualityTier.excellent;
  }
}

class NetworkQualityUpdate {
  const NetworkQualityUpdate({
    required this.snapshot,
    this.serverProfile,
  });

  final NetworkQualitySnapshot snapshot;
  final MediaQualityProfile? serverProfile;
}
