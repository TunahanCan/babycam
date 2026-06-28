import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ClientVideoViewer extends StatefulWidget {
  const ClientVideoViewer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
    this.fit = BoxFit.cover,
  });
  final String pairedServerHost;
  final int pairedServerPort;
  final String url;
  final BoxFit fit;

  @override
  State<ClientVideoViewer> createState() => _ClientVideoViewerState();
}

class _ClientVideoViewerState extends State<ClientVideoViewer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'about' || uri.scheme == 'data') {
            return NavigationDecision.navigate;
          }
          final allowed = (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host == widget.pairedServerHost &&
              uri.port == widget.pairedServerPort;
          return allowed
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ));
    _loadStream();
  }

  @override
  void didUpdateWidget(covariant ClientVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.fit != widget.fit) {
      _loadStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  void _loadStream() {
    final url = jsonEncode(widget.url);
    final objectFit = switch (widget.fit) {
      BoxFit.contain => 'contain',
      BoxFit.fill => 'fill',
      BoxFit.fitHeight => 'contain',
      BoxFit.fitWidth => 'contain',
      BoxFit.none => 'none',
      BoxFit.scaleDown => 'scale-down',
      _ => 'cover',
    };
    unawaited(_controller.loadHtmlString('''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin:0; width:100%; height:100%; background:#000; overflow:hidden; }
    img { width:100vw; height:100vh; object-fit:$objectFit; display:block; background:#000; }
  </style>
</head>
<body>
  <img src=$url alt="MimiCam live stream">
</body>
</html>
'''));
  }
}
