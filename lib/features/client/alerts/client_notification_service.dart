import '../../../core/protocol/alert_event_dto.dart';
import '../../../services/notification_service.dart';
import '../../../l10n/app_strings.dart';

class ClientNotificationService {
  NotificationService? _service;
  AppStrings? _strings;

  Future<void> initialize({AppStrings? strings}) async {
    if (strings == null) return;
    _strings = strings;
    if (_service != null) return;
    _service = NotificationService(strings);
    await _service!.initialize();
  }

  Future<void> show(String message) async => _service?.showAlert(message);

  Future<void> showAlert(AlertEventDto alert) async {
    final strings = _strings;
    await _service?.showAlert(
      strings == null ? alert.message : alert.localizedMessage(strings),
    );
  }
}
