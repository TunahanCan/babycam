part of '../media/watch_screen.dart';

class _StreamSurface extends StatefulWidget {
  const _StreamSurface({
    required this.session,
    required this.activeStream,
    required this.audioEnabled,
    required this.streamHealthState,
    required this.fit,
    required this.error,
    required this.onSessionRefreshRequired,
    required this.onFatalError,
    required this.connection,
    required this.retryBusy,
  });

  final PairingSession? session;
  final ActiveStreamSession? activeStream;
  final bool audioEnabled;
  final ClientStreamHealthState? streamHealthState;
  final BoxFit fit;
  final Object? error;
  final Future<void> Function() onSessionRefreshRequired;
  final ValueChanged<Object> onFatalError;
  final _WatchConnectionPresentation connection;
  final bool retryBusy;

  @override
  State<_StreamSurface> createState() => _StreamSurfaceState();
}

class _StreamSurfaceState extends State<_StreamSurface> {
  ClientMediaStreamSupervisor? _supervisor;
  WebRtcClientMediaSupervisor? _webRtcSupervisor;
  Uint8List? _latestFrame;
  Object? _streamError;
  String? _streamKey;

  @override
  void initState() {
    super.initState();
    _syncSupervisor();
  }

  @override
  void didUpdateWidget(covariant _StreamSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSupervisor();
  }

  @override
  void dispose() {
    final supervisor = _supervisor;
    _supervisor = null;
    unawaited(supervisor?.stop());
    final webRtcSupervisor = _webRtcSupervisor;
    _webRtcSupervisor = null;
    unawaited(webRtcSupervisor?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session == null || widget.activeStream == null) {
      final error = widget.error;
      if (error != null) {
        return _StreamErrorPanel(
          connection: widget.connection,
          retryBusy: widget.retryBusy,
          onRetry: widget.onSessionRefreshRequired,
        );
      }
      return _StreamPlaceholder(
        connection: widget.connection,
        retryBusy: widget.retryBusy,
        onRetry: widget.onSessionRefreshRequired,
      );
    }
    final webRtc = widget.activeStream?.webRtc;
    if (widget.activeStream?.usesWebRtc == true && webRtc != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            webRtc.videoRenderer,
            objectFit: widget.fit == BoxFit.cover
                ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            placeholderBuilder: (_) => _StreamPlaceholder(
              connection: widget.connection,
              retryBusy: widget.retryBusy,
              onRetry: widget.onSessionRefreshRequired,
            ),
          ),
          if (!widget.connection.isLive)
            _StreamConnectionOverlay(
              connection: widget.connection,
              retryBusy: widget.retryBusy,
              onRetry: widget.onSessionRefreshRequired,
            ),
        ],
      );
    }
    final streamError = _streamError;
    if (streamError != null) {
      return _StreamErrorPanel(
        connection: widget.connection,
        retryBusy: widget.retryBusy,
        onRetry: widget.onSessionRefreshRequired,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ClientVideoViewer(
          frame: _latestFrame,
          error: streamError ?? widget.error,
          fit: widget.fit,
        ),
        if (!widget.connection.isLive)
          _StreamConnectionOverlay(
            connection: widget.connection,
            retryBusy: widget.retryBusy,
            onRetry: widget.onSessionRefreshRequired,
          ),
      ],
    );
  }

  void _syncSupervisor() {
    final session = widget.session;
    final activeStream = widget.activeStream;
    final nextKey = session == null || activeStream == null
        ? null
        : '${session.httpScheme}://${session.host}:${session.port}'
            '|${session.sessionToken}|${activeStream.streamToken}'
            '|${activeStream.transport.name}';
    if (nextKey == _streamKey) {
      _updateAudioPlayback(activeStream);
      return;
    }
    _streamKey = nextKey;
    final previous = _supervisor;
    _supervisor = null;
    unawaited(previous?.stop());
    final previousWebRtc = _webRtcSupervisor;
    _webRtcSupervisor = null;
    unawaited(previousWebRtc?.stop());
    _latestFrame = null;
    _streamError = null;
    if (session == null || activeStream == null) {
      if (mounted) setState(() {});
      return;
    }
    if (activeStream.usesWebRtc) {
      final handle = activeStream.webRtc!;
      _updateAudioPlayback(activeStream);
      late final WebRtcClientMediaSupervisor supervisor;
      supervisor = WebRtcClientMediaSupervisor(
        handle: handle,
        videoExpected: true,
        audioExpected: activeStream.audioEnabled,
        healthState: widget.streamHealthState,
        onReconnectRequired: widget.onSessionRefreshRequired,
        onFatalError: (error) {
          if (!mounted || !identical(_webRtcSupervisor, supervisor)) return;
          setState(() => _streamError = error);
          widget.onFatalError(error);
        },
      );
      _webRtcSupervisor = supervisor;
      unawaited(supervisor.start().catchError((Object error) {
        if (!mounted || !identical(_webRtcSupervisor, supervisor)) return;
        setState(() => _streamError = error);
        widget.onFatalError(error);
      }));
      if (mounted) setState(() {});
      return;
    }
    late final ClientMediaStreamSupervisor supervisor;
    supervisor = ClientMediaStreamSupervisor(
      session: session,
      activeStream: activeStream,
      audioEnabled: widget.audioEnabled,
      healthState: widget.streamHealthState,
      onVideoFrame: (frame) {
        if (!mounted || !identical(_supervisor, supervisor)) return;
        setState(() {
          _latestFrame = frame;
          _streamError = null;
        });
      },
      onStatus: (update) {
        if (!mounted || !identical(_supervisor, supervisor)) return;
        final failure = update.failure;
        if (failure != null && failure.isTerminal) {
          setState(() => _streamError = failure);
        }
      },
      onSessionRefreshRequired: (_) async {
        await widget.onSessionRefreshRequired();
      },
      onFatalError: (failure) {
        if (!mounted || !identical(_supervisor, supervisor)) return;
        setState(() => _streamError = failure);
        widget.onFatalError(failure);
      },
    );
    _supervisor = supervisor;
    unawaited(supervisor.start().catchError((Object error) {
      if (!mounted || !identical(_supervisor, supervisor)) return;
      setState(() => _streamError = error);
      widget.onFatalError(error);
    }));
    if (mounted) setState(() {});
  }

  void _updateAudioPlayback(ActiveStreamSession? activeStream) {
    if (activeStream?.usesWebRtc == true) {
      widget.streamHealthState?.setAudioExpected(
        widget.audioEnabled && (activeStream?.audioEnabled ?? false),
      );
      final handle = activeStream?.webRtc;
      if (handle is WebRtcClientAudioController) {
        final audioController = handle as WebRtcClientAudioController;
        unawaited(
          audioController
              .setAudioEnabled(widget.audioEnabled)
              .catchError((Object _) {}),
        );
      }
      return;
    }
    final supervisor = _supervisor;
    if (supervisor != null) {
      unawaited(
        supervisor
            .setAudioEnabled(widget.audioEnabled)
            .catchError((Object _) {}),
      );
    }
  }
}

class _StreamPlaceholder extends StatelessWidget {
  const _StreamPlaceholder({
    required this.connection,
    required this.retryBusy,
    required this.onRetry,
  });

  final _WatchConnectionPresentation connection;
  final bool retryBusy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF162B4A),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(connection.icon, color: connection.color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      connection.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connection.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connection.canRetry) ...[
            const SizedBox(height: 12),
            _StreamRetryButton(
              key: const ValueKey('watch-placeholder-retry'),
              busy: retryBusy,
              onRetry: onRetry,
              filled: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _StreamConnectionOverlay extends StatelessWidget {
  const _StreamConnectionOverlay({
    required this.connection,
    required this.retryBusy,
    required this.onRetry,
  });

  final _WatchConnectionPresentation connection;
  final bool retryBusy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: .72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(connection.icon, color: connection.color, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          connection.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connection.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (connection.canRetry) ...[
                const SizedBox(height: 12),
                _StreamRetryButton(
                  key: const ValueKey('watch-overlay-retry'),
                  busy: retryBusy,
                  onRetry: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.toggled,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: toggled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: .68),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamErrorPanel extends StatelessWidget {
  const _StreamErrorPanel({
    required this.connection,
    required this.retryBusy,
    required this.onRetry,
  });

  final _WatchConnectionPresentation connection;
  final bool retryBusy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1D1420),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.of(context).ui('watchStreamUnavailableTitle'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connection.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (connection.canRetry)
            _StreamRetryButton(
              key: const ValueKey('watch-stream-retry'),
              busy: retryBusy,
              onRetry: onRetry,
            ),
        ],
      ),
    );
  }
}

class _StreamRetryButton extends StatelessWidget {
  const _StreamRetryButton({
    super.key,
    required this.busy,
    required this.onRetry,
    this.filled = true,
  });

  final bool busy;
  final Future<void> Function() onRetry;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final icon = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh_rounded, size: 18);
    final onPressed = busy ? null : () => unawaited(onRetry());
    if (!filled) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(strings.ui('reconnect')),
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(strings.ui('reconnect')),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        disabledBackgroundColor: Colors.white70,
        disabledForegroundColor: _navy,
      ),
    );
  }
}
