class AlertEventDto {
  const AlertEventDto({required this.id, required this.type, required this.severity, required this.messageKey, required this.message, required this.score, required this.timestampMs, required this.sourceDeviceId, this.metadata = const {}});
  final String id;
  final String type;
  final String severity;
  final String messageKey;
  final String message;
  final double score;
  final int timestampMs;
  final String sourceDeviceId;
  final Map<String, Object?> metadata;
  Map<String, Object?> toJson() => {'schemaVersion': 1, 'id': id, 'type': type, 'severity': severity, 'messageKey': messageKey, 'message': message, 'score': score, 'timestampMs': timestampMs, 'sourceDeviceId': sourceDeviceId, 'metadata': metadata};
}
