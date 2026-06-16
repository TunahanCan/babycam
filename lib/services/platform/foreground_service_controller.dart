import 'dart:io';

import 'package:flutter/services.dart';

class ForegroundServiceController {
  const ForegroundServiceController._();

  static const _channel = MethodChannel('mimicam/background_service');

  static Future<void> startServer() => _invokeAndroid('startServer');

  static Future<void> stopServer() => _invokeAndroid('stopServer');

  static Future<void> _invokeAndroid(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      return;
    }
  }
}
