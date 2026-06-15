import '../../../core/protocol/alert_event_dto.dart';

class ClientAlertHistory {
  final alerts = <AlertEventDto>[];
  void add(AlertEventDto alert) => alerts.insert(0, alert);
}
