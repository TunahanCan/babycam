import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'mjpeg_stream_parser.dart';

class ClientVideoViewer extends StatefulWidget {
  const ClientVideoViewer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
    this.fit = BoxFit.cover,
    this.onFrameReceived,
  });
  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final BoxFit fit;
  final VoidCallback? onFrameReceived;

  @override
  State<ClientVideoViewer> createState() => _ClientVideoViewerState();
}

class _ClientVideoViewerState extends State<ClientVideoViewer> {
  static const _retryDelay = Duration(milliseconds: 700);
  static const _connectTimeout = Duration(seconds: 5);

  HttpClient? _client;
  Uint8List? _latestFrame;
  Object? _error;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startVideo());
  }

  @override
  void didUpdateWidget(covariant ClientVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.fit != widget.fit) {
      unawaited(_startVideo());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _closeClient();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _latestFrame;
    if (frame == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: _error == null
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
      fit: widget.fit,
      gaplessPlayback: true,
      width: double.infinity,
      height: double.infinity,
    );
  }

  Future<void> _startVideo() async {
    final generation = ++_loadGeneration;
    _closeClient();
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    _client = client;
    final parser = MjpegStreamParser();
    final uri = Uri.parse(widget.url);

    try {
      _validateUri(uri);
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace, image/jpeg',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Video stream failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      await for (final chunk in response) {
        if (!mounted || generation != _loadGeneration) return;
        final frames = parser.add(Uint8List.fromList(chunk));
        if (frames.isEmpty) continue;
        for (final _ in frames) {
          widget.onFrameReceived?.call();
        }
        final latest = frames.last;
        if (mounted && generation == _loadGeneration) {
          setState(() {
            _latestFrame = latest;
            _error = null;
          });
        }
      }
      throw HttpException('Video stream ended', uri: uri);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
      await Future<void>.delayed(_retryDelay);
      if (mounted && generation == _loadGeneration) {
        unawaited(_startVideo());
      }
    } finally {
      if (_client == client) _client = null;
      client.close(force: true);
    }
  }

  void _validateUri(Uri uri) {
    final allowed = (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host == widget.pairedServerHost &&
        uri.port == widget.pairedServerPort;
    if (!allowed) {
      throw StateError('Video stream host is not the paired server.');
    }
  }

  void _closeClient() {
    _client?.close(force: true);
    _client = null;
  }
}
