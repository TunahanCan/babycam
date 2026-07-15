import '../../../core/async/serialized_async_executor.dart';
import '../../../core/protocol/alert_event_dto.dart';
import 'client_alert_history.dart';
import 'client_notification_service.dart';

/// Serializes one server alert into the two parent-facing destinations:
/// in-app history and the platform notification surface.
class ClientAlertDeliveryCoordinator {
  ClientAlertDeliveryCoordinator({
    required ClientAlertHistory history,
    required ClientNotificationService notifications,
  })  : _history = history,
        _notifications = notifications;

  final ClientAlertHistory _history;
  final ClientNotificationService _notifications;
  final _operations = SerializedAsyncExecutor();

  Future<void> deliver(AlertEventDto alert) => _operations.run(() async {
        try {
          await _history.add(alert);
        } catch (_) {
          // A storage failure must not suppress the phone notification.
        }
        await _notifications.showAlert(alert);
      });

  Future<void> drain() => _operations.drain();
}
