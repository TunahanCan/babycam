import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/notification_service.dart';

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
    expect(plugin.lastTitle, 'MimiCam alert');
    expect(plugin.lastBody, 'Baby is crying');
    expect(plugin.lastPayload, 'mimicam://alerts?alertId=cry+alert%2F1');
    expect(android?.channelId, NotificationService.channelId);
    expect(android?.importance, Importance.high);
    expect(android?.priority, Priority.high);
    expect(android?.category, AndroidNotificationCategory.message);
    expect(android?.playSound, isTrue);
    expect(android?.enableVibration, isTrue);
    expect(android?.autoCancel, isTrue);
    expect(android?.groupKey, isNotEmpty);
    expect(android?.styleInformation, isA<BigTextStyleInformation>());
  });

  test('notification tap stream accepts only MimiCam alert payloads', () async {
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
      payload: 'mimicam://alerts?alertId=motion-1',
    ));

    expect(await nextTap, 'mimicam://alerts?alertId=motion-1');
    NotificationService.takePendingTap();
  });

  test('retained engine refresh reads and deduplicates Activity launch tap',
      () async {
    const payload = 'mimicam://alerts?alertId=retained-engine-1';
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
  });

  final Future<bool?>? initialization;
  final bool? initializationResult;
  final bool reportPostedNotificationAsActive;
  final Object? showError;
  final NotificationAppLaunchDetails? launchDetails;

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
    // NotificationService resolves platform-specific permission handlers. A
    // null implementation models a platform where no extra permission API is
    // exposed, while keeping this fake independent from plugin internals.
    return null;
  }
}
