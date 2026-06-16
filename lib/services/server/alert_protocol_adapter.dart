import 'dart:convert';

import '../../analysis/alert/alert_event.dart';
import '../../core/mimicam_protocol.dart';

class AlertProtocolAdapter {
  static List<int> toLegacyAlertPacket(AlertEvent event) =>
      MimiCamProtocol.alertFrame(event.message);

  static String toJsonText(AlertEvent event) => jsonEncode(event.toJson());
}
