import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimicam/features/client/media/client_live_audio_pipeline.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());

  const audioUrl = String.fromEnvironment('AUDIO_URL');
  const audioToken = String.fromEnvironment('AUDIO_TOKEN');
  if (audioUrl.isEmpty) {
    debugPrint('CLIENT_AUDIO_PIPELINE_SMOKE missing AUDIO_URL');
    await SystemNavigator.pop();
    return;
  }

  final uri = Uri.parse(audioUrl);
  final pipeline = ClientLiveAudioPipeline();
  final completed = Completer<void>();
  await pipeline.start(
    uri: uri,
    pairedServerHost: uri.host,
    pairedServerPort: uri.port,
    bearerToken: audioToken.isEmpty ? null : audioToken,
    onStatus: (status) {
      debugPrint('CLIENT_AUDIO_PIPELINE_STATUS ${jsonEncode(status.toJson())}');
      if (!completed.isCompleted &&
          status.bytesWritten >= 24000 &&
          status.droppedNativeWrites == 0) {
        completed.complete();
      }
    },
    onError: (error) {
      debugPrint('CLIENT_AUDIO_PIPELINE_ERROR $error');
    },
  );

  try {
    await completed.future.timeout(const Duration(seconds: 8));
  } catch (error) {
    debugPrint('CLIENT_AUDIO_PIPELINE_TIMEOUT $error');
  }
  await pipeline.stop();
  await SystemNavigator.pop();
}
