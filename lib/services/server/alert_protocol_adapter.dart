import 'dart:convert';

import '../../analysis/alert/alert_event.dart';
import '../../core/babycam_protocol.dart';

class AlertProtocolAdapter {
  static List<int> toLegacyAlertPacket(AlertEvent event) => BabyCamProtocol.alertFrame(event.message);

  static String toJsonText(AlertEvent event) => jsonEncode(event.toJson());
}
