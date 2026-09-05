import '../../../core/protocol/alert_event_dto.dart';
import '../../../l10n/app_strings.dart';

class AlertShareService {
  String buildShareText(AlertEventDto alert, {required AppStrings strings}) =>
      strings.alertShareText(
        message: alert.localizedMessage(strings),
        time: DateTime.fromMillisecondsSinceEpoch(alert.timestampMs),
        score: alert.score,
        deviceId: alert.sourceDeviceId,
      );

  Future<void> shareAlert(AlertEventDto alert,
      {required AppStrings strings}) async {
    buildShareText(alert, strings: strings);
  }
}
