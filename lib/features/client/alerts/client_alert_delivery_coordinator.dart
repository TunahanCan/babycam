import '../../../core/async/serialized_async_executor.dart';
import '../../../core/protocol/alert_event_dto.dart';
import '../../../services/notification_service.dart';
import 'client_alert_history.dart';
import 'client_notification_service.dart';

/// Serializes one server alert into the two parent-facing destinations:
/// in-app history and the platform notification surface.
class ClientAlertDeliveryCoordinator {
  ClientAlertDeliveryCoordinator({
    required ClientAlertHistory history,
    required ClientNotificationService notifications,
    this.maxRememberedAlertIds = 256,
  })  : _history = history,
        _notifications = notifications,
        assert(maxRememberedAlertIds > 0);

  final ClientAlertHistory _history;
  final ClientNotificationService _notifications;
  final int maxRememberedAlertIds;
  final _operations = SerializedAsyncExecutor();
  final _rememberedAlertIds = <String>{};
  final _notificationRetryAlertIds = <String>{};

  Future<void> deliver(AlertEventDto alert) => _operations.run(() async {
        // Keep this check inside the serialized operation. Two copies received
        // by reconnecting sockets can otherwise both pass a pre-queue check
        // and interrupt the parent twice for the same server event.
        if (_wasAlreadyDelivered(alert.id)) return;

        final alreadyInHistory =
            _history.alerts.any((item) => item.id == alert.id);
        Object? notificationError;
        StackTrace? notificationStack;
        if (!alreadyInHistory) {
          try {
            await _history.add(alert);
          } catch (_) {
            // ClientAlertHistory keeps the item in memory even if persistence
            // fails. Check the resulting surface below instead of assuming the
            // write either fully succeeded or fully failed.
          }
        }

        NotificationDeliveryReceipt? receipt;
        try {
          receipt = await _notifications.showAlert(alert);
        } catch (error, stack) {
          notificationError = error;
          notificationStack = stack;
        }

        final availableInHistory =
            _history.alerts.any((item) => item.id == alert.id);
        final notificationDelivered =
            receipt?.posted == true && receipt?.verifiedActive != false;
        if (notificationDelivered) {
          _notificationRetryAlertIds.remove(alert.id);
          _remember(alert.id);
          return;
        }

        // A user-denied permission (or a platform without native
        // notifications) cannot be repaired by reconnecting. The in-app
        // history is the durable fallback in that case, so acknowledge once it
        // is available and avoid an endless reconnect loop.
        if (availableInHistory &&
            _isPermanentNotificationFailure(receipt?.error)) {
          _notificationRetryAlertIds.remove(alert.id);
          _remember(alert.id);
          return;
        }

        // Do not let a successful history write hide a transient platform
        // notification failure. Keep this id eligible despite history
        // deduplication and fail the listener callback so the server replays
        // the still-unacknowledged event after reconnect.
        _notificationRetryAlertIds.add(alert.id);
        if (notificationError != null) {
          Error.throwWithStackTrace(
            notificationError,
            notificationStack ?? StackTrace.current,
          );
        }
        throw StateError('Alert ${alert.id} could not be delivered locally.');
      });

  Future<void> drain() => _operations.drain();

  bool _wasAlreadyDelivered(String alertId) {
    if (_notificationRetryAlertIds.contains(alertId)) return false;
    return _rememberedAlertIds.contains(alertId) ||
        _history.alerts.any((alert) => alert.id == alertId);
  }

  bool _isPermanentNotificationFailure(String? error) =>
      error == 'notification_permission_denied' ||
      error == 'native_notifications_unsupported';

  void _remember(String alertId) {
    _rememberedAlertIds.add(alertId);
    if (_rememberedAlertIds.length <= maxRememberedAlertIds) return;
    _rememberedAlertIds.remove(_rememberedAlertIds.first);
  }
}
