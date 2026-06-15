import 'alert_type.dart';

/// Tracks per-alert-type cooldown windows after emitted alerts.
class CooldownPolicy {
  CooldownPolicy({required Map<AlertType, int> cooldownMsByType})
      : _cooldownMsByType = Map.unmodifiable(cooldownMsByType);

  final Map<AlertType, int> _cooldownMsByType;
  final Map<AlertType, int> _lastEmittedAtByType = {};

  /// Returns true when [type] can be emitted at [timestampMs].
  bool canEmit(AlertType type, int timestampMs) =>
      remainingMs(type, timestampMs) == 0;

  /// Records that [type] was emitted at [timestampMs].
  void markEmitted(AlertType type, int timestampMs) {
    _lastEmittedAtByType[type] = timestampMs;
  }

  /// Returns remaining cooldown in milliseconds, or zero if none remains.
  int remainingMs(AlertType type, int timestampMs) {
    final cooldownMs = _cooldownMsByType[type] ?? 0;
    if (cooldownMs <= 0) {
      return 0;
    }

    final lastEmittedAt = _lastEmittedAtByType[type];
    if (lastEmittedAt == null) {
      return 0;
    }

    final elapsedMs = timestampMs - lastEmittedAt;
    if (elapsedMs < 0) {
      return cooldownMs;
    }

    final remaining = cooldownMs - elapsedMs;
    return remaining > 0 ? remaining : 0;
  }

  /// Clears cooldown state for [type], or all cooldown state when omitted.
  void reset([AlertType? type]) {
    if (type == null) {
      _lastEmittedAtByType.clear();
    } else {
      _lastEmittedAtByType.remove(type);
    }
  }
}
