import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_strings.dart';

class NotificationDeliveryReceipt {
  const NotificationDeliveryReceipt({
    required this.notificationId,
    required this.posted,
    this.verifiedActive,
    this.error,
  });

  final int notificationId;
  final bool posted;
  final bool? verifiedActive;
  final String? error;
}

class NotificationService {
  NotificationService(
    this._strings, {
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'miucam_alerts';
  static const updatesChannelId = 'miucam_room_updates';
  static const alertsPayload = 'miucam://alerts';
  static const _groupKey = 'miucam_alerts_group';
  // iOS groups notifications by this exact thread identifier. Keep it
  // independent of the Android channel name so a future Android rename cannot
  // silently split the parent alert stack on iPhone.
  static const iosAlertThreadIdentifier = 'miucam.parent-alerts';
  static final _notificationTaps = StreamController<String>.broadcast();
  static String? _pendingTap;
  static String? _lastPublishedTap;

  static Stream<String> get notificationTaps => _notificationTaps.stream;

  /// Returns a notification tap that launched the app before navigation was
  /// ready. Live consumers should also call this after handling a stream event
  /// so a later Client screen does not replay the same tap.
  static String? takePendingTap() {
    final payload = _pendingTap;
    _pendingTap = null;
    return payload;
  }

  /// Re-reads the Activity launch intent after Android reattaches a retained
  /// Flutter engine. In that lifecycle shape the notifications plugin does not
  /// emit its regular response callback because the Activity is new rather
  /// than receiving `onNewIntent`.
  static Future<void> refreshLaunchTap({
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    if (!_supportsNativeNotifications) return;
    try {
      final details = await (plugin ?? FlutterLocalNotificationsPlugin())
          .getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp == true) {
        _publishNotificationTap(details?.notificationResponse?.payload);
      }
    } catch (_) {
      // A lifecycle refresh is best effort; initialization still owns errors.
    }
  }

  AppStrings _strings;
  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initializing;
  var _pluginInitialized = false;
  var _enabled = false;
  var _notificationsAttempted = 0;
  var _notificationsPosted = 0;
  String? _lastError;

  bool get enabled => _enabled;
  int get notificationsAttempted => _notificationsAttempted;
  int get notificationsPosted => _notificationsPosted;
  String? get lastError => _lastError;

  void updateStrings(AppStrings strings) {
    _strings = strings;
  }

  Future<bool> initialize() {
    final active = _initializing;
    if (active != null) return active;
    final operation = _initialize();
    _initializing = operation;
    return operation.whenComplete(() {
      if (identical(_initializing, operation)) _initializing = null;
    });
  }

  Future<bool> _initialize() async {
    try {
      if (!_supportsNativeNotifications) {
        _pluginInitialized = true;
        _enabled = true;
        _lastError = null;
        return true;
      }
      if (!_pluginInitialized) {
        final initialized = await _plugin.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_miucam'),
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
          onDidReceiveNotificationResponse: (response) {
            _publishNotificationTap(response.payload);
          },
        );
        if (initialized == false) {
          _enabled = false;
          _lastError = 'notification_plugin_initialization_failed';
          return false;
        }
        _pluginInitialized = true;
        final launchDetails = await _plugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp == true) {
          _publishNotificationTap(launchDetails?.notificationResponse?.payload);
        }
      }
      _enabled = await _requestOrRefreshPermission();
      _lastError = _enabled ? null : 'notification_permission_denied';
      return _enabled;
    } catch (error) {
      _enabled = false;
      _lastError = error.toString();
      return false;
    }
  }

  Future<bool> _requestOrRefreshPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        channelId,
        _strings.notificationChannelName,
        description: _strings.ui('notificationChannelDescription'),
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ));
      await android.createNotificationChannel(AndroidNotificationChannel(
        updatesChannelId,
        _strings.notificationUpdatesChannelName,
        description: _strings.ui('notificationChannelDescription'),
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      ));
      final alreadyEnabled = await android.areNotificationsEnabled();
      if (alreadyEnabled == true) return true;
      final granted = await android.requestNotificationsPermission();
      return granted ?? await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<NotificationDeliveryReceipt> showAlert(
    String message, {
    required String alertId,
    String? title,
    String severity = 'warning',
  }) async {
    final notificationId = notificationIdFor(alertId);
    _notificationsAttempted++;
    if (!await initialize()) {
      return NotificationDeliveryReceipt(
        notificationId: notificationId,
        posted: false,
        error: _lastError ?? 'notification_permission_denied',
      );
    }
    if (!_supportsNativeNotifications) {
      return NotificationDeliveryReceipt(
        notificationId: notificationId,
        posted: false,
        error: 'native_notifications_unsupported',
      );
    }

    try {
      final contentTitle = title ?? _strings.notificationTitle;
      final interruptive = _isInterruptive(severity);
      await _plugin.show(
        notificationId,
        contentTitle,
        message,
        NotificationDetails(
          android: AndroidNotificationDetails(
            interruptive ? channelId : updatesChannelId,
            interruptive
                ? _strings.notificationChannelName
                : _strings.notificationUpdatesChannelName,
            channelDescription: _strings.ui('notificationChannelDescription'),
            icon: 'ic_stat_miucam',
            importance:
                interruptive ? Importance.high : Importance.defaultImportance,
            priority: interruptive ? Priority.high : Priority.defaultPriority,
            playSound: interruptive,
            enableVibration: interruptive,
            channelShowBadge: true,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.private,
            groupKey: _groupKey,
            autoCancel: true,
            onlyAlertOnce: false,
            ticker: contentTitle,
            styleInformation: BigTextStyleInformation(
              message,
              contentTitle: contentTitle,
              summaryText: 'MiuCam',
            ),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: interruptive,
            presentBanner: true,
            presentList: true,
            // This is the iOS Notification Center grouping contract. Every
            // parent alert retains its own notification id while sharing one
            // thread, so iOS shows a single MiuCam stack instead of a noisy
            // list of independent banners.
            threadIdentifier: iosAlertThreadIdentifier,
            interruptionLevel: interruptive
                ? InterruptionLevel.active
                : InterruptionLevel.passive,
          ),
        ),
        payload: '$alertsPayload?alertId=${Uri.encodeQueryComponent(alertId)}',
      );
      final verifiedActive = await _verifyActive(notificationId);
      _notificationsPosted++;
      _lastError = null;
      return NotificationDeliveryReceipt(
        notificationId: notificationId,
        posted: true,
        verifiedActive: verifiedActive,
      );
    } catch (error) {
      _lastError = error.toString();
      return NotificationDeliveryReceipt(
        notificationId: notificationId,
        posted: false,
        error: _lastError,
      );
    }
  }

  bool _isInterruptive(String severity) {
    final normalized = severity.trim().toLowerCase();
    return normalized == 'attention' ||
        normalized == 'warning' ||
        normalized == 'critical' ||
        normalized == 'high' ||
        normalized == 'medium';
  }

  Future<bool?> _verifyActive(int notificationId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final active = await _plugin.getActiveNotifications();
      return active.any((notification) => notification.id == notificationId);
    } catch (_) {
      return null;
    }
  }

  static int notificationIdFor(String alertId) {
    var hash = 0x811C9DC5;
    for (final codeUnit in alertId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return 10000 + (hash % 2000000000);
  }

  static bool get _supportsNativeNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void _publishNotificationTap(String? payload) {
    if (payload == null || !payload.startsWith(alertsPayload)) return;
    if (_lastPublishedTap == payload) return;
    _lastPublishedTap = payload;
    _pendingTap = payload;
    _notificationTaps.add(payload);
  }
}
