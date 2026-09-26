import '../media/adaptive_media_profile.dart';
import '../alerts/alert_message_key.dart';
import '../alerts/alert_severity.dart';
import '../alerts/alert_type.dart';
import '../../l10n/app_strings.dart';

export '../alerts/alert_type.dart' show AlertCategory;

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

  // Keep raw strings above intact for unknown peers and persisted history.
  // Interpretation is typed without normalizing or rewriting wire data.
  AlertType? get knownType => AlertType.tryParse(type);
  AlertSeverity? get knownSeverity => AlertSeverity.tryParse(severity);
  AlertMessageKey? get knownMessageKey => AlertMessageKey.tryParse(messageKey);

  String get _presentationType =>
      AlertMessageKey.tryParseNormalized(messageKey)?.presentationType ?? type;

  AlertCategory get category {
    final normalizedType = _presentationType.trim().toLowerCase();
    final category = AlertType.tryParse(normalizedType)?.category;
    if (category != null) return category;
    if (normalizedType == AlertMessageKey.batteryLow.wireValue.toLowerCase()) {
      return AlertCategory.system;
    }
    if (normalizedType == AlertMessageKey.legacy.wireValue.toLowerCase() ||
        AlertMessageKey.tryParseNormalized(messageKey) ==
            AlertMessageKey.legacy) {
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
    // Wire/history retain the original text for compatibility. Presentation
    // always belongs to the receiving parent's locale, including old events
    // without measurements. Never fabricate zero-valued analysis details.
    if (!_hasLocalizationMetadata) return _localizedFallback(strings);
    return switch (knownMessageKey) {
      AlertMessageKey.cry => strings.parentCryAlert(
          confidencePercent: _int('confidencePercent'),
          ambientDeltaDb: _double('ambientDeltaDb'),
          cryBandPercent: _int('cryBandPercent'),
          calibrated: _bool('isCalibrated'),
        ),
      AlertMessageKey.loudSound => strings.parentLoudSoundAlert(
          dbfs: _double('dbfs'),
          ambientDeltaDb: _double('ambientDeltaDb'),
        ),
      AlertMessageKey.motion => strings.parentMotionAlert(
          scorePercent: _int('scorePercent'),
          activeAreaPercent: _int('activeAreaPercent'),
          meanDiff: _double('meanDiff'),
        ),
      AlertMessageKey.lightChange => strings.parentLightChangeAlert(
          scorePercent: _int('scorePercent'),
          lumaShift: _double('globalLumaShift'),
        ),
      AlertMessageKey.highCryEpisode => strings.parentEpisodeHighCryAlert(
          seconds: _durationSeconds(),
          motionAgo: strings.parentMotionAgo(_intOrNull('lastMotionAgoMs')),
          networkTier: strings.networkQualityLabel(_networkTier()),
        ),
      AlertMessageKey.shortSoundEpisode => strings.parentEpisodeShortSoundAlert(
          seconds: _durationSeconds(),
        ),
      AlertMessageKey.cryEpisode => strings.parentEpisodeCryAlert(
          seconds: _durationSeconds(),
          networkTier: strings.networkQualityLabel(_networkTier()),
        ),
      _ => _localizedFallback(strings),
    };
  }

  String _localizedFallback(AppStrings strings) =>
      strings.alertNotificationBody(
          type: _presentationType, messageKey: messageKey) ??
      strings.alertDetailsUnavailable;

  String localizedTitle(AppStrings strings) => strings.alertNotificationTitle(
        type: _presentationType,
        messageKey: messageKey,
      );

  String localizedNotificationBody(AppStrings strings) =>
      strings.alertNotificationBody(
          type: _presentationType, messageKey: messageKey) ??
      localizedMessage(strings);

  bool get _hasLocalizationMetadata {
    switch (knownMessageKey) {
      case AlertMessageKey.cry:
        return _isNumber('confidencePercent', min: 0, max: 100) &&
            _isNumber('ambientDeltaDb', min: -200, max: 200) &&
            _isNumber('cryBandPercent', min: 0, max: 100) &&
            metadata['isCalibrated'] is bool;
      case AlertMessageKey.loudSound:
        return _isNumber('dbfs', min: -200, max: 20) &&
            _isNumber('ambientDeltaDb', min: -200, max: 200);
      case AlertMessageKey.motion:
        return _isNumber('scorePercent', min: 0, max: 100) &&
            _isNumber('activeAreaPercent', min: 0, max: 100) &&
            _isNumber('meanDiff', min: 0, max: 255);
      case AlertMessageKey.lightChange:
        return _isNumber('scorePercent', min: 0, max: 100) &&
            _isNumber('globalLumaShift', min: -255, max: 255);
      case AlertMessageKey.highCryEpisode:
        return _isDuration('durationMs') &&
            _isNetworkTier('networkTier') &&
            _isOptionalNumber('lastMotionAgoMs', min: 0, max: 86400000);
      case AlertMessageKey.shortSoundEpisode:
        return _isDuration('durationMs');
      case AlertMessageKey.cryEpisode:
        return _isDuration('durationMs') && _isNetworkTier('networkTier');
      default:
        return true;
    }
  }

  bool _isDuration(String key) => _isNumber(key, min: 0, max: 86400000);

  bool _isNetworkTier(String key) {
    final value = metadata[key];
    return value is String &&
        NetworkQualityTier.values.any((tier) => tier.name == value);
  }

  bool _isOptionalNumber(
    String key, {
    required num min,
    required num max,
  }) =>
      !metadata.containsKey(key) ||
      metadata[key] == null ||
      _isNumber(key, min: min, max: max);

  bool _isNumber(
    String key, {
    required num min,
    required num max,
  }) {
    final value = metadata[key];
    return value is num && value.isFinite && value >= min && value <= max;
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
      NetworkQualityTier.fromName(metadata['networkTier'] is String
          ? metadata['networkTier'] as String
          : null);
}
