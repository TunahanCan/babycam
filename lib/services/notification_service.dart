import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_strings.dart';

class NotificationService {
  NotificationService(this._strings);

  final AppStrings _strings;
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<bool> initialize() async {
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? await android.areNotificationsEnabled() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    return true;
  }

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
