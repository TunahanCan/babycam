part of '../media/watch_screen.dart';

class _LiveMetricGrid extends StatelessWidget {
  const _LiveMetricGrid({
    required this.quality,
    required this.profile,
    required this.audioEnabled,
    required this.alertsActive,
    required this.alertsConnected,
    required this.systemNotificationsEnabled,
  });

  final NetworkQualitySnapshot? quality;
  final MediaQualityProfile? profile;
  final bool audioEnabled;
  final bool alertsActive;
  final bool alertsConnected;
  final bool? systemNotificationsEnabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final networkLabel = quality == null
        ? strings.ui('measuring')
        : _VideoPanel._networkLabel(strings, quality!.tier);
    final latencyLabel = quality?.rttMs == null
        ? strings.ui('measuring')
        : '${quality!.rttMs} ms';
    final audioLabel = audioEnabled
        ? profile?.audioFirst == true
            ? strings.ui('audioPriority')
            : strings.ui('audioOn')
        : strings.ui('audioMuted');
    final notificationLabel = !alertsActive
        ? strings.ui('notificationsOff')
        : alertsConnected
            ? systemNotificationsEnabled == false
                ? strings.ui('notificationsInAppOnly')
                : strings.ui('notificationsOn')
            : strings.ui('clientTitleReconnecting');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: _cardDecoration().copyWith(color: Colors.white),
      child: Column(
        children: [
          _StatusRow(
            icon: Icons.mic_rounded,
            title: strings.ui('audio'),
            value: audioLabel,
            color: _mint,
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          _StatusRow(
            icon: Icons.notifications_active_rounded,
            title: strings.ui('navNotifications'),
            value: notificationLabel,
            color: alertsActive ? _pink : _slate,
          ),
          const Divider(height: 1, color: Color(0xFFE7EAF0)),
          _StatusRow(
            icon: Icons.wifi_tethering_rounded,
            title: strings.ui('latency'),
            value: '$networkLabel · $latencyLabel',
            color: quality?.tier == NetworkQualityTier.offline
                ? const Color(0xFFB63D5B)
                : const Color(0xFF6257C8),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _slate,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: StadiumBorder(),
      ),
      child: Text(
        AppStrings.of(context).ui('live').toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF218765),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QualityPreferenceCard extends StatelessWidget {
  const _QualityPreferenceCard({required this.profile});

  final MediaQualityProfile? profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.ui('automaticQuality'),
            style: const TextStyle(
              color: _navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            profile == null
                ? strings.ui('autoQualityDescription')
                : localizedMediaProfileSummary(strings, profile!),
            style: const TextStyle(color: _slate, fontSize: 14.5, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine(
    this.title,
    this.description,
    this.on, {
    this.onChanged,
  });

  final String title;
  final String description;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                Text(description,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          Switch(value: on, onChanged: onChanged, activeThumbColor: _mint),
        ],
      ),
    );
  }
}

class _AlertTimeline extends StatelessWidget {
  const _AlertTimeline({required this.alerts});

  final List<AlertEventDto> alerts;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = alerts.isEmpty ? <AlertEventDto>[] : alerts;
    return Column(
      children: [
        if (items.isEmpty)
          _Timeline(
            '--:--',
            strings.ui('waitingLatestStatus'),
            strings.ui('pairedServerAlertAppears'),
            _timelineMint,
          )
        else
          for (final alert in items) ...[
            _Timeline(
              _formatAlertTime(alert.timestampMs),
              _alertTitle(strings, alert),
              alert.localizedMessage(strings),
              _alertColor(alert),
            ),
            if (alert != items.last) const SizedBox(height: 10),
          ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(dark: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.ui('dailySummary'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Text(
                items.isEmpty
                    ? strings.ui('parentEventsPriorityText')
                    : strings.notificationCount(items.length),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14.5, height: 1.25),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _alertTitle(AppStrings strings, AlertEventDto alert) {
  return alert.localizedTitle(strings);
}

Color _alertColor(AlertEventDto alert) {
  final family = alert.category;
  return switch (family) {
    AlertCategory.motion => _timelineAmber,
    AlertCategory.audio => _timelinePink,
    AlertCategory.system => _timelineMint,
  };
}

String _formatAlertTime(int timestampMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.time, this.title, this.text, this.color);

  final String time;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(time,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(text,
                    style: const TextStyle(
                        color: _slate, fontSize: 14, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.actions});

  final List<_ActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 76,
      ),
      itemBuilder: (context, index) => _Action(actions[index]),
    );
  }
}

class _ActionSpec {
  const _ActionSpec(
    this.icon,
    this.text,
    this.backgroundColor,
    this.onTap, {
    this.busy = false,
  });

  final IconData icon;
  final String text;
  final Color backgroundColor;
  final VoidCallback onTap;
  final bool busy;
}

class _Action extends StatelessWidget {
  const _Action(this.spec);

  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      width: double.infinity,
      child: FilledButton(
        onPressed: spec.busy ? null : spec.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: spec.backgroundColor,
          foregroundColor: _navy,
          padding: const EdgeInsets.all(4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spec.busy)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              CircleAvatar(
                radius: 13,
                backgroundColor: Colors.white,
                child: Icon(spec.icon, color: _navy, size: 20),
              ),
            const SizedBox(height: 3),
            Flexible(
              child: Text(
                spec.text,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter(this.text, this.active, {required this.onTap});

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? _navy : Colors.white,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  text,
                  style: TextStyle(
                    color: active ? Colors.white : _slate,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.tab, required this.onTap});

  final int tab;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(6),
      decoration:
          const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
      child: Row(
        children: [
          for (final entry in [
            AppStrings.of(context).ui('navWatch'),
            AppStrings.of(context).ui('navHistory'),
            AppStrings.of(context).ui('navSettings')
          ].asMap().entries)
            Expanded(
              child: InkWell(
                onTap: () => onTap(entry.key),
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: tab == entry.key
                        ? const Color(0xFFFFDCE6)
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tab == entry.key ? _navy : _slate,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinnedNav extends StatelessWidget {
  const _PinnedNav({required this.child, required this.dark});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? _navy : const Color(0xFFF9F7FC),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22111827),
            blurRadius: 22,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: child,
        ),
      ),
    );
  }
}

class _Top extends StatelessWidget {
  const _Top({this.trailing, this.title});

  final Widget? trailing;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _navy,
        ),
        Expanded(
          child: Center(
            child: Text(
              title ?? 'MiuCam',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _navy,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: Align(
            alignment: Alignment.centerRight,
            child: trailing == null
                ? const SizedBox.shrink()
                : FittedBox(fit: BoxFit.scaleDown, child: trailing),
          ),
        ),
      ],
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge({
    required this.text,
    this.dark = false,
    this.icon = Icons.circle,
    this.color = const Color(0xFF2A9474),
    this.backgroundColor = _mintSoft,
  });

  final String text;
  final bool dark;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: dark ? Colors.white.withValues(alpha: .10) : backgroundColor,
        shape: StadiumBorder(
          side: BorderSide(
            color: dark ? Colors.white24 : color.withValues(alpha: .36),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: dark ? Colors.white : color, size: 13),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: dark ? Colors.white : color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LightShell extends StatelessWidget {
  const _LightShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.55, -.75),
          radius: .85,
          colors: [_mintSoft, Color(0xFFFDF7F4), Color(0xFFF9F7FC)],
        ),
      ),
      child: child,
    );
  }
}

BoxDecoration _cardDecoration({bool dark = false}) {
  return BoxDecoration(
    color: dark ? _navy : Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: const [
      BoxShadow(color: Color(0x18111827), blurRadius: 18, offset: Offset(0, 8)),
    ],
  );
}

const _navy = Color(0xFF101B31);
const _slate = Color(0xFF6E7686);
const _pink = Color(0xFFFF708B);
const _mint = Color(0xFF87D8CC);
const _mintSoft = Color(0xFFD9F7F1);
const _timelinePink = Color(0xFFA83355);
const _timelineMint = Color(0xFF167D69);
const _timelineAmber = Color(0xFF8A5A00);

const _title = TextStyle(
    color: _navy, fontSize: 30, height: 1.08, fontWeight: FontWeight.w900);
const _subtitle = TextStyle(color: _slate, fontSize: 15.5, height: 1.25);
