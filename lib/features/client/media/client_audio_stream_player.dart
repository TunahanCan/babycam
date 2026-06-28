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
  });

  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final PcmAudioOutput audioOutput;
  final VoidCallback? onAudioChunkReceived;

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
        }
        if (_outputStarted && parsed.pcm16le.isNotEmpty) {
          await widget.audioOutput.write(parsed.pcm16le);
          widget.onAudioChunkReceived?.call();
        }
      }
      throw HttpException('Audio stream ended', uri: Uri.parse(widget.url));
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
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
