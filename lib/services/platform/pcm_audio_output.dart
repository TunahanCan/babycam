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

/// An isolated playback owner.
///
/// Stopping an older lease must never stop a newer lease created by the same
/// [PcmAudioLeaseSink]. Implementations invalidate ownership synchronously
/// before awaiting native cleanup.
abstract interface class PcmAudioPlaybackLease {
  Future<void> start({
    required int sampleRate,
    required int channels,
  });

  Future<bool> write(Uint8List pcm16le);

  Future<void> stop();
}

abstract interface class PcmAudioLeaseSink {
  PcmAudioPlaybackLease createPlaybackLease();

  /// Invalidates any playback left behind by a previous coordinator instance.
  Future<void> resetPlayback();
}

class PcmAudioOutput implements PcmAudioSink, PcmAudioLeaseSink {
  const PcmAudioOutput({
    MethodChannel channel = const MethodChannel('miucam/pcm_audio'),
  }) : _channel = channel;

  final MethodChannel _channel;
  static int _lastOperationId = DateTime.now().microsecondsSinceEpoch;
  static int _lastLeaseId = 0;
  static PcmAudioPlaybackLease? _legacyLease;

  static int _nextOperationId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now > _lastOperationId) {
      _lastOperationId = now;
    } else {
      _lastOperationId++;
    }
    return _lastOperationId;
  }

  @override
  PcmAudioPlaybackLease createPlaybackLease() =>
      _MethodChannelPcmAudioPlaybackLease(
        channel: _channel,
        leaseId: ++_lastLeaseId,
      );

  @override
  Future<void> resetPlayback() async {
    await _channel.invokeMethod<bool>('stop', {
      'operationId': _nextOperationId(),
      'reset': true,
    });
  }

  @override
  Future<void> start({
    required int sampleRate,
    required int channels,
  }) async {
    final previous = _legacyLease;
    final lease = createPlaybackLease();
    _legacyLease = lease;
    if (previous != null) await previous.stop();
    try {
      await lease.start(sampleRate: sampleRate, channels: channels);
    } catch (_) {
      if (identical(_legacyLease, lease)) _legacyLease = null;
      rethrow;
    }
  }

  @override
  Future<bool> write(Uint8List pcm16le) async {
    if (pcm16le.isEmpty) return false;
    return await _legacyLease?.write(pcm16le) ?? false;
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
  Future<void> stop() async {
    final lease = _legacyLease;
    _legacyLease = null;
    if (lease == null) {
      await resetPlayback();
      return;
    }
    await lease.stop();
  }
}

class _MethodChannelPcmAudioPlaybackLease implements PcmAudioPlaybackLease {
  _MethodChannelPcmAudioPlaybackLease({
    required this.channel,
    required this.leaseId,
  });

  final MethodChannel channel;
  final int leaseId;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  bool _retired = false;

  @override
  Future<void> start({
    required int sampleRate,
    required int channels,
  }) {
    if (_retired) {
      return Future<void>.error(
        StateError('PCM playback lease is retired.'),
      );
    }
    return _startOperation ??= _start(
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  Future<void> _start({
    required int sampleRate,
    required int channels,
  }) async {
    final accepted = await channel.invokeMethod<bool>('start', {
      'sampleRate': sampleRate,
      'channels': channels,
      'leaseId': leaseId,
      'operationId': PcmAudioOutput._nextOperationId(),
    });
    if (accepted == false) {
      throw StateError('PCM playback start lost operation ownership.');
    }
  }

  @override
  Future<bool> write(Uint8List pcm16le) async {
    if (_retired || pcm16le.isEmpty) return false;
    return await channel.invokeMethod<bool>('write', {
          'bytes': pcm16le,
          'leaseId': leaseId,
          'operationId': PcmAudioOutput._nextOperationId(),
        }) ??
        false;
  }

  @override
  Future<void> stop() {
    final current = _stopOperation;
    if (current != null) return current;
    _retired = true;
    final operation = channel.invokeMethod<bool>('stop', {
      'leaseId': leaseId,
      'operationId': PcmAudioOutput._nextOperationId(),
    });
    return _stopOperation = operation.then<void>((_) {});
  }
}
