import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the Client alert transport alive through Android's foreground service.
///
/// Unsupported platforms intentionally treat the absent native channel as a
/// no-op; Android platform failures still surface so the UI does not claim that
/// background alerts are armed when the foreground service could not start.
class ClientAlertBackgroundService {
  const ClientAlertBackgroundService({
    MethodChannel channel = const MethodChannel('miucam/platform_runtime'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> start() => _setDemand(active: true);

  Future<void> stop() => _setDemand(active: false);

  Future<void> _setDemand({required bool active}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setAlertDemand', {
        'active': active,
      });
    } on MissingPluginException {
      // Older Android embeddings may not provide the service channel.
    }
  }
}
