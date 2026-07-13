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

  void updateStrings(AppStrings strings) {
    _strings = strings;
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
    );
    _lastDelivery = delivery;
    return delivery;
  }

  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) {
    final strings = _strings;
    return show(
      strings == null
          ? alert.message
          : alert.localizedNotificationBody(strings),
      alertId: alert.id,
      title: strings?.alertNotificationTitle(
        type: alert.type,
        messageKey: alert.messageKey,
      ),
      severity: alert.severity,
    );
  }
}
