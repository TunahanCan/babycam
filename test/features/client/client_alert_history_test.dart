import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/features/client/alerts/client_alert_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/failing_alert_preferences.dart';

void main() {
  test('false storage result remains an error while the alert stays visible',
      () async {
    final preferences = FailingAlertPreferences()..failWrites = true;
    final history = ClientAlertHistory(preferences: preferences);
    addTearDown(history.dispose);

    await expectLater(
      history.addPendingNotification(_alert('not-saved', 'Pending alert')),
      throwsStateError,
    );
    expect(history.alerts.single.id, 'not-saved');
    expect(history.isNotificationPending('not-saved'), isTrue);
    expect(preferences.saved, isEmpty);
  });

  test('loading valid history never deletes it when rewriting fails', () async {
    final preferences = FailingAlertPreferences();
    final original = ClientAlertHistory(preferences: preferences);
    final restored = ClientAlertHistory(preferences: preferences);
    addTearDown(original.dispose);
    addTearDown(restored.dispose);
    await original.addPendingNotification(_alert('saved', 'Saved alert'));
    final durableValue = preferences.saved[ClientAlertHistory.storageKey];
    preferences.throwOnWrite = true;

    await restored.load();

    expect(restored.alerts.single.id, 'saved');
    expect(restored.isNotificationPending('saved'), isTrue);
    expect(preferences.removalAttempts, 0);
    expect(preferences.saved[ClientAlertHistory.storageKey], durableValue);
  });

  test('a failed durable clear is reported and can be retried', () async {
    final preferences = FailingAlertPreferences();
    final history = ClientAlertHistory(preferences: preferences);
    addTearDown(history.dispose);
    await history.add(_alert('old-alert', 'Saved alert'));
    preferences.failWrites = true;

    await expectLater(history.clear(), throwsStateError);
    expect(preferences.saved, isNotEmpty);
    preferences.failWrites = false;
    await history.clear();
    expect(preferences.saved, isEmpty);
  });

  test('gelen alert history icine yazilir ve kalici yuklenir', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final history = ClientAlertHistory(preferences: preferences);

    await history.add(_alert('alert-1', 'İlk bildirim'));
    await history.add(_alert('alert-2', 'Son bildirim'));

    final restored = ClientAlertHistory(preferences: preferences);
    await restored.load();

    expect(restored.alerts.map((alert) => alert.id), ['alert-2', 'alert-1']);
    expect(restored.alerts.first.message, 'Son bildirim');
  });

  test('ayni alert id tekrar gelirse en uste tek kayit olarak guncellenir',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final history = ClientAlertHistory(preferences: preferences);

    await history.add(_alert('alert-1', 'Eski metin'));
    await history.add(_alert('alert-1', 'Yeni metin'));

    expect(history.alerts, hasLength(1));
    expect(history.alerts.single.message, 'Yeni metin');
  });

  test('bozuk history json crash atmadan temizlenir', () async {
    SharedPreferences.setMockInitialValues({
      ClientAlertHistory.storageKey: '{bozuk-json',
    });
    final preferences = await SharedPreferences.getInstance();
    final history = ClientAlertHistory(preferences: preferences);

    await history.load();

    expect(history.alerts, isEmpty);
    expect(preferences.getString(ClientAlertHistory.storageKey), isNull);
  });
}

AlertEventDto _alert(String id, String message) => AlertEventDto(
      id: id,
      type: 'legacyAlert',
      severity: 'info',
      messageKey: 'legacyAlert',
      message: message,
      score: 0,
      timestampMs: DateTime(2026, 6, 29, 12, 30).millisecondsSinceEpoch,
      sourceDeviceId: 'server',
    );
