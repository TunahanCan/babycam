import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/alert_event_dto.dart';
import 'package:mimicam/features/client/alerts/client_alert_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
