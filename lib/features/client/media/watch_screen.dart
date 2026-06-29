import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/alert_event_dto.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../l10n/app_strings.dart';
import '../../shared/presentation/localized_measurement_text.dart';
import '../../shared/presentation/media_profile_text.dart';
import '../client_runtime.dart';
import 'client_audio_stream_player.dart';
import 'client_stream_health_state.dart';
import 'client_video_viewer.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.runtime, this.initialTab = 0});

  final ClientRuntime runtime;
  final int initialTab;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late int _tab;
  bool _audioEnabled = true;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2);
    _startLiveWatch();
  }

  @override
  void dispose() {
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    widget.runtime.stopWatching().catchError((Object _) {});
    super.dispose();
  }

  void _startLiveWatch() {
    if (!widget.runtime.currentState.alertsActive) {
      unawaited(
        widget.runtime.startAlertListening().catchError((Object _) => false),
      );
    }
    unawaited(
      widget.runtime
          .startWatching(audioEnabled: _audioEnabled)
          .catchError((Object _) {}),
    );
  }

  void _toggleAudio() {
    setState(() => _audioEnabled = !_audioEnabled);
    if (_audioEnabled && widget.runtime.currentState.activeStream == null) {
      _startLiveWatch();
    }
  }

  Future<void> _toggleNotifications(ClientRuntimeState state) async {
    if (state.alertsActive) {
      await widget.runtime.stopAlertListening();
      return;
    }
    final started = await widget.runtime.startAlertListening();
    if (!started && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).ui('notificationOff'))),
        );
    }
  }

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _exitFullscreen() {
    setState(() => _fullscreen = false);
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.runtime.currentState;
        if (_fullscreen) {
          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _exitFullscreen();
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: _fullscreenWatch(context, state),
            ),
          );
        }
        final child = switch (_tab) {
          0 => _LightShell(child: _watch(context, state)),
          1 => _LightShell(child: _history()),
          _ => _LightShell(child: _settings(state)),
        };
        return Scaffold(
          body: child,
          bottomNavigationBar: _PinnedNav(
            dark: false,
            child: _Nav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
          ),
        );
      },
    );
  }

  Widget _fullscreenWatch(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _StreamSurface(
            session: state.session,
            streamToken: state.activeStream?.streamToken,
            audioEnabled: _audioEnabled,
            streamHealthState: widget.runtime.streamHealthState,
            fit: BoxFit.contain,
            error: state.error,
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _RoundIconButton(
              icon: Icons.close_rounded,
              tooltip: strings.ui('exitFullScreen'),
              onTap: _exitFullscreen,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _RoundIconButton(
              icon: _audioEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              tooltip: _audioEnabled
                  ? strings.ui('muteAudio')
                  : strings.ui('unmuteAudio'),
              onTap: _toggleAudio,
            ),
          ),
        ],
      ),
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
          _Top(
            trailing: _ConnectedBadge(text: strings.ui('connected')),
          ),
          const SizedBox(height: 16),
          Text(strings.ui('liveWatching'), style: _title),
          const SizedBox(height: 8),
          Text(strings.ui('liveStreamConnectedSubtitle'), style: _subtitle),
          const SizedBox(height: 18),
          _VideoPanel(
            session: state.session,
            streamToken: state.activeStream?.streamToken,
            error: state.error,
            audioEnabled: _audioEnabled,
            streamHealthState: widget.runtime.streamHealthState,
            onToggleAudio: _toggleAudio,
            onEnterFullscreen: _enterFullscreen,
          ),
          const SizedBox(height: 16),
          _LiveMetricGrid(
            quality: quality,
            profile: profile,
            audioEnabled: _audioEnabled,
            alertsActive: state.alertsActive,
          ),
          const SizedBox(height: 18),
          _ActionGroup(
            actions: _watchActionSpecs(strings, state),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                strings.ui('stopLiveWatch'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
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
          StreamBuilder<List<AlertEventDto>>(
            stream: widget.runtime.alertUpdates,
            initialData: widget.runtime.alerts,
            builder: (context, snapshot) => _AlertTimeline(
              alerts: snapshot.data ?? const [],
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
          _SliderCard(
              strings.ui('notificationCooldown'),
              strings.ui('repeatedAlertsLimit'),
              localizedSecondsLabel(strings, 60),
              _pink,
              .68),
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

  List<_ActionSpec> _watchActionSpecs(
    AppStrings strings,
    ClientRuntimeState state,
  ) {
    // Keep watch actions as specs so responsive layout is isolated from the
    // navigation callbacks each button triggers.
    return [
      _ActionSpec(
        _audioEnabled ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        _audioEnabled ? strings.ui('muteAudio') : strings.ui('unmuteAudio'),
        const Color(0xFFFFE3EA),
        _toggleAudio,
      ),
      _ActionSpec(
        state.alertsActive
            ? Icons.notifications_off_rounded
            : Icons.notifications_active_rounded,
        state.alertsActive
            ? strings.ui('disableNotifications')
            : strings.ui('enableNotifications'),
        _mintSoft,
        () => unawaited(_toggleNotifications(state)),
      ),
      _ActionSpec(
        Icons.fullscreen_rounded,
        strings.ui('fullScreen'),
        const Color(0xFFF2EEFA),
        _enterFullscreen,
      ),
      _ActionSpec(
        Icons.nights_stay_rounded,
        strings.ui('openHistory'),
        const Color(0xFFF8FFF9),
        () => setState(() => _tab = 1),
      ),
    ];
  }
}

class _VideoPanel extends StatelessWidget {
  const _VideoPanel({
    required this.session,
    required this.streamToken,
    required this.error,
    required this.audioEnabled,
    required this.streamHealthState,
    required this.onToggleAudio,
    required this.onEnterFullscreen,
  });

  final PairingSession? session;
  final String? streamToken;
  final Object? error;
  final bool audioEnabled;
  final ClientStreamHealthState? streamHealthState;
  final VoidCallback onToggleAudio;
  final VoidCallback onEnterFullscreen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFA47465),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2D8CD), width: 4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StreamSurface(
              session: session,
              streamToken: streamToken,
              audioEnabled: audioEnabled,
              streamHealthState: streamHealthState,
              fit: BoxFit.contain,
              error: error,
            ),
            const Positioned(top: 10, left: 12, child: _LiveBadge()),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: audioEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    tooltip: audioEnabled
                        ? strings.ui('muteAudio')
                        : strings.ui('unmuteAudio'),
                    onTap: onToggleAudio,
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

class _StreamSurface extends StatelessWidget {
  const _StreamSurface({
    required this.session,
    required this.streamToken,
    required this.audioEnabled,
    required this.streamHealthState,
    required this.fit,
    required this.error,
  });

  final PairingSession? session;
  final String? streamToken;
  final bool audioEnabled;
  final ClientStreamHealthState? streamHealthState;
  final BoxFit fit;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    final streamToken = this.streamToken;
    final streamUrl = session == null || streamToken == null
        ? null
        : ServerEndpointBuilder(session).http(
            MimiCamProtocolV2.video,
            query: {'streamToken': streamToken},
          ).toString();
    final audioUrl = session == null || streamToken == null || !audioEnabled
        ? null
        : ServerEndpointBuilder(session).http(
            MimiCamProtocolV2.audio,
            query: {'streamToken': streamToken},
          ).toString();
    if (streamUrl == null && error != null) {
      return _StreamErrorPanel(message: error.toString());
    }
    if (streamUrl == null) return const _StreamPlaceholder();
    return Stack(
      fit: StackFit.expand,
      children: [
        ClientVideoViewer(
          pairedServerHost: session!.host,
          pairedServerPort: session.port,
          url: streamUrl,
          authToken: session.sessionToken,
          fit: fit,
          onFrameReceived: streamHealthState?.markVideoFrameReceived,
        ),
        if (audioUrl != null)
          Positioned(
            left: 0,
            bottom: 0,
            width: 2,
            height: 2,
            child: IgnorePointer(
              child: Opacity(
                opacity: .01,
                child: ClientAudioStreamPlayer(
                  pairedServerHost: session.host,
                  pairedServerPort: session.port,
                  url: audioUrl,
                  authToken: session.sessionToken,
                  onAudioChunkReceived:
                      streamHealthState?.markAudioChunkReceived,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StreamPlaceholder extends StatelessWidget {
  const _StreamPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final left in [22.0, 82.0, 142.0, 202.0, 262.0])
          Positioned(
            left: left,
            top: 22,
            bottom: 22,
            child: Container(width: 1, color: Colors.white54),
          ),
        const Align(alignment: Alignment.center, child: _CribSketch()),
        Positioned(
          left: 14,
          bottom: 12,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.black.withValues(alpha: .78),
            child: const Icon(
              Icons.nights_stay_rounded,
              color: _mint,
              size: 18,
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 12,
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.black.withValues(alpha: .78),
            child: const Icon(
              Icons.settings_suggest_rounded,
              color: _pink,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: .68),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _StreamErrorPanel extends StatelessWidget {
  const _StreamErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1D1420),
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.of(context).ui('streamStartFailed'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetricGrid extends StatelessWidget {
  const _LiveMetricGrid({
    required this.quality,
    required this.profile,
    required this.audioEnabled,
    required this.alertsActive,
  });

  final NetworkQualitySnapshot? quality;
  final MediaQualityProfile? profile;
  final bool audioEnabled;
  final bool alertsActive;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final networkLabel = quality == null
        ? strings.ui('measuring')
        : _VideoPanel._networkLabel(strings, quality!.tier);
    final latencyLabel =
        quality?.rttMs == null ? '120 ms' : '${quality!.rttMs} ms';
    final audioLabel = audioEnabled
        ? profile?.audioFirst == true
            ? strings.ui('audioPriority')
            : strings.ui('audioOn')
        : strings.ui('audioMuted');
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.mic_rounded,
            title: strings.ui('audio'),
            value: audioLabel,
            color: _mintSoft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricTile(
            icon: Icons.notifications_active_rounded,
            title: strings.ui('navNotifications'),
            value: alertsActive
                ? strings.ui('notificationsOn')
                : strings.ui('notificationsOff'),
            color: const Color(0xFFFFE3EA),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricTile(
            icon: Icons.wifi_tethering_rounded,
            title: strings.ui('latency'),
            value: '$networkLabel · $latencyLabel',
            color: const Color(0xFFF8FFF9),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
    return Container(
      height: 116,
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration().copyWith(color: Colors.white),
      child: Column(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color,
            child: Icon(icon, color: _navy, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _slate, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _navy,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
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

class _CribSketch extends StatelessWidget {
  const _CribSketch();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 116,
      child: Stack(
        children: [
          Positioned(
            left: 34,
            right: 22,
            top: 44,
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFFFDCCD),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Positioned(
            left: 84,
            top: 22,
            child: Container(
              width: 70,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF0BFAE),
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
          const Positioned(
            right: 20,
            top: 42,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFC4A08E),
            ),
          ),
          const Positioned(
            right: 0,
            top: 58,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Color(0xFFC4A08E),
            ),
          ),
          const Positioned(
            left: 104,
            top: 48,
            child: SizedBox(
              width: 28,
              child: Divider(color: _navy, thickness: 1),
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
                : localizedMediaProfileSummary(strings, profile!),
            style: const TextStyle(color: _slate, fontSize: 14.5, height: 1.25),
          ),
        ],
      ),
    );
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
            _mint,
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
                    : '${items.length} ${strings.ui('navNotifications')}',
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
  final family = _alertFamily(alert);
  return switch (family) {
    _AlertFamily.motion => strings.ui('motionDetectedTitle'),
    _AlertFamily.audio => strings.ui('cryDetectedTitle'),
    _AlertFamily.system => strings.notificationTitle,
  };
}

Color _alertColor(AlertEventDto alert) {
  final family = _alertFamily(alert);
  return switch (family) {
    _AlertFamily.motion => _amber,
    _AlertFamily.audio => _pink,
    _AlertFamily.system => _mint,
  };
}

enum _AlertFamily { audio, motion, system }

_AlertFamily _alertFamily(AlertEventDto alert) {
  final signature = '${alert.type} ${alert.messageKey}'.toLowerCase();
  if (signature.contains('motion') || signature.contains('light')) {
    return _AlertFamily.motion;
  }
  if (signature.contains('cry') ||
      signature.contains('sound') ||
      signature.contains('audio') ||
      signature.contains('legacy')) {
    return _AlertFamily.audio;
  }
  return _AlertFamily.system;
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
  const _ActionSpec(this.icon, this.text, this.backgroundColor, this.onTap);

  final IconData icon;
  final String text;
  final Color backgroundColor;
  final VoidCallback onTap;
}

class _Action extends StatelessWidget {
  const _Action(this.spec);

  final _ActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      width: double.infinity,
      child: FilledButton(
        onPressed: spec.onTap,
        style: FilledButton.styleFrom(
          backgroundColor: spec.backgroundColor,
          foregroundColor: _navy,
          padding: const EdgeInsets.all(10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Icon(spec.icon, color: _navy, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              spec.text,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _navy,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ],
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

class _Top extends StatelessWidget {
  const _Top({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _navy,
        ),
        const Spacer(),
        const Icon(Icons.circle, color: _pink, size: 10),
        const SizedBox(width: 8),
        const Text(
          'MimiCam',
          style: TextStyle(
            color: _pink,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing! else const SizedBox(width: 48),
      ],
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  const _ConnectedBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: _mintSoft,
        shape: StadiumBorder(
          side: BorderSide(color: _mint.withValues(alpha: .45)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Color(0xFF42B883), size: 7),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF2A9474),
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
const _amber = Color(0xFFFFD37B);

const _title = TextStyle(
    color: _navy, fontSize: 30, height: 1.08, fontWeight: FontWeight.w900);
const _subtitle = TextStyle(color: _slate, fontSize: 15.5, height: 1.25);
