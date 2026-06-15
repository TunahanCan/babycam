import '../../../core/protocol/alert_event_dto.dart';
import 'websocket_event_gateway.dart';

class ServerAlertBroadcaster {
  ServerAlertBroadcaster(this._gateway);
  final WebSocketEventGateway _gateway;
  void broadcast(AlertEventDto event) => _gateway.broadcast(event);
}
