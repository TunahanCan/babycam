import 'dart:async';

import 'package:flutter/material.dart';

import 'client_live_audio_pipeline.dart';
import 'pcm_audio_output.dart';

class ClientAudioStreamPlayer extends StatefulWidget {
  const ClientAudioStreamPlayer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
    this.authToken,
    this.audioOutput = const PcmAudioOutput(),
    this.onAudioChunkReceived,
    this.onPlaybackStatus,
    this.onAudioError,
  });

  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final String? authToken;
  final PcmAudioSink audioOutput;
  final VoidCallback? onAudioChunkReceived;
  final ValueChanged<ClientLiveAudioStatus>? onPlaybackStatus;
  final ValueChanged<Object>? onAudioError;

  @override
  State<ClientAudioStreamPlayer> createState() =>
      _ClientAudioStreamPlayerState();
}

class _ClientAudioStreamPlayerState extends State<ClientAudioStreamPlayer> {
  late ClientLiveAudioPipeline _pipeline;

  @override
  void initState() {
    super.initState();
    _pipeline = ClientLiveAudioPipeline(audioOutput: widget.audioOutput);
    _startAudio();
  }

  @override
  void didUpdateWidget(covariant ClientAudioStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final outputChanged = !identical(oldWidget.audioOutput, widget.audioOutput);
    if (outputChanged) {
      unawaited(_pipeline.stop());
      _pipeline = ClientLiveAudioPipeline(audioOutput: widget.audioOutput);
    }
    if (oldWidget.url != widget.url ||
        oldWidget.authToken != widget.authToken ||
        oldWidget.pairedServerHost != widget.pairedServerHost ||
        oldWidget.pairedServerPort != widget.pairedServerPort ||
        outputChanged) {
      _startAudio();
    }
  }

  @override
  void dispose() {
    unawaited(_pipeline.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void _startAudio() {
    unawaited(
      _pipeline.start(
        uri: Uri.parse(widget.url),
        pairedServerHost: widget.pairedServerHost,
        pairedServerPort: widget.pairedServerPort,
        bearerToken: widget.authToken,
        onAudioChunkWritten: widget.onAudioChunkReceived,
        onStatus: widget.onPlaybackStatus,
        onError: widget.onAudioError,
      ),
    );
  }
}
