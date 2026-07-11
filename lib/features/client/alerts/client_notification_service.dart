import '../../../core/protocol/alert_event_dto.dart';
import '../../../services/notification_service.dart';
import '../../../l10n/app_strings.dart';

class ClientNotificationService {
  ClientNotificationService({NotificationService? service})
      : _service = service;

  NotificationService? _service;
  AppStrings? _strings;
  NotificationDeliveryReceipt? _lastDelivery;

  NotificationDeliveryReceipt? get lastDelivery => _lastDelivery;

  Future<bool> initialize({AppStrings? strings}) async {
    if (strings != null) {
      _strings = strings;
      _service ??= NotificationService(strings);
    }
    final service = _service;
    if (service == null) return false;
    return service.initialize();
  }

  Future<NotificationDeliveryReceipt> show(
    String message, {
    required String alertId,
  }) async {
    final service = _service;
    if (service == null) {
      return NotificationDeliveryReceipt(
        notificationId: NotificationService.notificationIdFor(alertId),
        posted: false,
        error: 'notification_service_not_initialized',
      );
    }
    final delivery = await service.showAlert(message, alertId: alertId);
    _lastDelivery = delivery;
    return delivery;
  }

  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) {
    final strings = _strings;
    return show(
      strings == null ? alert.message : alert.localizedMessage(strings),
      alertId: alert.id,
    );
  }
}
