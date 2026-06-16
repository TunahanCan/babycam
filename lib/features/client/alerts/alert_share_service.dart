import '../../../core/protocol/alert_event_dto.dart';

class AlertShareService {
  String buildShareText(AlertEventDto alert) {
    final time = DateTime.fromMillisecondsSinceEpoch(alert.timestampMs);
    return 'MimiCam uyarısı: ${alert.message}\nSaat: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}\nSkor: ${alert.score.toStringAsFixed(2)}\nCihaz: ${alert.sourceDeviceId}';
  }

  Future<void> shareAlert(AlertEventDto alert) async {
    buildShareText(alert);
  }
}
