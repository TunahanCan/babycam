import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class ClientAudioStreamPlayer extends StatefulWidget {
  const ClientAudioStreamPlayer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
  });

  final String pairedServerHost;
  final int pairedServerPort;
  final String url;

  @override
  State<ClientAudioStreamPlayer> createState() =>
      _ClientAudioStreamPlayerState();
}

class _ClientAudioStreamPlayerState extends State<ClientAudioStreamPlayer> {
  late final AudioPlayer _player;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _startAudio();
  }

  @override
  void didUpdateWidget(covariant ClientAudioStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _startAudio();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  Future<void> _startAudio() async {
    final generation = ++_loadGeneration;
    try {
      await _player.stop();
      if (!mounted || generation != _loadGeneration) return;
      await _player.setVolume(1);
      await _player.setUrl(widget.url);
      if (!mounted || generation != _loadGeneration) return;
      await _player.play();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted && generation == _loadGeneration) {
        unawaited(_startAudio());
      }
    }
  }
}
