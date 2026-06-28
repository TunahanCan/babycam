import 'package:flutter/services.dart';

class PcmAudioOutput {
  const PcmAudioOutput({
    MethodChannel channel = const MethodChannel('mimicam/pcm_audio'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> start({
    required int sampleRate,
    required int channels,
  }) =>
      _channel.invokeMethod<void>('start', {
        'sampleRate': sampleRate,
        'channels': channels,
      });

  Future<void> write(Uint8List pcm16le) async {
    if (pcm16le.isEmpty) return;
    await _channel.invokeMethod<void>('write', pcm16le);
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
