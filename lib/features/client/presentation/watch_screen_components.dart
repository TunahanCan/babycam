part of '../media/watch_screen.dart';

class _WatchNightClockView extends StatefulWidget {
  const _WatchNightClockView({
    required this.runtime,
    required this.state,
    required this.onExit,
  });

  final ClientRuntime runtime;
  final ClientRuntimeState state;
  final VoidCallback onExit;

  @override
  State<_WatchNightClockView> createState() => _WatchNightClockViewState();
}

class _WatchNightClockViewState extends State<_WatchNightClockView> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = widget.state;
    final quality = state.networkQuality?.tier ?? NetworkQualityTier.unknown;
    final time = formatLocalTime(context, _now);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 44)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.close_rounded,
                        tooltip: strings.ui('exitNightClock'),
                        onTap: widget.onExit,
                      ),
                      const Spacer(),
                      _ConnectedBadge(
                        text: _VideoPanel._networkLabel(strings, quality),
                        dark: true,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Semantics(
                    label: time,
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          time,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    !state.alertsActive
                        ? strings.ui('notificationsOff')
                        : widget.runtime.alertTransportConnected
                            ? widget.runtime.systemNotificationsEnabled == false
                                ? strings.ui('notificationsInAppOnly')
                                : strings.ui('nightClockAudioAlertsOn')
                            : strings.ui('clientTitleReconnecting'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (state.session != null &&
                      widget.runtime.roomControls != null)
                    RoomAudioDetectionNotice(
                      controls: widget.runtime.roomControls!,
                      session: state.session!,
                      dark: true,
                    ),
                  const Spacer(),
                  StreamBuilder<List<AlertEventDto>>(
                    stream: widget.runtime.alertUpdates,
                    initialData: widget.runtime.alerts,
                    builder: (context, snapshot) {
                      final alerts = snapshot.data ?? const <AlertEventDto>[];
                      final alert = alerts.isEmpty ? null : alerts.first;
                      return Semantics(
                        liveRegion: true,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.notifications_active_rounded,
                                color: _mint,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  alert == null
                                      ? strings.ui('waitingLatestStatus')
                                      : '${formatAlertTimestamp(context, alert.timestampMs)} · '
                                          '${_alertTitle(strings, alert)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection({required this.runtime});

  final ClientRuntime runtime;

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  _WatchAlertFilter _filter = _WatchAlertFilter.all;

  List<AlertEventDto> _filtered(List<AlertEventDto> alerts) =>
      switch (_filter) {
        _WatchAlertFilter.all => alerts,
        _WatchAlertFilter.audio => alerts
            .where((alert) => alert.category == AlertCategory.audio)
            .toList(growable: false),
        _WatchAlertFilter.motion => alerts
            .where((alert) => alert.category == AlertCategory.motion)
            .toList(growable: false),
        _WatchAlertFilter.system => alerts
            .where((alert) => alert.category == AlertCategory.system)
            .toList(growable: false),
      };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          const _Top(),
          const SizedBox(height: 16),
          Text(strings.ui('alertHistory'), style: _title),
          const SizedBox(height: 8),
          Text(strings.ui('alertHistorySubtitle'), style: _subtitle),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in _WatchAlertFilter.values) ...[
                  if (filter != _WatchAlertFilter.all)
                    const SizedBox(width: 10),
                  _Filter(
                    switch (filter) {
                      _WatchAlertFilter.all => strings.ui('all'),
                      _WatchAlertFilter.audio => strings.ui('audio'),
                      _WatchAlertFilter.motion => strings.ui('motion'),
                      _WatchAlertFilter.system => strings.ui('system'),
                    },
                    _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<AlertEventDto>>(
            stream: widget.runtime.alertUpdates,
            initialData: widget.runtime.alerts,
            builder: (context, snapshot) => _AlertTimeline(
              alerts: _filtered(snapshot.data ?? const []),
            ),
          ),
        ],
      ),
    );
  }
}

enum _WatchAlertFilter { all, audio, motion, system }

class _WatchConnectionPresentation {
  const _WatchConnectionPresentation({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.isLive,
    required this.canRetry,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final bool isLive;
  final bool canRetry;

  factory _WatchConnectionPresentation.fromState(
    ClientRuntimeState state,
    AppStrings strings,
  ) {
    if (state.error != null || state.phase == ClientRuntimePhase.error) {
      return _WatchConnectionPresentation(
        label: strings.ui('clientTitleError'),
        subtitle: strings.ui('watchConnectionErrorSubtitle'),
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFB63D5B),
        backgroundColor: const Color(0xFFFFE8EE),
        isLive: false,
        canRetry: true,
      );
    }
    if (state.phase == ClientRuntimePhase.revoked) {
      return _WatchConnectionPresentation(
        label: strings.ui('clientTitleRevoked'),
        subtitle: strings.ui('clientSubtitleError'),
        icon: Icons.link_off_rounded,
        color: const Color(0xFFB63D5B),
        backgroundColor: const Color(0xFFFFE8EE),
        isLive: false,
        canRetry: false,
      );
    }
    final offline = state.phase == ClientRuntimePhase.offline ||
        state.networkQuality?.tier == NetworkQualityTier.offline;
    if (offline) {
      return _WatchConnectionPresentation(
        label: strings.ui('clientTitleOffline'),
        subtitle: strings.ui('clientSubtitleOffline'),
        icon: Icons.cloud_off_rounded,
        color: const Color(0xFF9A681C),
        backgroundColor: const Color(0xFFFFF2D9),
        isLive: false,
        canRetry: true,
      );
    }
    if (state.phase == ClientRuntimePhase.reconnecting ||
        state.phase == ClientRuntimePhase.renewingToken) {
      return _WatchConnectionPresentation(
        label: state.phase == ClientRuntimePhase.renewingToken
            ? strings.ui('clientTitleRenewingToken')
            : strings.ui('clientTitleReconnecting'),
        subtitle: strings.ui('watchReconnectingSubtitle'),
        icon: Icons.sync_rounded,
        color: const Color(0xFF6257C8),
        backgroundColor: const Color(0xFFEEEAFE),
        isLive: false,
        canRetry: true,
      );
    }
    if (state.phase == ClientRuntimePhase.watching &&
        state.activeStream != null) {
      return _WatchConnectionPresentation(
        label: strings.ui('connected'),
        subtitle: strings.ui('liveStreamConnectedSubtitle'),
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF278565),
        backgroundColor: _mintSoft,
        isLive: true,
        canRetry: false,
      );
    }
    return _WatchConnectionPresentation(
      label: strings.ui('cameraStarting'),
      subtitle: strings.ui('watchStartingSubtitle'),
      icon: Icons.hourglass_top_rounded,
      color: const Color(0xFF6257C8),
      backgroundColor: const Color(0xFFEEEAFE),
      isLive: false,
      canRetry: false,
    );
  }
}
