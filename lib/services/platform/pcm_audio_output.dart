import 'package:flutter/services.dart';

abstract class PcmAudioSink {
  Future<void> start({
    required int sampleRate,
    required int channels,
  });

  Future<bool> write(Uint8List pcm16le);

  Future<Map<String, Object?>> status();

  Future<void> stop();
}

class PcmAudioOutput implements PcmAudioSink {
  const PcmAudioOutput({
    MethodChannel channel = const MethodChannel('mimicam/pcm_audio'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> start({
    required int sampleRate,
    required int channels,
  }) =>
      _channel.invokeMethod<void>('start', {
        'sampleRate': sampleRate,
        'channels': channels,
      });

  @override
  Future<bool> write(Uint8List pcm16le) async {
    if (pcm16le.isEmpty) return false;
    return await _channel.invokeMethod<bool>('write', pcm16le) ?? true;
  }

  @override
  Future<Map<String, Object?>> status() async {
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    return status ?? const {};
  }

  Future<void> playTestTone({
    int sampleRate = 16000,
    int channels = 1,
    int durationMs = 1200,
    int frequencyHz = 440,
    double amplitude = .35,
  }) =>
      _channel.invokeMethod<void>('playTestTone', {
        'sampleRate': sampleRate,
        'channels': channels,
        'durationMs': durationMs,
        'frequencyHz': frequencyHz,
        'amplitude': amplitude,
      });

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
