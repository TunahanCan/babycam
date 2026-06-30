import 'dart:typed_data';

import 'package:flutter/material.dart';

class ClientVideoViewer extends StatelessWidget {
  const ClientVideoViewer({
    super.key,
    required this.frame,
    this.error,
    this.fit = BoxFit.cover,
  });

  final Uint8List? frame;
  final Object? error;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final frame = this.frame;
    if (frame == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: error == null
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.videocam_off_rounded, color: Colors.white70),
      );
    }
    return Image.memory(
      frame,
      fit: fit,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
