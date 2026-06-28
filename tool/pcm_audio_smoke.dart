import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimicam/features/client/media/pcm_audio_output.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());

  const output = PcmAudioOutput();
  await output.playTestTone(durationMs: 1200, frequencyHz: 660, amplitude: .35);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final started = await output.status();
  debugPrint('PCM_SMOKE_STATUS_STARTED ${jsonEncode(started)}');
  await Future<void>.delayed(const Duration(milliseconds: 1600));
  final finished = await output.status();
  debugPrint('PCM_SMOKE_STATUS_FINISHED ${jsonEncode(finished)}');
  await output.stop();
  await SystemNavigator.pop();
}
