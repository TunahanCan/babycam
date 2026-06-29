import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/bytes/byte_chunk.dart';
import 'mjpeg_stream_parser.dart';

class ClientVideoViewer extends StatefulWidget {
  const ClientVideoViewer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
    this.authToken,
    this.fit = BoxFit.cover,
    this.connectTimeout = const Duration(seconds: 5),
    this.readTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 700),
    this.clientFactory,
    this.onFrameReceived,
    this.onStreamTimeout,
    this.onReconnectAttempt,
  });
  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final String? authToken;
  final BoxFit fit;
  final Duration connectTimeout;
  final Duration readTimeout;
  final Duration retryDelay;
  final HttpClient Function()? clientFactory;
  final VoidCallback? onFrameReceived;
  final VoidCallback? onStreamTimeout;
  final VoidCallback? onReconnectAttempt;

  @override
  State<ClientVideoViewer> createState() => _ClientVideoViewerState();
}

class _ClientVideoViewerState extends State<ClientVideoViewer> {
  HttpClient? _client;
  Timer? _retryTimer;
  Completer<void>? _retryWait;
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
    if (oldWidget.url != widget.url ||
        oldWidget.authToken != widget.authToken ||
        oldWidget.fit != widget.fit) {
      unawaited(_startVideo());
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _cancelRetry();
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
    _cancelRetry();
    _closeClient();
    final client = (widget.clientFactory?.call() ?? HttpClient())
      ..connectionTimeout = widget.connectTimeout;
    _client = client;
    final parser = MjpegStreamParser();
    final uri = Uri.parse(widget.url);

    try {
      _validateUri(uri);
      final request = await client.getUrl(uri).timeout(widget.connectTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace, image/jpeg',
      );
      final authToken = widget.authToken;
      if (authToken != null && authToken.isNotEmpty) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      }
      final response = await request.close().timeout(widget.connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Video stream failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      await for (final chunk in response.timeout(widget.readTimeout)) {
        if (!mounted || generation != _loadGeneration) return;
        final frames = parser.add(chunk.asUint8ListView());
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
      widget.onReconnectAttempt?.call();
      if (error is TimeoutException) {
        widget.onStreamTimeout?.call();
      }
      setState(() => _error = error);
      await _waitForRetryDelay();
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

  Future<void> _waitForRetryDelay() {
    final wait = Completer<void>();
    _retryWait = wait;
    _retryTimer = Timer(widget.retryDelay, () {
      if (!wait.isCompleted) wait.complete();
    });
    return wait.future.whenComplete(() {
      if (identical(_retryWait, wait)) {
        _retryWait = null;
        _retryTimer = null;
      }
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final wait = _retryWait;
    _retryWait = null;
    if (wait != null && !wait.isCompleted) {
      wait.complete();
    }
  }
}
