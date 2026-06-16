import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_strings.dart';

class NotificationService {
  NotificationService(this._strings);

  final AppStrings _strings;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() => _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ));

  Future<void> showAlert(String message) => _plugin.show(
        2001,
        _strings.notificationTitle,
        message,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'mimicam_alerts',
            _strings.notificationChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
}
