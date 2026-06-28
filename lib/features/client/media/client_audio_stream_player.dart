import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'pcm_audio_output.dart';
import 'wav_pcm_stream_parser.dart';

class ClientAudioStreamPlayer extends StatefulWidget {
  const ClientAudioStreamPlayer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
    this.audioOutput = const PcmAudioOutput(),
    this.onAudioChunkReceived,
    this.onPlaybackStatus,
    this.onAudioError,
  });

  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final PcmAudioOutput audioOutput;
  final VoidCallback? onAudioChunkReceived;
  final ValueChanged<Map<String, Object?>>? onPlaybackStatus;
  final ValueChanged<Object>? onAudioError;

  @override
  State<ClientAudioStreamPlayer> createState() =>
      _ClientAudioStreamPlayerState();
}

class _ClientAudioStreamPlayerState extends State<ClientAudioStreamPlayer> {
  static const _retryDelay = Duration(milliseconds: 700);
  static const _connectTimeout = Duration(seconds: 5);

  HttpClient? _client;
  var _loadGeneration = 0;
  var _outputStarted = false;
  var _chunksWritten = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startAudio());
  }

  @override
  void didUpdateWidget(covariant ClientAudioStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_startAudio());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _closeClient();
    unawaited(_stopOutput());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  Future<void> _startAudio() async {
    final generation = ++_loadGeneration;
    await _stopOutput();
    _closeClient();
    _chunksWritten = 0;
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    _client = client;
    final parser = WavPcmStreamParser();

    try {
      final request = await client.getUrl(Uri.parse(widget.url));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'audio/wav, audio/x-wav, application/octet-stream',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Audio stream failed with HTTP ${response.statusCode}',
          uri: Uri.parse(widget.url),
        );
      }
      await for (final chunk in response) {
        if (!mounted || generation != _loadGeneration) return;
        final parsed = parser.add(Uint8List.fromList(chunk));
        if (!_outputStarted && parsed.isConfigured) {
          await widget.audioOutput.start(
            sampleRate: parsed.sampleRate,
            channels: parsed.channels,
          );
          _outputStarted = true;
          unawaited(_reportPlaybackStatus('started'));
        }
        if (_outputStarted && parsed.pcm16le.isNotEmpty) {
          await widget.audioOutput.write(parsed.pcm16le);
          _chunksWritten++;
          if (_chunksWritten == 1 || _chunksWritten % 25 == 0) {
            unawaited(_reportPlaybackStatus('write'));
          }
          widget.onAudioChunkReceived?.call();
        }
      }
      throw HttpException('Audio stream ended', uri: Uri.parse(widget.url));
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      widget.onAudioError?.call(error);
      debugPrint('MimiCam audio stream error: $error');
      await Future<void>.delayed(_retryDelay);
      if (mounted && generation == _loadGeneration) {
        unawaited(_startAudio());
      }
    } finally {
      if (_client == client) {
        _client = null;
      }
      client.close(force: true);
    }
  }

  Future<void> _reportPlaybackStatus(String event) async {
    try {
      final status = await widget.audioOutput.status();
      final payload = {'event': event, ...status};
      widget.onPlaybackStatus?.call(payload);
      debugPrint('MimiCam audio playback $event: $payload');
    } catch (error) {
      debugPrint('MimiCam audio playback status failed: $error');
    }
  }

  Future<void> _stopOutput() async {
    if (!_outputStarted) return;
    _outputStarted = false;
    try {
      await widget.audioOutput.stop();
    } catch (_) {
      return;
    }
  }

  void _closeClient() {
    _client?.close(force: true);
    _client = null;
  }
}
