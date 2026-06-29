import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_strings.dart';

class NotificationService {
  NotificationService(this._strings);

  static const _channelId = 'mimicam_alerts';
  static const _payloadAlerts = 'mimicam://alerts';

  final AppStrings _strings;
  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;
  var _enabled = false;

  Future<bool> initialize() async {
    if (_initialized) return _enabled;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentAlert: true,
          defaultPresentBadge: true,
          defaultPresentSound: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
        ),
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        _channelId,
        _strings.notificationChannelName,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ));
      final granted = await android.requestNotificationsPermission();
      _enabled = granted ?? await android.areNotificationsEnabled() ?? true;
      _initialized = true;
      return _enabled;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      _enabled = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
      _initialized = true;
      return _enabled;
    }
    _enabled = true;
    _initialized = true;
    return _enabled;
  }

  Future<void> showAlert(String message) {
    if (!_enabled) return Future<void>.value();
    return _plugin.show(
      2001,
      _strings.notificationTitle,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _strings.notificationChannelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          channelShowBadge: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
          threadIdentifier: _channelId,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: _payloadAlerts,
    );
  }
}
