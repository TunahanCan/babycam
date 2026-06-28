import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ClientVideoViewer extends StatefulWidget {
  const ClientVideoViewer({
    super.key,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.url,
  });
  final String pairedServerHost;
  final int pairedServerPort;
  final String url;

  @override
  State<ClientVideoViewer> createState() => _ClientVideoViewerState();
}

class _ClientVideoViewerState extends State<ClientVideoViewer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final allowed = (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host == widget.pairedServerHost &&
              uri.port == widget.pairedServerPort;
          return allowed
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didUpdateWidget(covariant ClientVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
