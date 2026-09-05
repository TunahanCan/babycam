part of '../media/watch_screen.dart';

class _BroadcastAccessCard extends StatelessWidget {
  const _BroadcastAccessCard({
    required this.snapshot,
  });

  final BroadcastAccessSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final locked = snapshot.isLocked;
    final unlocked = snapshot.unlocked;
    final title = unlocked
        ? strings.ui('broadcastAccessUnlockedTitle')
        : locked
            ? strings.ui('broadcastAccessLockedTitle')
            : strings.ui('broadcastAccessTrialTitle');
    final body = unlocked
        ? strings.ui('broadcastAccessRemoteUnlockedBody')
        : locked
            ? strings.ui('broadcastAccessRemoteLockedBody')
            : strings.uiFormat('broadcastAccessRemoteTrialBody', {
                'remaining': _remainingText(strings, snapshot.remaining),
              });
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(
        color: locked ? const Color(0xFFFFEEF2) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: unlocked
                    ? _mintSoft
                    : locked
                        ? const Color(0xFFFFD4DF)
                        : const Color(0xFFF2EEFA),
                child: Icon(
                  unlocked
                      ? Icons.verified_rounded
                      : locked
                          ? Icons.lock_rounded
                          : Icons.hourglass_bottom_rounded,
                  color: _navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: _slate,
              fontSize: 13.5,
              height: 1.25,
            ),
          ),
          if (!unlocked) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: snapshot.usedRatio,
                backgroundColor: const Color(0xFFECEFF5),
                valueColor: AlwaysStoppedAnimation<Color>(
                  locked ? _pink : _mint,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  static String _remainingText(AppStrings strings, Duration duration) {
    final totalMinutes =
        (duration.inMilliseconds / Duration.millisecondsPerMinute)
            .ceil()
            .clamp(0, 24 * 60);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) {
      return strings.uiFormat('durationMinutesShort', {'minutes': minutes});
    }
    if (minutes == 0) {
      return strings.uiFormat('durationHoursShort', {'hours': hours});
    }
    return strings.uiFormat(
      'durationHoursMinutesShort',
      {'hours': hours, 'minutes': minutes},
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _navy, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _title.copyWith(fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _subtitle.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LatestAlertCard extends StatelessWidget {
  const _LatestAlertCard({required this.alert, required this.onOpenHistory});

  final AlertEventDto? alert;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final item = alert;
    final color = item == null ? _mint : _alertColor(item);
    final icon = switch (item?.category) {
      AlertCategory.audio => Icons.graphic_eq_rounded,
      AlertCategory.motion => Icons.directions_run_rounded,
      AlertCategory.system => Icons.info_outline_rounded,
      null => Icons.notifications_none_rounded,
    };
    return Semantics(
      button: true,
      label: strings.ui('openHistory'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpenHistory,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: _cardDecoration().copyWith(color: Colors.white),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withValues(alpha: .18),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item == null
                            ? strings.ui('lastAlert')
                            : '${strings.ui('lastAlert')} · '
                                '${formatAlertTimestamp(context, item.timestampMs)}',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item == null
                            ? strings.ui('waitingLatestStatus')
                            : item.localizedMessage(strings),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _slate,
                          fontSize: 12.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: _slate,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({
    required this.session,
    required this.activeStream,
    required this.error,
    required this.audioEnabled,
    required this.fit,
    required this.streamHealthState,
    required this.onToggleAudio,
    required this.onToggleFit,
    required this.onEnterFullscreen,
    required this.onSessionRefreshRequired,
    required this.onFatalError,
    required this.connection,
    required this.retryBusy,
  });

  final PairingSession? session;
  final ActiveStreamSession? activeStream;
  final Object? error;
  final bool audioEnabled;
  final BoxFit fit;
  final ClientStreamHealthState? streamHealthState;
  final VoidCallback onToggleAudio;
  final VoidCallback onToggleFit;
  final VoidCallback onEnterFullscreen;
  final Future<void> Function() onSessionRefreshRequired;
  final ValueChanged<Object> onFatalError;
  final _WatchConnectionPresentation connection;
  final bool retryBusy;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AspectRatio(
      // Bağlantı kurulurken açıklama ve yeniden dene eylemi videodan daha
      // fazla dikey alana ihtiyaç duyar. 5:4 alan, dar ekranlarda ve büyük
      // yazıda durum metninin kesilmesini önler; canlı görüntü 16:9 kalır.
      aspectRatio: connection.isLive ? 16 / 9 : 5 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF162B4A),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: Colors.white.withValues(alpha: .75), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StreamSurface(
              session: session,
              activeStream: activeStream,
              audioEnabled: audioEnabled,
              streamHealthState: streamHealthState,
              fit: fit,
              error: error,
              onSessionRefreshRequired: onSessionRefreshRequired,
              onFatalError: onFatalError,
              connection: connection,
              retryBusy: retryBusy,
            ),
            if (connection.isLive)
              const Positioned(
                top: 10,
                left: 12,
                child: _LiveBadge(),
              ),
            if (connection.isLive)
              Positioned(
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: fit == BoxFit.cover
                          ? Icons.fit_screen_rounded
                          : Icons.crop_free_rounded,
                      tooltip: fit == BoxFit.cover
                          ? strings.ui('videoFitContain')
                          : strings.ui('videoFitCover'),
                      onTap: onToggleFit,
                      toggled: fit == BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    _RoundIconButton(
                      icon: audioEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      tooltip: audioEnabled
                          ? strings.ui('muteAudio')
                          : strings.ui('unmuteAudio'),
                      onTap: onToggleAudio,
                      toggled: audioEnabled,
                    ),
                    const SizedBox(width: 8),
                    _RoundIconButton(
                      icon: Icons.fullscreen_rounded,
                      tooltip: strings.ui('fullScreen'),
                      onTap: onEnterFullscreen,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _networkLabel(AppStrings strings, NetworkQualityTier tier) =>
      switch (tier) {
        NetworkQualityTier.excellent => strings.ui('netExcellent'),
        NetworkQualityTier.good => strings.ui('netGood'),
        NetworkQualityTier.weak => strings.ui('netWeak'),
        NetworkQualityTier.critical => strings.ui('netCritical'),
        NetworkQualityTier.offline => strings.ui('netOffline'),
        NetworkQualityTier.unknown => strings.ui('measuring'),
      };
}
