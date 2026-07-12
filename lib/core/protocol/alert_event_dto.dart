import '../media/adaptive_media_profile.dart';
import '../../l10n/app_strings.dart';

enum AlertCategory { audio, motion, system }

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
      this.snapshotAvailable,
      this.battery,
      this.transport,
      this.childId,
      this.metadata = const {}});
  final String id;
  final String type;
  final String severity;
  final String messageKey;
  final String message;
  final double score;
  final int timestampMs;
  final String sourceDeviceId;
  final bool? snapshotAvailable;
  final Map<String, Object?>? battery;
  final String? transport;
  final String? childId;
  final Map<String, Object?> metadata;

  AlertCategory get category {
    final normalizedType = type.trim().toLowerCase();
    final normalizedMessageKey = messageKey.trim().toLowerCase();

    if (const {
          'motiondetected',
          'globallightchange',
        }.contains(normalizedType) ||
        const {
          'parentmotionalert',
          'parentlightchangealert',
        }.contains(normalizedMessageKey)) {
      return AlertCategory.motion;
    }

    if (const {
      'systemwarning',
      'batterylow',
    }.contains(normalizedType)) {
      return AlertCategory.system;
    }

    if (const {
          'crydetected',
          'loudsound',
          'legacyalert',
        }.contains(normalizedType) ||
        const {
          'parentcryalert',
          'parentloudsoundalert',
          'parentepisodehighcryalert',
          'parentepisodeshortsoundalert',
          'parentepisodecryalert',
          'legacyalert',
        }.contains(normalizedMessageKey)) {
      return AlertCategory.audio;
    }

    return AlertCategory.system;
  }

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
        if (snapshotAvailable != null) 'snapshotAvailable': snapshotAvailable,
        if (battery != null) 'battery': battery,
        if (transport != null) 'transport': transport,
        if (childId != null) 'childId': childId,
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
    final battery = json['battery'];
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
      snapshotAvailable: json['snapshotAvailable'] is bool
          ? json['snapshotAvailable'] as bool
          : null,
      battery: battery is Map ? Map<String, Object?>.from(battery) : null,
      transport: json['transport']?.toString(),
      childId: json['childId']?.toString(),
      metadata: Map<String, Object?>.from(metadata),
    );
  }

  String localizedMessage(AppStrings strings) {
    // A newer client may receive an older/server-side event with a message key
    // but without the feature metadata needed to rebuild it. Never replace a
    // valid server message with a template filled with zeroes.
    if (!_hasLocalizationMetadata) return message;
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

  bool get _hasLocalizationMetadata {
    switch (messageKey) {
      case 'parentCryAlert':
        return _hasAll(const [
          'confidencePercent',
          'ambientDeltaDb',
          'cryBandPercent',
          'isCalibrated',
        ]);
      case 'parentLoudSoundAlert':
        return _hasAll(const ['dbfs', 'ambientDeltaDb']);
      case 'parentMotionAlert':
        return _hasAll(const ['scorePercent', 'activeAreaPercent', 'meanDiff']);
      case 'parentLightChangeAlert':
        return _hasAll(const ['scorePercent', 'globalLumaShift']);
      case 'parentEpisodeHighCryAlert':
        return _hasAll(const ['durationMs', 'networkTier']);
      case 'parentEpisodeShortSoundAlert':
      case 'parentEpisodeCryAlert':
        return _hasAll(const ['durationMs']);
      default:
        return true;
    }
  }

  bool _hasAll(List<String> keys) => keys.every(metadata.containsKey);

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
