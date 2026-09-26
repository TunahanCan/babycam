import 'alert_type.dart';

/// Semantic message identifiers carried by alert JSON and persisted history.
enum AlertMessageKey {
  cry('parentCryAlert', AlertType.cryDetected),
  loudSound('parentLoudSoundAlert', AlertType.loudSound),
  motion('parentMotionAlert', AlertType.motionDetected),
  lightChange('parentLightChangeAlert', AlertType.globalLightChange),
  highCryEpisode('parentEpisodeHighCryAlert', AlertType.cryDetected),
  shortSoundEpisode('parentEpisodeShortSoundAlert', AlertType.loudSound),
  cryEpisode('parentEpisodeCryAlert', AlertType.cryDetected),
  batteryLow('batteryLow'),
  legacy('legacyAlert');

  const AlertMessageKey(this.wireValue, [this.typeOverride]);

  final String wireValue;
  final AlertType? typeOverride;

  String? get presentationType =>
      typeOverride?.wireValue ?? (this == batteryLow ? wireValue : null);

  /// Detailed localization historically requires an exact wire identifier.
  static AlertMessageKey? tryParse(String value) => _byWireValue[value];

  /// Category/title interpretation also supports older case-varied keys.
  static AlertMessageKey? tryParseNormalized(String value) =>
      _byNormalizedWireValue[value.trim().toLowerCase()];

  static final _byWireValue = {
    for (final key in values) key.wireValue: key,
  };
  static final _byNormalizedWireValue = {
    for (final key in values) key.wireValue.toLowerCase(): key,
  };

  static AlertMessageKey forType(AlertType type) => switch (type) {
        AlertType.cryDetected => cry,
        AlertType.motionDetected => motion,
        AlertType.loudSound => loudSound,
        AlertType.globalLightChange => lightChange,
        AlertType.systemWarning => legacy,
      };
}
