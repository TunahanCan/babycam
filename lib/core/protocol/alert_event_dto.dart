import '../media/adaptive_media_profile.dart';
import '../../l10n/app_strings.dart';

class AlertEventDto {
  const AlertEventDto(
      {required this.id,
      required this.type,
      required this.severity,
      required this.messageKey,
      required this.message,
      required this.score,
      required this.timestampMs,
      required this.sourceDeviceId,
      this.metadata = const {}});
  final String id;
  final String type;
  final String severity;
  final String messageKey;
  final String message;
  final double score;
  final int timestampMs;
  final String sourceDeviceId;
  final Map<String, Object?> metadata;
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'type': type,
        'severity': severity,
        'messageKey': messageKey,
        'message': message,
        'score': score,
        'timestampMs': timestampMs,
        'sourceDeviceId': sourceDeviceId,
        'metadata': metadata
      };

  static AlertEventDto? fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final id = json['id'];
    final type = json['type'];
    final severity = json['severity'];
    final messageKey = json['messageKey'];
    final message = json['message'];
    final score = json['score'];
    final timestampMs = json['timestampMs'];
    final sourceDeviceId = json['sourceDeviceId'];
    final metadata = json['metadata'];
    if (schemaVersion != 1 ||
        id is! String ||
        type is! String ||
        severity is! String ||
        messageKey is! String ||
        message is! String ||
        score is! num ||
        timestampMs is! int ||
        sourceDeviceId is! String ||
        metadata is! Map) {
      return null;
    }
    return AlertEventDto(
      id: id,
      type: type,
      severity: severity,
      messageKey: messageKey,
      message: message,
      score: score.toDouble(),
      timestampMs: timestampMs,
      sourceDeviceId: sourceDeviceId,
      metadata: Map<String, Object?>.from(metadata),
    );
  }

  String localizedMessage(AppStrings strings) {
    return switch (messageKey) {
      'parentCryAlert' => strings.parentCryAlert(
          confidencePercent: _int('confidencePercent'),
          ambientDeltaDb: _double('ambientDeltaDb'),
          cryBandPercent: _int('cryBandPercent'),
          calibrated: _bool('isCalibrated'),
        ),
      'parentLoudSoundAlert' => strings.parentLoudSoundAlert(
          dbfs: _double('dbfs'),
          ambientDeltaDb: _double('ambientDeltaDb'),
        ),
      'parentMotionAlert' => strings.parentMotionAlert(
          scorePercent: _int('scorePercent'),
          activeAreaPercent: _int('activeAreaPercent'),
          meanDiff: _double('meanDiff'),
        ),
      'parentLightChangeAlert' => strings.parentLightChangeAlert(
          scorePercent: _int('scorePercent'),
          lumaShift: _double('globalLumaShift'),
        ),
      'parentEpisodeHighCryAlert' => strings.parentEpisodeHighCryAlert(
          seconds: _durationSeconds(),
          motionAgo: strings.parentMotionAgo(_intOrNull('lastMotionAgoMs')),
          networkTier: strings.networkQualityLabel(_networkTier()),
        ),
      'parentEpisodeShortSoundAlert' => strings.parentEpisodeShortSoundAlert(
          seconds: _durationSeconds(),
        ),
      'parentEpisodeCryAlert' => strings.parentEpisodeCryAlert(
          seconds: _durationSeconds(),
          networkTier: strings.networkQualityLabel(_networkTier()),
        ),
      _ => message,
    };
  }

  int _int(String key) {
    final value = metadata[key];
    return value is num ? value.round() : 0;
  }

  int? _intOrNull(String key) {
    final value = metadata[key];
    return value is num ? value.round() : null;
  }

  double _double(String key) {
    final value = metadata[key];
    return value is num ? value.toDouble() : 0;
  }

  bool _bool(String key) => metadata[key] == true;

  int _durationSeconds() => (_int('durationMs') / 1000).round();

  NetworkQualityTier _networkTier() =>
      NetworkQualityTier.fromName(metadata['networkTier'] as String?);
}
