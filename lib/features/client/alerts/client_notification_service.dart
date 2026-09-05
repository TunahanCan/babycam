import '../../../core/protocol/alert_event_dto.dart';
import '../../../services/notification_service.dart';
import '../../../l10n/app_strings.dart';

class ClientNotificationService {
  ClientNotificationService({NotificationService? service})
      : _service = service;

  NotificationService? _service;
  NotificationDeliveryReceipt? _lastDelivery;

  NotificationDeliveryReceipt? get lastDelivery => _lastDelivery;

  void updateStrings(AppStrings strings) {
    final service = _service;
    if (service == null) {
      _service = NotificationService(strings);
    } else {
      service.updateStrings(strings);
    }
  }

  Future<bool> initialize({AppStrings? strings}) async {
    if (strings != null) {
      updateStrings(strings);
    }
    final service = _service;
    if (service == null) return false;
    return service.initialize();
  }

  Future<NotificationDeliveryReceipt> show(
    String message, {
    required String alertId,
    String? title,
    String severity = 'warning',
    String Function(AppStrings)? messageBuilder,
    String Function(AppStrings)? titleBuilder,
  }) async {
    final service = _service;
    if (service == null) {
      return NotificationDeliveryReceipt(
        notificationId: NotificationService.notificationIdFor(alertId),
        posted: false,
        error: 'notification_service_not_initialized',
      );
    }
    final delivery = await service.showAlert(
      message,
      alertId: alertId,
      title: title,
      severity: severity,
      messageBuilder: messageBuilder,
      titleBuilder: titleBuilder,
    );
    _lastDelivery = delivery;
    return delivery;
  }

  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) {
    return show(
      alert.message,
      alertId: alert.id,
      messageBuilder: alert.localizedNotificationBody,
      titleBuilder: alert.localizedTitle,
      severity: alert.severity,
    );
  }
}
