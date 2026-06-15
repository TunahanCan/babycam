import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() => _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ));

  Future<void> showAlert(String message) => _plugin.show(
        2001,
        'BabyCam uyarısı',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'babycam_alerts',
            'BabyCam Uyarıları',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
}
