import 'dart:io';

import 'package:flutter/services.dart';

class ForegroundServiceController {
  const ForegroundServiceController._();

  static const _channel = MethodChannel('mimicam/background_service');

  static Future<void> startServer({
    bool camera = true,
    bool microphone = true,
  }) =>
      _invokeAndroid('startServer', {
        'camera': camera,
        'microphone': microphone,
      });

  static Future<void> stopServer() => _invokeAndroid('stopServer');

  static Future<Map<String, Object?>> status() async {
    if (!Platform.isAndroid) return const {};
    return await _channel.invokeMapMethod<String, Object?>('status') ??
        const {};
  }

  static Future<void> _invokeAndroid(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>(method, arguments);
  }
}
