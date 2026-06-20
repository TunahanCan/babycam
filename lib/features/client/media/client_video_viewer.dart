import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ClientVideoViewer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final controller = WebViewController()
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final allowed = uri.scheme == 'http' &&
              uri.host == pairedServerHost &&
              uri.port == pairedServerPort;
          return allowed
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(url));
    return WebViewWidget(controller: controller);
  }
}
