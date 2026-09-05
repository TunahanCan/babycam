import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/features/client/alerts/client_alert_delivery_coordinator.dart';
import 'package:miucam/features/client/alerts/client_alert_history.dart';
import 'package:miucam/features/client/alerts/client_notification_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('notification ids are deterministic, distinct, and Android-safe', () {
    final first = NotificationService.notificationIdFor('alert-001');
    final same = NotificationService.notificationIdFor('alert-001');
    final second = NotificationService.notificationIdFor('alert-002');

    expect(first, same);
    expect(second, isNot(first));
    expect(first, inInclusiveRange(10000, 2000009999));
    expect(second, inInclusiveRange(10000, 2000009999));
  });

  test('first alert waits for plugin initialization before it is posted',
      () async {
    final initialization = Completer<bool?>();
    final plugin = _FakeNotificationsPlugin(
      initialization: initialization.future,
      reportPostedNotificationAsActive: true,
    );
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    final delivery = service.showAlert(
      'Motion detected',
      alertId: 'motion-1',
    );

    expect(plugin.initializeCalls, 1);
    expect(plugin.showCalls, 0);
    expect(service.notificationsAttempted, 1);

    initialization.complete(true);
    final receipt = await delivery;

    expect(receipt.posted, isTrue);
    expect(receipt.verifiedActive, isTrue);
    expect(plugin.showCalls, 1);
    expect(service.notificationsPosted, 1);
    expect(service.lastError, isNull);
  });

  test('concurrent alerts share initialization and keep separate ids',
      () async {
    final initialization = Completer<bool?>();
    final plugin = _FakeNotificationsPlugin(
      initialization: initialization.future,
    );
    final service = NotificationService(
      AppStrings(const Locale('tr')),
      plugin: plugin,
    );

    final first = service.showAlert('İlk uyarı', alertId: 'alert-a');
    final second = service.showAlert('İkinci uyarı', alertId: 'alert-b');

    expect(plugin.initializeCalls, 1);
    expect(plugin.showCalls, 0);

    initialization.complete(true);
    final receipts = await Future.wait([first, second]);

    expect(plugin.initializeCalls, 1);
    expect(plugin.showCalls, 2);
    expect(receipts.map((receipt) => receipt.notificationId).toSet(),
        hasLength(2));
    expect(receipts.every((receipt) => receipt.posted), isTrue);
  });

  test('initialization failure returns a failed receipt without posting',
      () async {
    final plugin = _FakeNotificationsPlugin(initializationResult: false);
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    final receipt = await service.showAlert(
      'This must not be posted',
      alertId: 'permission-denied',
    );

    expect(receipt.posted, isFalse);
    expect(receipt.error, 'notification_plugin_initialization_failed');
    expect(plugin.showCalls, 0);
    expect(service.enabled, isFalse);
    expect(service.notificationsAttempted, 1);
    expect(service.notificationsPosted, 0);
  });

  test('posting error is exposed through receipt and service diagnostics',
      () async {
    final plugin = _FakeNotificationsPlugin(showError: StateError('boom'));
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    final receipt = await service.showAlert(
      'Motion detected',
      alertId: 'post-error',
    );

    expect(receipt.posted, isFalse);
    expect(receipt.error, contains('boom'));
    expect(service.lastError, contains('boom'));
    expect(service.notificationsAttempted, 1);
    expect(service.notificationsPosted, 0);
  });

  test('disabled Android channel is permanent without blocking other channels',
      () async {
    final plugin = _FakeNotificationsPlugin(
      android: _FakeAndroidNotifications(),
    );
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    final blocked = await service.showAlert('Cry detected', alertId: 'cry');
    expect(blocked.posted, isFalse);
    expect(blocked.error, 'notification_channel_disabled');
    expect(plugin.showCalls, 0);

    final allowed = await service.showAlert(
      'Motion detected',
      alertId: 'motion',
      severity: 'info',
    );
    expect(allowed.posted, isTrue);
    expect(plugin.showCalls, 1);
    expect(plugin.lastDetails?.android?.channelId,
        NotificationService.updatesChannelId);
  });

  test('Android alert uses message semantics and a deep-link payload',
      () async {
    final plugin = _FakeNotificationsPlugin();
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    final receipt = await service.showAlert(
      'Baby is crying',
      alertId: 'cry alert/1',
    );
    final android = plugin.lastDetails?.android;

    expect(receipt.posted, isTrue);
    expect(plugin.lastTitle, 'MiuCam · Nursery');
    expect(plugin.lastBody, 'Baby is crying');
    expect(plugin.lastPayload, 'miucam://alerts?alertId=cry+alert%2F1');
    expect(android?.channelId, NotificationService.channelId);
    expect(android?.importance, Importance.high);
    expect(android?.priority, Priority.high);
    expect(android?.category, AndroidNotificationCategory.message);
    expect(android?.visibility, NotificationVisibility.private);
    expect(android?.playSound, isTrue);
    expect(android?.enableVibration, isTrue);
    expect(android?.autoCancel, isTrue);
    expect(android?.onlyAlertOnce, isTrue);
    expect(android?.groupKey, isNotEmpty);
    expect(android?.styleInformation, isA<BigTextStyleInformation>());
  });

  test('informational room updates are quiet and keep their typed title',
      () async {
    final plugin = _FakeNotificationsPlugin();
    final service = NotificationService(
      AppStrings(AppStrings.fallbackLocale),
      plugin: plugin,
    );

    final receipt = await service.showAlert(
      'Mom, there is movement in the nursery view.',
      alertId: 'motion-info-1',
      title: 'Movement detected in the nursery',
      severity: 'info',
    );
    final android = plugin.lastDetails?.android;

    expect(receipt.posted, isTrue);
    expect(plugin.lastTitle, 'Movement detected in the nursery');
    expect(android?.channelId, NotificationService.updatesChannelId);
    expect(android?.importance, Importance.defaultImportance);
    expect(android?.priority, Priority.defaultPriority);
    expect(android?.playSound, isFalse);
    expect(android?.enableVibration, isFalse);
  });

  test('iOS parent alerts share one Notification Center thread', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final plugin = _FakeNotificationsPlugin();
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );

    await service.showAlert('First room alert', alertId: 'ios-alert-1');
    final first = plugin.lastDetails?.iOS;
    await service.showAlert('Second room alert', alertId: 'ios-alert-2');
    final second = plugin.lastDetails?.iOS;

    expect(
        first?.threadIdentifier, NotificationService.iosAlertThreadIdentifier);
    expect(
        second?.threadIdentifier, NotificationService.iosAlertThreadIdentifier);
    expect(second?.badgeNumber, isNull);
    expect(second?.presentList, isTrue);
  });

  test('iOS informational update uses passive interruption without sound',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final plugin = _FakeNotificationsPlugin();
    final service = NotificationService(
      AppStrings(AppStrings.fallbackLocale),
      plugin: plugin,
    );

    await service.showAlert(
      'Mom, the nursery light may have changed.',
      alertId: 'ios-light-info',
      title: 'The nursery light changed',
      severity: 'info',
    );
    final details = plugin.lastDetails?.iOS;

    expect(details?.interruptionLevel, InterruptionLevel.passive);
    expect(details?.presentSound, isFalse);
  });

  test('active client notification copy follows a runtime locale change',
      () async {
    final plugin = _FakeNotificationsPlugin();
    final nativeService = NotificationService(
      AppStrings(AppStrings.fallbackLocale),
      plugin: plugin,
    );
    final service = ClientNotificationService(service: nativeService);
    const alert = AlertEventDto(
      id: 'locale-motion',
      type: 'motionDetected',
      severity: 'info',
      messageKey: 'parentMotionAlert',
      message: 'Motion detected',
      score: .7,
      timestampMs: 42,
      sourceDeviceId: 'server',
      metadata: {
        'scorePercent': 70,
        'activeAreaPercent': 14,
        'meanDiff': 8.2,
      },
    );

    await service.initialize(strings: AppStrings(AppStrings.fallbackLocale));
    await service.showAlert(alert);
    expect(plugin.lastTitle, 'Movement detected in the nursery');
    expect(plugin.lastBody, startsWith('Mom,'));

    service.updateStrings(AppStrings(const Locale('tr')));
    await service.showAlert(alert);
    expect(plugin.lastTitle, 'Bebek odasında hareket var');
    expect(plugin.lastBody, startsWith('Anne,'));
  });

  for (final locale in AppStrings.supportedLocales) {
    test('injected client notifications use parent locale $locale', () async {
      final plugin = _FakeNotificationsPlugin();
      final strings = AppStrings(locale);
      final service = ClientNotificationService(
        service: NotificationService(strings, plugin: plugin),
      );
      // Replay/storage retains the original wire text. It must never override
      // the selected parent locale, including when metadata was not retained.
      for (final event in const [
        ('cryDetected', 'parentCryAlert'),
        ('loudSound', 'parentLoudSoundAlert'),
        ('motionDetected', 'parentMotionAlert'),
        ('globalLightChange', 'parentLightChangeAlert'),
        ('cryDetected', 'parentEpisodeHighCryAlert'),
        ('loudSound', 'parentEpisodeShortSoundAlert'),
        ('cryDetected', 'parentEpisodeCryAlert'),
      ]) {
        final alert = AlertEventDto(
          id: '${locale.toLanguageTag()}-${event.$2}',
          type: event.$1,
          severity: 'warning',
          messageKey: event.$2,
          message: 'SERVER LANGUAGE MUST NOT LEAK',
          score: .7,
          timestampMs: 42,
          sourceDeviceId: 'server',
        );
        final restored = AlertEventDto.fromJson(alert.toJson())!;
        final receipt = await service.showAlert(restored);
        expect(receipt.posted, isTrue);
        expect(plugin.lastTitle, restored.localizedTitle(strings));
        expect(plugin.lastBody, restored.localizedNotificationBody(strings));
        expect(plugin.lastBody, isNot(contains('SERVER LANGUAGE')));
        expect(plugin.lastDetails?.android?.channelName,
            strings.notificationChannelName);
      }
    });
  }

  test('queued alert uses locale selected while plugin permission waits',
      () async {
    final initialization = Completer<bool?>();
    final plugin = _FakeNotificationsPlugin(
      initialization: initialization.future,
    );
    final service = ClientNotificationService(
      service:
          NotificationService(AppStrings(const Locale('en')), plugin: plugin),
    );
    const alert = AlertEventDto(
      id: 'queued-locale',
      type: 'motionDetected',
      severity: 'info',
      messageKey: 'parentMotionAlert',
      message: 'SERVER LANGUAGE MUST NOT LEAK',
      score: .7,
      timestampMs: 42,
      sourceDeviceId: 'server',
    );
    final pending = service.showAlert(alert);
    service.updateStrings(AppStrings(const Locale('tr')));
    initialization.complete(true);
    expect((await pending).posted, isTrue);
    expect(plugin.lastTitle, 'Bebek odasında hareket var');
    expect(plugin.lastBody, startsWith('Anne,'));
    expect(plugin.lastDetails?.android?.channelName,
        AppStrings(const Locale('tr')).notificationUpdatesChannelName);
  });

  test('pending replay after restart uses new parent language exactly once',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final originalHistory = ClientAlertHistory(preferences: preferences);
    final restoredHistory = ClientAlertHistory(preferences: preferences);
    addTearDown(originalHistory.dispose);
    addTearDown(restoredHistory.dispose);
    const alert = AlertEventDto(
      id: 'restart-locale',
      type: 'cryDetected',
      severity: 'warning',
      messageKey: 'parentCryAlert',
      message: 'SERVER LANGUAGE MUST NOT LEAK',
      score: .7,
      timestampMs: 42,
      sourceDeviceId: 'server',
    );
    final initialDelivery = ClientAlertDeliveryCoordinator(
      history: originalHistory,
      notifications: ClientNotificationService(
        service: NotificationService(
          AppStrings(const Locale('tr')),
          plugin:
              _FakeNotificationsPlugin(showError: StateError('interrupted')),
        ),
      ),
    );
    await expectLater(initialDelivery.deliver(alert), throwsStateError);
    await restoredHistory.load();
    expect(restoredHistory.isNotificationPending(alert.id), isTrue);
    final plugin =
        _FakeNotificationsPlugin(reportPostedNotificationAsActive: true);
    final strings = AppStrings(const Locale('fr'));
    final restoredDelivery = ClientAlertDeliveryCoordinator(
      history: restoredHistory,
      notifications: ClientNotificationService(
        service: NotificationService(strings, plugin: plugin),
      ),
    );
    final replayed = restoredHistory.alerts.single;
    await restoredDelivery.deliver(replayed);
    await restoredDelivery.deliver(replayed);
    expect(plugin.showCalls, 1);
    expect(plugin.lastBody, alert.localizedNotificationBody(strings));
    expect(plugin.lastBody, isNot(contains('SERVER LANGUAGE')));
    expect(restoredHistory.isNotificationPending(alert.id), isFalse);
  });

  test('locale change immediately relabels channels without another alert',
      () async {
    final android = _FakeAndroidNotifications();
    final plugin = _FakeNotificationsPlugin(android: android);
    final service =
        NotificationService(AppStrings(const Locale('en')), plugin: plugin);
    expect(await service.initialize(), isTrue);
    final tr = AppStrings(const Locale('tr'));
    final ar = AppStrings(const Locale('ar', 'QA'));
    service.updateStrings(tr);
    service.updateStrings(ar);
    await Future<void>.delayed(Duration.zero);
    expect(android.createdChannels[NotificationService.channelId]?.name,
        ar.notificationChannelName);
    expect(android.createdChannels[NotificationService.updatesChannelId]?.name,
        ar.notificationUpdatesChannelName);
    expect(android.createdChannels[NotificationService.channelId]?.description,
        ar.ui('notificationChannelDescription'));
    expect(android.permissionRequests, 0);
    expect(plugin.showCalls, 0);
  });

  test('notification tap stream accepts only MiuCam alert payloads', () async {
    final plugin = _FakeNotificationsPlugin();
    final service = NotificationService(
      AppStrings(const Locale('en')),
      plugin: plugin,
    );
    await service.initialize();

    final nextTap = NotificationService.notificationTaps.first;
    plugin.notificationResponse?.call(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'other-app://alerts',
    ));
    plugin.notificationResponse?.call(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'miucam://alerts?alertId=motion-1',
    ));

    expect(await nextTap, 'miucam://alerts?alertId=motion-1');
    NotificationService.takePendingTap();
  });

  test('retained engine refresh reads and deduplicates Activity launch tap',
      () async {
    const payload = 'miucam://alerts?alertId=retained-engine-1';
    final plugin = _FakeNotificationsPlugin(
      launchDetails: const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: 42,
          payload: payload,
        ),
      ),
    );
    final received = <String>[];
    final subscription = NotificationService.notificationTaps.listen(
      received.add,
    );
    addTearDown(subscription.cancel);

    await NotificationService.refreshLaunchTap(plugin: plugin);
    await NotificationService.refreshLaunchTap(plugin: plugin);
    await Future<void>.delayed(Duration.zero);

    expect(received, [payload]);
    expect(NotificationService.takePendingTap(), payload);
  });
}

class _FakeNotificationsPlugin implements FlutterLocalNotificationsPlugin {
  _FakeNotificationsPlugin({
    this.initialization,
    this.initializationResult = true,
    this.reportPostedNotificationAsActive = false,
    this.showError,
    this.launchDetails = const NotificationAppLaunchDetails(false),
    this.android,
  });

  final Future<bool?>? initialization;
  final bool? initializationResult;
  final bool reportPostedNotificationAsActive;
  final Object? showError;
  final NotificationAppLaunchDetails? launchDetails;
  final AndroidFlutterLocalNotificationsPlugin? android;

  int initializeCalls = 0;
  int showCalls = 0;
  int? lastId;
  String? lastTitle;
  String? lastBody;
  String? lastPayload;
  NotificationDetails? lastDetails;
  DidReceiveNotificationResponseCallback? notificationResponse;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) {
    initializeCalls++;
    notificationResponse = onDidReceiveNotificationResponse;
    return initialization ?? Future<bool?>.value(initializationResult);
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    return launchDetails;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    showCalls++;
    lastId = id;
    lastTitle = title;
    lastBody = body;
    lastDetails = notificationDetails;
    lastPayload = payload;
    if (showError != null) throw showError!;
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async {
    if (!reportPostedNotificationAsActive || lastId == null) return const [];
    return [ActiveNotification(id: lastId)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #resolvePlatformSpecificImplementation &&
        invocation.typeArguments.single ==
            AndroidFlutterLocalNotificationsPlugin) {
      return android;
    }
    // NotificationService resolves platform-specific permission handlers. A
    // null implementation models a platform where no extra permission API is
    // exposed, while keeping this fake independent from plugin internals.
    return null;
  }
}

class _FakeAndroidNotifications
    implements AndroidFlutterLocalNotificationsPlugin {
  final createdChannels = <String, AndroidNotificationChannel>{};
  int permissionRequests = 0;

  @override
  Future<void> createNotificationChannel(
      AndroidNotificationChannel notificationChannel) async {
    createdChannels[notificationChannel.id] = notificationChannel;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<List<AndroidNotificationChannel>?> getNotificationChannels() async => [
        const AndroidNotificationChannel(
          NotificationService.channelId,
          'Alerts',
          importance: Importance.none,
        ),
        const AndroidNotificationChannel(
          NotificationService.updatesChannelId,
          'Updates',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
