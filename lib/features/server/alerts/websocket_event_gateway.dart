import '../../../core/protocol/alert_event_dto.dart';

class WebSocketEventGateway {
  final sent = <Map<String, Object?>>[];
  void broadcast(AlertEventDto event) => sent.add(event.toJson());
}
