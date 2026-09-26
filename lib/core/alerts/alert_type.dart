/// User-facing families shared by analysis, transport, and parent history.
enum AlertCategory { audio, motion, system }

/// Structured event types emitted by the analysis engine.
///
/// Wire values are explicit because saved history and older peers must remain
/// readable even if a Dart identifier is renamed later.
enum AlertType {
  cryDetected('cryDetected', AlertCategory.audio),
  motionDetected('motionDetected', AlertCategory.motion),
  loudSound('loudSound', AlertCategory.audio),
  globalLightChange('globalLightChange', AlertCategory.motion),
  systemWarning('systemWarning', AlertCategory.system);

  const AlertType(this.wireValue, this.category);

  final String wireValue;
  final AlertCategory category;

  static final _byWireValue = {
    for (final type in values) type.wireValue.toLowerCase(): type,
  };

  static AlertType? tryParse(String value) =>
      _byWireValue[value.trim().toLowerCase()];
}
