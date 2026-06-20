import '../../../services/notification_service.dart';
import '../../../l10n/app_strings.dart';

class ClientNotificationService {
  NotificationService? _service;
  Future<void> initialize({AppStrings? strings}) async {
    if (strings == null || _service != null) return;
    _service = NotificationService(strings);
    await _service!.initialize();
  }

  Future<void> show(String message) async => _service?.showAlert(message);
}
