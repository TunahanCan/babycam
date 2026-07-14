part of '../client_home_screen.dart';

enum _AlertFilter { all, motion, audio, system }

class _NotificationFilterBar extends StatelessWidget {
  const _NotificationFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _AlertFilter selected;
  final ValueChanged<_AlertFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            text: strings.ui('all'),
            active: selected == _AlertFilter.all,
            onTap: () => onChanged(_AlertFilter.all),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('motion'),
            active: selected == _AlertFilter.motion,
            onTap: () => onChanged(_AlertFilter.motion),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('audio'),
            active: selected == _AlertFilter.audio,
            onTap: () => onChanged(_AlertFilter.audio),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('system'),
            active: selected == _AlertFilter.system,
            onTap: () => onChanged(_AlertFilter.system),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.alerts,
    required this.filter,
    this.onWatch,
  });

  final List<AlertEventDto> alerts;
  final _AlertFilter filter;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final filteredAlerts = alerts
        .where((alert) => _matchesAlertFilter(alert, filter))
        .toList(growable: false)
      ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    final items = filteredAlerts.isEmpty
        ? [_emptyNotificationSpec(strings)]
        : filteredAlerts
            .map((alert) => _notificationSpecFromAlert(strings, alert));

    return Column(
      children: [
        for (final item in items) ...[
          _NotificationCard(item, onWatch: onWatch),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

bool _matchesAlertFilter(AlertEventDto alert, _AlertFilter filter) {
  if (filter == _AlertFilter.all) return true;
  return switch (filter) {
    _AlertFilter.all => true,
    _AlertFilter.motion => alert.category == AlertCategory.motion,
    _AlertFilter.audio => alert.category == AlertCategory.audio,
    _AlertFilter.system => alert.category == AlertCategory.system,
  };
}

_NotificationSpec _emptyNotificationSpec(AppStrings strings) =>
    _NotificationSpec(
      Icons.notifications_none_rounded,
      strings.ui('waitingLatestStatus'),
      strings.ui('pairedServerAlertAppears'),
      '--:--',
      strings.ui('system'),
      const Color(0xFFF1F5FB),
    );

_NotificationSpec _notificationSpecFromAlert(
  AppStrings strings,
  AlertEventDto alert,
) {
  final family = alert.category;
  return _NotificationSpec(
    switch (family) {
      AlertCategory.motion => Icons.directions_run_rounded,
      AlertCategory.audio => Icons.notifications_active_outlined,
      AlertCategory.system => Icons.wifi_rounded,
    },
    alert.localizedTitle(strings),
    alert.localizedMessage(strings),
    _formatAlertTime(alert.timestampMs),
    _severityLabel(strings, alert.severity),
    switch (family) {
      AlertCategory.motion => const Color(0xFFEFFAF5),
      AlertCategory.audio => MimiCamDesignTokens.blushSoft,
      AlertCategory.system => const Color(0xFFF1F5FB),
    },
  );
}

String _severityLabel(AppStrings strings, String severity) {
  final normalized = severity.toLowerCase();
  if (normalized.contains('critical') || normalized.contains('high')) {
    return strings.ui('important');
  }
  if (normalized.contains('warning') || normalized.contains('medium')) {
    return strings.ui('warning');
  }
  if (normalized.contains('attention')) {
    return strings.ui('important');
  }
  if (normalized.contains('info') || normalized.contains('low')) {
    return strings.ui('info');
  }
  return strings.ui('system');
}

String _formatAlertTime(int timestampMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _NotificationSpec {
  const _NotificationSpec(
    this.icon,
    this.title,
    this.text,
    this.time,
    this.badge,
    this.backgroundColor,
  );

  final IconData icon;
  final String title;
  final String text;
  final String time;
  final String badge;
  final Color backgroundColor;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(this.item, {this.onWatch});

  final _NotificationSpec item;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final decoration = MimiCamDesignTokens.cardDecoration().copyWith(
      color: item.backgroundColor,
    );
    return Semantics(
      button: onWatch != null,
      label: onWatch == null ? item.title : strings.ui('openLiveWatch'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onWatch,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: decoration,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child: Icon(item.icon, color: MimiCamDesignTokens.nightPlum),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: MimiCamDesignTokens.nightPlum,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.text,
                        style: const TextStyle(
                          color: MimiCamDesignTokens.slate,
                          fontSize: 13.5,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        onWatch == null
                            ? item.time
                            : '${item.time} · ${strings.ui('openLiveWatch')}',
                        style: const TextStyle(
                          color: MimiCamDesignTokens.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: const ShapeDecoration(
                        color: Colors.white,
                        shape: StadiumBorder(),
                      ),
                      child: Text(
                        item.badge,
                        style: const TextStyle(
                          color: MimiCamDesignTokens.pink,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (onWatch != null) ...[
                      const SizedBox(height: 18),
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: MimiCamDesignTokens.pink,
                        size: 22,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
