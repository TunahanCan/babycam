import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
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
    _configureAndroidPlayback();
    _loadAudio();
  }

  @override
  void didUpdateWidget(covariant ClientAudioStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadAudio();
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);

  WebViewController _createController() {
    var params = const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams
          .fromPlatformWebViewControllerCreationParams(
        params,
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams
          .fromPlatformWebViewControllerCreationParams(
        params,
      );
    }
    return WebViewController.fromPlatformCreationParams(params);
  }

  void _configureAndroidPlayback() {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }
  }

  void _loadAudio() {
    final url = jsonEncode(widget.url);
    unawaited(_controller.loadHtmlString('''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin:0; width:100%; height:100%; background:transparent; }
    audio { width:100%; height:32px; opacity:.01; }
  </style>
</head>
<body>
  <audio id="mimicam-audio" src=$url autoplay playsinline></audio>
  <script>
    const audio = document.getElementById('mimicam-audio');
    audio.volume = 1;
    audio.play().catch(() => {});
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) audio.play().catch(() => {});
    });
  </script>
</body>
</html>
'''));
  }
}
