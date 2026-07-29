import 'dart:io';

import 'package:flutter/services.dart';

class ForegroundServiceController {
  const ForegroundServiceController._();

  static const _channel = MethodChannel('miucam/background_service');

  static Future<void> startServer({
    bool camera = false,
    bool microphone = false,
    bool playback = false,
    bool? nativeCameraCapture,
    bool? nativeMicrophoneCapture,
  }) {
    // Legacy callers used this as a generic "keep alive" hook after opening
    // hardware. Starting Android 14, a foreground service must declare only
    // the while-in-use resource types it actually owns. An unspecified demand
    // is therefore deliberately a no-op; PlatformRuntimeContract publishes the
    // authoritative exact demand immediately after reconciliation.
    if (!camera && !microphone && !playback) return Future<void>.value();
    final serviceCameraCapture = camera && (nativeCameraCapture ?? camera);
    final serviceMicrophoneCapture =
        microphone && (nativeMicrophoneCapture ?? microphone);
    return _invokeAndroid('startServer', {
      'camera': camera,
      'microphone': microphone,
      'playback': playback,
      'nativeCameraCapture': serviceCameraCapture,
      'nativeMicrophoneCapture': serviceMicrophoneCapture,
    });
  }

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
