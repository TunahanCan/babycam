import 'alert_severity.dart';
import 'alert_type.dart';

/// Structured, transport-agnostic alert generated from analysis results.
class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.score,
    required this.timestampMs,
    this.metadata = const {},
  });

  final String id;
  final AlertType type;
  final AlertSeverity severity;
  final String message;
  final double score;
  final int timestampMs;
  final Map<String, Object?> metadata;

  /// Converts this alert into a JSON-friendly map.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'severity': severity.name,
        'message': message,
        'score': score,
        'timestampMs': timestampMs,
        'metadata': metadata,
      };
}
