import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/features/client/alerts/client_alert_delivery_coordinator.dart';
import 'package:miucam/features/client/alerts/client_alert_history.dart';
import 'package:miucam/features/client/alerts/client_notification_service.dart';
import 'package:miucam/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/failing_alert_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('denied notifications require a saved fallback before acknowledging',
      () async {
    final preferences = FailingAlertPreferences()..failWrites = true;
    final history = ClientAlertHistory(preferences: preferences);
    final notifications = _PermanentFailureNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'permission-and-storage-failure');

    await expectLater(delivery.deliver(alert), throwsStateError);
    expect(history.alerts.single.id, alert.id);
    expect(history.isNotificationPending(alert.id), isTrue);
    expect(preferences.saved, isEmpty);

    preferences.failWrites = false;
    await delivery.deliver(alert);
    expect(preferences.writeAttempts, greaterThanOrEqualTo(2));
    final restored = ClientAlertHistory(preferences: preferences);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.alerts.single.id, alert.id);
    expect(restored.isNotificationPending(alert.id), isFalse);

    await ClientAlertDeliveryCoordinator(
      history: restored,
      notifications: notifications,
    ).deliver(alert);
    expect(notifications.calls, 2);
  });

  test('failed native notification remains retryable after process restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final original = ClientAlertHistory(preferences: preferences);
    final restored = ClientAlertHistory(preferences: preferences);
    final completed = ClientAlertHistory(preferences: preferences);
    addTearDown(original.dispose);
    addTearDown(restored.dispose);
    addTearDown(completed.dispose);
    final alert = _alert(id: 'interrupted-platform-delivery');
    final firstDelivery = ClientAlertDeliveryCoordinator(
      history: original,
      notifications: _RetryingNotificationService(),
    );

    await expectLater(firstDelivery.deliver(alert), throwsStateError);
    await restored.load();
    expect(restored.alerts, hasLength(1));
    expect(restored.isNotificationPending(alert.id), isTrue);

    final notifications = _RecordingNotificationService();
    final retryDelivery = ClientAlertDeliveryCoordinator(
      history: restored,
      notifications: notifications,
    );
    await retryDelivery.deliver(alert);
    expect(notifications.alerts.map((item) => item.id), [alert.id]);
    expect(restored.alerts, hasLength(1));

    await completed.load();
    expect(completed.isNotificationPending(alert.id), isFalse);
    await ClientAlertDeliveryCoordinator(
      history: completed,
      notifications: notifications,
    ).deliver(alert);
    expect(notifications.alerts, hasLength(1));
  });

  test(
      'concurrent and reconnect copies produce one history entry and one notification',
      () async {
    final history = _RecordingAlertHistory();
    final notifications = _BlockingNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'cry-42');

    final first = delivery.deliver(alert);
    await notifications.firstCallStarted.future;

    // Models the same event arriving from an overlapping/reconnected socket
    // while its first platform post is still in flight.
    final concurrentCopy = delivery.deliver(alert);
    notifications.releaseFirstCall.complete();
    await Future.wait([first, concurrentCopy]);

    // A later replay in the same runtime must remain quiet as well.
    await delivery.deliver(alert);
    await delivery.drain();

    expect(history.addCalls, 1);
    expect(history.alerts.map((item) => item.id), ['cry-42']);
    expect(notifications.alerts.map((item) => item.id), ['cry-42']);
  });

  test('persisted history also suppresses a replay after coordinator rebuild',
      () async {
    final history = _RecordingAlertHistory();
    await history.add(_alert(id: 'motion-persisted'));
    history.addCalls = 0;
    final notifications = _RecordingNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);

    await delivery.deliver(_alert(id: 'motion-persisted'));

    expect(history.addCalls, 0);
    expect(history.alerts, hasLength(1));
    expect(notifications.alerts, isEmpty);
  });

  test('remembered id cache evicts the oldest id at its fixed capacity',
      () async {
    final history = _RecordingAlertHistory(maxItems: 1);
    final notifications = _RecordingNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
      maxRememberedAlertIds: 2,
    );
    addTearDown(history.dispose);

    await delivery.deliver(_alert(id: 'alert-a'));
    await delivery.deliver(_alert(id: 'alert-b'));
    await delivery.deliver(_alert(id: 'alert-c'));

    // alert-a is now outside both bounded stores (cache: b,c; history: c).
    await delivery.deliver(_alert(id: 'alert-a'));

    expect(
      notifications.alerts.map((alert) => alert.id),
      ['alert-a', 'alert-b', 'alert-c', 'alert-a'],
    );
    expect(history.addCalls, 4);
  });

  test('both local surfaces failing leaves alert eligible for replay',
      () async {
    final history = _RejectingAlertHistory();
    final notifications = _RetryingNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'retry-me');

    await expectLater(delivery.deliver(alert), throwsStateError);
    await delivery.deliver(alert);
    await delivery.deliver(alert);

    expect(notifications.calls, 2);
    expect(notifications.alerts.map((item) => item.id), ['retry-me']);
  });

  test(
      'transient notification failure retries without duplicating stored history',
      () async {
    final history = _RecordingAlertHistory();
    final notifications = _RetryingNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'retry-notification');

    await expectLater(delivery.deliver(alert), throwsStateError);
    await delivery.deliver(alert);
    await delivery.deliver(alert);

    expect(history.addCalls, 1);
    expect(history.alerts.map((item) => item.id), ['retry-notification']);
    expect(notifications.calls, 2);
    expect(
      notifications.alerts.map((item) => item.id),
      ['retry-notification'],
    );
  });

  test('permission denial uses history fallback without reconnect loop',
      () async {
    final history = _RecordingAlertHistory();
    final notifications = _PermanentFailureNotificationService();
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'history-only');

    await delivery.deliver(alert);
    await delivery.deliver(alert);

    expect(history.addCalls, 1);
    expect(history.alerts.map((item) => item.id), ['history-only']);
    expect(notifications.calls, 1);
  });

  test('disabled notification channel uses history without reconnect loop',
      () async {
    final history = _RecordingAlertHistory();
    final notifications = _PermanentFailureNotificationService(
      error: 'notification_channel_disabled',
    );
    final delivery = ClientAlertDeliveryCoordinator(
      history: history,
      notifications: notifications,
    );
    addTearDown(history.dispose);
    final alert = _alert(id: 'channel-disabled');

    await delivery.deliver(alert);
    await delivery.deliver(alert);

    expect(history.alerts, hasLength(1));
    expect(history.isNotificationPending(alert.id), isFalse);
    expect(notifications.calls, 1);
  });
}

class _RecordingAlertHistory extends ClientAlertHistory {
  _RecordingAlertHistory({super.maxItems});

  int addCalls = 0;

  @override
  Future<void> add(AlertEventDto alert) {
    addCalls++;
    return super.add(alert);
  }
}

class _RecordingNotificationService extends ClientNotificationService {
  final alerts = <AlertEventDto>[];

  @override
  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) async {
    alerts.add(alert);
    return NotificationDeliveryReceipt(
      notificationId: NotificationService.notificationIdFor(alert.id),
      posted: true,
      verifiedActive: true,
    );
  }
}

class _BlockingNotificationService extends _RecordingNotificationService {
  final firstCallStarted = Completer<void>();
  final releaseFirstCall = Completer<void>();

  @override
  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) async {
    if (!firstCallStarted.isCompleted) {
      firstCallStarted.complete();
      await releaseFirstCall.future;
    }
    return super.showAlert(alert);
  }
}

class _RejectingAlertHistory extends ClientAlertHistory {
  @override
  Future<void> add(AlertEventDto alert) async {
    throw StateError('storage unavailable');
  }
}

class _RetryingNotificationService extends ClientNotificationService {
  int calls = 0;
  final alerts = <AlertEventDto>[];

  @override
  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) async {
    calls++;
    if (calls == 1) {
      return NotificationDeliveryReceipt(
        notificationId: NotificationService.notificationIdFor(alert.id),
        posted: false,
        error: 'platform unavailable',
      );
    }
    alerts.add(alert);
    return NotificationDeliveryReceipt(
      notificationId: NotificationService.notificationIdFor(alert.id),
      posted: true,
      verifiedActive: true,
    );
  }
}

class _PermanentFailureNotificationService extends ClientNotificationService {
  _PermanentFailureNotificationService({
    this.error = 'notification_permission_denied',
  });

  final String error;
  int calls = 0;

  @override
  Future<NotificationDeliveryReceipt> showAlert(AlertEventDto alert) async {
    calls++;
    return NotificationDeliveryReceipt(
      notificationId: NotificationService.notificationIdFor(alert.id),
      posted: false,
      error: error,
    );
  }
}

AlertEventDto _alert({required String id}) => AlertEventDto(
      id: id,
      type: 'cryDetected',
      severity: 'warning',
      messageKey: 'parentEpisodeCryAlert',
      message: 'Ağlama benzeri ses olabilir.',
      score: .82,
      timestampMs: 42,
      sourceDeviceId: 'server',
      metadata: const {
        'durationMs': 5000,
        'networkTier': 'good',
      },
    );
