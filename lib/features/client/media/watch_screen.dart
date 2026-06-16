import 'package:flutter/material.dart';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../l10n/app_strings.dart';
import '../client_runtime.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.runtime});

  final ClientRuntime runtime;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.runtime.startWatching().catchError((Object _) {});
  }

  @override
  void dispose() {
    widget.runtime.stopWatching().catchError((Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.runtime.currentState;
        final child = switch (_tab) {
          0 => _DarkShell(child: _watch(context, state)),
          1 => _LightShell(child: _history()),
          _ => _LightShell(child: _settings(state)),
        };
        return Scaffold(
          body: child,
          bottomNavigationBar: _PinnedNav(
            dark: _tab == 0,
            child: _Nav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
          ),
        );
      },
    );
  }

  Widget _watch(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final quality = state.networkQuality;
    final profile = state.mediaProfile;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          const _Top(dark: true),
          const SizedBox(height: 16),
          Text(strings.ui('liveWatching'), style: _darkTitle),
          const SizedBox(height: 8),
          Text(strings.ui('liveStreamConnectedSubtitle'), style: _darkSubtitle),
          const SizedBox(height: 14),
          _LightPill(strings.ui('connected')),
          const SizedBox(height: 16),
          _VideoPanel(quality: quality, profile: profile),
          const SizedBox(height: 12),
          _NetworkQualityCard(quality: quality, profile: profile),
          const SizedBox(height: 16),
          _Event(
              label: strings.ui('lastAlert'),
              value: strings.ui('cryingDetectedAt'),
              color: _pink),
          const SizedBox(height: 10),
          _Event(
              label: strings.ui('motion'),
              value: strings.ui('motionCalmScore'),
              color: _mint),
          const SizedBox(height: 10),
          _Event(
              label: strings.ui('navNotifications'),
              value: strings.ui('localNotificationOn'),
              color: _amber),
          const SizedBox(height: 18),
          Text(
            strings.ui('quickActions'),
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _ActionGroup(
            actions: [
              _ActionSpec(strings.ui('reconnect'), _mint, _navy, () {}),
              _ActionSpec(strings.ui('changeAddress'), _pink, Colors.white,
                  () => Navigator.pop(context)),
              _ActionSpec(strings.ui('openHistory'), _amber, _navy,
                  () => setState(() => _tab = 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _history() {
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
                _Filter(strings.ui('all'), true),
                const SizedBox(width: 10),
                _Filter(strings.ui('audio'), false),
                const SizedBox(width: 10),
                _Filter(strings.ui('motion'), false),
                const SizedBox(width: 10),
                _Filter(strings.ui('system'), false),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Timeline('09:38', strings.cryingSound,
              '18 dB · ${strings.ui('notificationCooldown')}', _pink),
          const SizedBox(height: 10),
          _Timeline(
              '09:31', strings.ui('phaseClientPaired'), '192.168.1.42', _mint),
          const SizedBox(height: 10),
          _Timeline('09:12', strings.motionAlert(72),
              strings.ui('motionMinimumDurationDescription'), _amber),
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
                  strings.ui('todayEventSummary'),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14.5, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings(ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final profile = state.mediaProfile;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          const _Top(),
          const SizedBox(height: 16),
          Text(strings.ui('navSettings'), style: _title),
          const SizedBox(height: 8),
          Text(strings.ui('watchSettingsSubtitle'), style: _subtitle),
          const SizedBox(height: 18),
          _QualityPreferenceCard(profile: profile),
          const SizedBox(height: 12),
          _SliderCard(strings.ui('notificationCooldown'),
              strings.ui('repeatedAlertsLimit'), '60 sn', _pink, .68),
          const SizedBox(height: 12),
          _SliderCard(strings.ui('cryThreshold'),
              strings.ui('ambientCrySensitivity'), '%65', _mint, .65),
          const SizedBox(height: 12),
          _SliderCard(strings.ui('motionThreshold'),
              strings.ui('cameraMotionSensitivity'), '%22', _amber, .22),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(dark: true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.ui('integrations'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _SwitchLine(strings.ui('keepDeviceAwake'),
                    strings.ui('enabledInServerMode'), true),
                _SwitchLine(
                    strings.ui('language'), strings.ui('languageAuto'), true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({required this.quality, required this.profile});

  final NetworkQualitySnapshot? quality;
  final MediaQualityProfile? profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final networkLabel = quality == null
        ? strings.ui('measuring')
        : _networkLabel(strings, quality!.tier);
    final latencyLabel = quality?.rttMs == null ? '—' : '${quality!.rttMs}ms';
    final audioLabel = profile?.audioFirst == true
        ? strings.ui('audioPriority')
        : strings.ui('open');
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        alignment: Alignment.bottomCenter,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 8,
          children: [
            _VideoMetric(
                strings.uiFormat('audioMetric', {'value': audioLabel})),
            _VideoMetric(
                strings.uiFormat('latencyMetric', {'value': latencyLabel})),
            _VideoMetric(
                strings.uiFormat('networkMetric', {'value': networkLabel})),
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

class _NetworkQualityCard extends StatelessWidget {
  const _NetworkQualityCard({required this.quality, required this.profile});

  final NetworkQualitySnapshot? quality;
  final MediaQualityProfile? profile;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isAudioFirst =
        quality?.tier.shouldPreferAudio == true || profile?.audioFirst == true;
    final title = isAudioFirst
        ? strings.ui('audioFirstMode')
        : strings.ui('connectionStable');
    final text = isAudioFirst
        ? strings.ui('audioFirstModeText')
        : strings.ui('autoQualityModeText');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(dark: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: isAudioFirst ? _amber : _mint,
            child: Icon(
              isAudioFirst
                  ? Icons.hearing_rounded
                  : Icons.network_check_rounded,
              color: _navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                if (profile != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile!.summary,
                    style: const TextStyle(
                      color: _mint,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
                : profile!.summary,
            style: const TextStyle(color: _slate, fontSize: 14.5, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _VideoMetric extends StatelessWidget {
  const _VideoMetric(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontSize: 13.5));
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard(
      this.title, this.description, this.value, this.color, this.progress);

  final String title;
  final String description;
  final String value;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: _navy, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Text(description,
              style: const TextStyle(color: _slate, fontSize: 14)),
          const SizedBox(height: 14),
          LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: color,
              backgroundColor: const Color(0xFFECEFF4)),
        ],
      ),
    );
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine(this.title, this.description, this.on);

  final String title;
  final String description;
  final bool on;

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
          Switch(value: on, onChanged: null, activeThumbColor: _mint),
        ],
      ),
    );
  }
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

class _Event extends StatelessWidget {
  const _Event({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(radius: 22, backgroundColor: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: _slate, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _navy, fontSize: 17, fontWeight: FontWeight.w900),
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              for (final action in actions) ...[
                _Action(action),
                if (action != actions.last) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final action in actions) ...[
              Expanded(child: _Action(action)),
              if (action != actions.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ActionSpec {
  const _ActionSpec(
      this.text, this.backgroundColor, this.foregroundColor, this.onTap);

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;
}

class _Action extends StatelessWidget {
  const _Action(this.spec);

  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        onPressed: spec.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: spec.backgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Text(
          spec.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: spec.foregroundColor,
              fontWeight: FontWeight.w900,
              fontSize: 15),
        ),
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter(this.text, this.active);

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: ShapeDecoration(
          color: active ? _navy : Colors.white, shape: const StadiumBorder()),
      child: Text(
        text,
        style: TextStyle(
            color: active ? Colors.white : _slate,
            fontSize: 14,
            fontWeight: FontWeight.w900),
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

class _LightPill extends StatelessWidget {
  const _LightPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration:
            const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _navy, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _Top extends StatelessWidget {
  const _Top({this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : _navy;
    return Row(
      children: [
        Text('09:41',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 14)),
        const Spacer(),
        Icon(Icons.signal_cellular_alt_rounded, color: color),
        const SizedBox(width: 12),
        Icon(Icons.battery_5_bar_rounded, color: color),
      ],
    );
  }
}

class _DarkShell extends StatelessWidget {
  const _DarkShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.7, -.85),
          radius: .9,
          colors: [Color(0xFF24465A), _navy, Color(0xFF07111F)],
        ),
      ),
      child: child,
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
const _amber = Color(0xFFFFD37B);

const _title = TextStyle(
    color: _navy, fontSize: 30, height: 1.08, fontWeight: FontWeight.w900);
const _subtitle = TextStyle(color: _slate, fontSize: 15.5, height: 1.25);
const _darkTitle = TextStyle(
    color: Colors.white,
    fontSize: 30,
    height: 1.08,
    fontWeight: FontWeight.w900);
const _darkSubtitle =
    TextStyle(color: Colors.white70, fontSize: 15.5, height: 1.25);
