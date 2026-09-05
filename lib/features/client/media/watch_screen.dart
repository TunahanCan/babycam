import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/protocol/alert_event_dto.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../l10n/app_strings.dart';
import '../../../services/monetization/broadcast_access_service.dart';
import '../../shared/presentation/media_profile_text.dart';
import '../../shared/presentation/localized_time.dart';
import '../../shared/presentation/localized_measurement_text.dart';
import '../../shared/presentation/localized_room_name.dart';
import '../client_runtime.dart';
import '../controls/client_room_controls.dart';
import '../controls/room_controls_panel.dart';
import '../controls/room_audio_detection_notice.dart';
import 'active_stream_session.dart';
import 'client_media_stream_supervisor.dart';
import 'client_stream_health_state.dart';
import 'client_video_viewer.dart';
import 'webrtc/webrtc_client_connector.dart';
import 'webrtc/webrtc_client_media_supervisor.dart';

part '../presentation/watch_screen_components.dart';
part '../presentation/watch_live_cards.dart';
part '../presentation/watch_stream_surface.dart';
part '../presentation/watch_support_components.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.runtime,
    this.initialTab = 0,
    this.keepScreenAwake = true,
    this.onKeepScreenAwakeChanged,
    this.openSettings,
  });

  final ClientRuntime runtime;
  final int initialTab;
  final bool keepScreenAwake;
  final ValueChanged<bool>? onKeepScreenAwakeChanged;
  final Future<bool> Function()? openSettings;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  late int _tab;
  bool _audioEnabled = true;
  bool _fullscreen = false;
  bool _nightClock = false;
  bool _notificationsBusy = false;
  bool _streamRetryBusy = false;
  late bool _keepScreenAwake;
  BoxFit _videoFit = BoxFit.cover;
  late final int _presentationToken;
  int _screenOperationGeneration = 0;
  bool _screenDisposed = false;
  late bool _appInForeground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _presentationToken = widget.runtime.claimWatchPresentation();
    _tab = widget.initialTab.clamp(0, 2);
    _keepScreenAwake = widget.keepScreenAwake;
    unawaited(_applyWakelock(_keepScreenAwake && _appInForeground));
    _startLiveWatch();
  }

  @override
  void dispose() {
    _screenDisposed = true;
    _screenOperationGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    if (_keepScreenAwake) unawaited(_applyWakelock(false));
    unawaited(widget.runtime
        .releaseWatchPresentation(_presentationToken)
        .catchError((Object _) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_appInForeground == foreground) return;
    _appInForeground = foreground;
    if (!foreground) {
      _screenOperationGeneration++;
      if (_keepScreenAwake) unawaited(_applyWakelock(false));
      unawaited(widget.runtime.stopWatching().catchError((_) {}));
      return;
    }
    if (_keepScreenAwake) unawaited(_applyWakelock(true));
    if (!_nightClock) _startLiveWatch();
  }

  void _startLiveWatch() {
    if (!_appInForeground || _nightClock || _screenDisposed) return;
    final operationGeneration = ++_screenOperationGeneration;
    unawaited(() async {
      try {
        if (!_isCurrentScreenOperation(operationGeneration)) return;
        await widget.runtime.startWatching(audioEnabled: _audioEnabled);
      } catch (_) {}
    }());
  }

  Future<void> _applyWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Widget tests and unsupported targets may not expose a wakelock plugin.
    }
  }

  void _setKeepScreenAwake(bool enabled) {
    if (_keepScreenAwake == enabled) return;
    setState(() => _keepScreenAwake = enabled);
    unawaited(_applyWakelock(enabled && _appInForeground));
    widget.onKeepScreenAwakeChanged?.call(enabled);
  }

  bool _isCurrentScreenOperation(int generation) =>
      !_screenDisposed &&
      generation == _screenOperationGeneration &&
      widget.runtime.isWatchPresentationCurrent(_presentationToken);

  void _toggleAudio() {
    final next = !_audioEnabled;
    setState(() => _audioEnabled = next);
    if (widget.runtime.currentState.activeStream == null && next) {
      _startLiveWatch();
    }
  }

  void _toggleVideoFit() {
    setState(() {
      _videoFit = _videoFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleRoomControlError(Object error) {
    final strings = AppStrings.of(context);
    if (error is RoomMicrophonePermissionException) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(strings.ui('microphonePermissionRequired')),
            action: SnackBarAction(
              label: strings.ui('openAppSettings'),
              onPressed: () => unawaited(_openSystemSettings()),
            ),
          ),
        );
      return;
    }
    _showSnack(strings.ui('roomControlFailed'));
  }

  Future<bool> _openSystemSettings() =>
      widget.openSettings?.call() ?? openAppSettings();

  Future<void> _toggleNotifications(ClientRuntimeState state) async {
    if (_notificationsBusy) return;
    final strings = AppStrings.of(context);
    setState(() => _notificationsBusy = true);
    try {
      if (state.alertsActive) {
        await widget.runtime.stopAlertListening();
        return;
      }
      final started = await widget.runtime.startAlertListening();
      if ((!started || widget.runtime.systemNotificationsEnabled == false) &&
          mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(strings.ui('notificationOff')),
              action: SnackBarAction(
                label: strings.ui('openAppSettings'),
                onPressed: openAppSettings,
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) _showSnack(strings.ui('clientSubtitleError'));
    } finally {
      if (mounted) setState(() => _notificationsBusy = false);
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

  void _enterNightClock() {
    _screenOperationGeneration++;
    setState(() {
      _nightClock = true;
      _fullscreen = false;
    });
    unawaited(() async {
      try {
        await widget.runtime.stopWatching();
      } catch (_) {}
    }());
  }

  void _exitNightClock() {
    setState(() => _nightClock = false);
    _startLiveWatch();
  }

  @override
  Widget build(BuildContext context) {
    if (_nightClock) {
      return StreamBuilder<ClientRuntimeState>(
        stream: widget.runtime.states,
        initialData: widget.runtime.currentState,
        builder: (context, snapshot) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exitNightClock();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _WatchNightClockView(
              runtime: widget.runtime,
              state: snapshot.data ?? widget.runtime.currentState,
              onExit: _exitNightClock,
            ),
          ),
        ),
      );
    }
    if (_fullscreen) {
      return StreamBuilder<ClientRuntimeState>(
        stream: widget.runtime.states,
        initialData: widget.runtime.currentState,
        builder: (context, snapshot) => PopScope<void>(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exitFullscreen();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _fullscreenWatch(
              context,
              snapshot.data ?? widget.runtime.currentState,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: _tab == 1
          ? _LightShell(child: _WatchHistorySection(runtime: widget.runtime))
          : StreamBuilder<ClientRuntimeState>(
              stream: widget.runtime.states,
              initialData: widget.runtime.currentState,
              builder: (context, snapshot) {
                final state = snapshot.data ?? widget.runtime.currentState;
                return _LightShell(
                  child: _tab == 0 ? _watch(context, state) : _settings(state),
                );
              },
            ),
      bottomNavigationBar: _PinnedNav(
        dark: false,
        child: _Nav(tab: _tab, onTap: (i) => setState(() => _tab = i)),
      ),
    );
  }

  Widget _fullscreenWatch(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final connection = _WatchConnectionPresentation.fromState(state, strings);
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _StreamSurface(
            session: state.session,
            activeStream: state.activeStream,
            audioEnabled: _audioEnabled,
            streamHealthState: widget.runtime.streamHealthState,
            fit: _videoFit,
            error: state.error,
            onSessionRefreshRequired: _refreshStreamSession,
            onFatalError: widget.runtime.reportStreamFailure,
            connection: connection,
            retryBusy: _streamRetryBusy,
          ),
          if (state.session != null && widget.runtime.roomControls != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: ConstrainedBox(
                key: const ValueKey('fullscreen-audio-detection-notice'),
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * .35)
                      .clamp(0.0, 160.0),
                ),
                child: SingleChildScrollView(
                  child: RoomAudioDetectionNotice(
                    controls: widget.runtime.roomControls!,
                    session: state.session!,
                    dark: true,
                  ),
                ),
              ),
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
            child: Row(
              children: [
                _RoundIconButton(
                  icon: _videoFit == BoxFit.cover
                      ? Icons.fit_screen_rounded
                      : Icons.crop_free_rounded,
                  tooltip: _videoFit == BoxFit.cover
                      ? strings.ui('videoFitContain')
                      : strings.ui('videoFitCover'),
                  onTap: _toggleVideoFit,
                  toggled: _videoFit == BoxFit.contain,
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: _audioEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  tooltip: _audioEnabled
                      ? strings.ui('muteAudio')
                      : strings.ui('unmuteAudio'),
                  onTap: _toggleAudio,
                  toggled: _audioEnabled,
                ),
              ],
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
    final connection = _WatchConnectionPresentation.fromState(state, strings);
    final roomName = state.session?.deviceName;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          _Top(
            title: roomName != null
                ? localizedRoomName(strings, roomName)
                : strings.ui('liveWatching'),
            trailing: _ConnectedBadge(
              text: connection.label,
              icon: connection.icon,
              color: connection.color,
              backgroundColor: connection.backgroundColor,
            ),
          ),
          const SizedBox(height: 14),
          if (state.broadcastAccess != null) ...[
            _BroadcastAccessCard(snapshot: state.broadcastAccess!),
          ],
          const SizedBox(height: 18),
          _VideoPanel(
            session: state.session,
            activeStream: state.activeStream,
            error: state.error,
            audioEnabled: _audioEnabled,
            fit: _videoFit,
            streamHealthState: widget.runtime.streamHealthState,
            onToggleAudio: _toggleAudio,
            onToggleFit: _toggleVideoFit,
            onEnterFullscreen: _enterFullscreen,
            onSessionRefreshRequired: _refreshStreamSession,
            onFatalError: widget.runtime.reportStreamFailure,
            connection: connection,
            retryBusy: _streamRetryBusy,
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AlertEventDto>>(
            stream: widget.runtime.alertUpdates,
            initialData: widget.runtime.alerts,
            builder: (context, snapshot) {
              final alerts = snapshot.data ?? const <AlertEventDto>[];
              return _LatestAlertCard(
                alert: alerts.isEmpty ? null : alerts.first,
                onOpenHistory: () => setState(() => _tab = 1),
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionLabel(
            icon: Icons.insights_rounded,
            title: strings.ui('roomStatus'),
            subtitle: connection.subtitle,
          ),
          const SizedBox(height: 10),
          _LiveMetricGrid(
            quality: quality,
            profile: profile,
            audioEnabled: _audioEnabled,
            alertsActive: state.alertsActive,
            alertsConnected: widget.runtime.alertTransportConnected,
            systemNotificationsEnabled:
                widget.runtime.systemNotificationsEnabled,
          ),
          if (state.session != null && widget.runtime.roomControls != null)
            RoomAudioDetectionNotice(
              controls: widget.runtime.roomControls!,
              session: state.session!,
            ),
          const SizedBox(height: 18),
          _SectionLabel(
            icon: Icons.tune_rounded,
            title: strings.ui('quickActions'),
            subtitle: strings.ui('liveWatching'),
          ),
          const SizedBox(height: 10),
          _ActionGroup(
            actions: _watchActionSpecs(strings, state),
          ),
          if (state.session != null && widget.runtime.roomControls != null) ...[
            const SizedBox(height: 18),
            RoomControlsPanel(
              controls: widget.runtime.roomControls!,
              session: state.session!,
              onError: _handleRoomControlError,
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: .18)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              label: Text(
                strings.ui('stopLiveWatch'),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
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
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(dark: true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.ui('watchPreferences'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _SwitchLine(
                  strings.ui('enableNotifications'),
                  strings.ui('watchNotificationsDescription'),
                  state.alertsActive,
                  onChanged: _notificationsBusy
                      ? null
                      : (_) => unawaited(_toggleNotifications(state)),
                ),
                _SwitchLine(
                  strings.ui('keepDeviceAwake'),
                  strings.ui('keepAwakeClientText'),
                  _keepScreenAwake,
                  onChanged: _setKeepScreenAwake,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: _mintSoft,
                  child: Icon(Icons.tune_rounded, color: _navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.ui('detectionSettingsOnServer'),
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          )),
                      const SizedBox(height: 6),
                      Text(strings.ui('detectionSettingsOnServerDescription'),
                          style: const TextStyle(
                            color: _slate,
                            fontSize: 14,
                            height: 1.3,
                          )),
                    ],
                  ),
                ),
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
        busy: _notificationsBusy,
      ),
      _ActionSpec(
        Icons.fullscreen_rounded,
        strings.ui('fullScreen'),
        const Color(0xFFF2EEFA),
        _enterFullscreen,
      ),
      _ActionSpec(
        Icons.nights_stay_rounded,
        strings.ui('nightClock'),
        const Color(0xFFF8FFF9),
        _enterNightClock,
      ),
    ];
  }

  Future<void> _refreshStreamSession() async {
    if (_streamRetryBusy || _screenDisposed) return;
    final strings = AppStrings.of(context);
    setState(() => _streamRetryBusy = true);
    try {
      await _restartLiveWatch(audioEnabled: _audioEnabled);
    } catch (_) {
      if (mounted) _showSnack(strings.ui('streamStartFailed'));
    } finally {
      if (mounted) setState(() => _streamRetryBusy = false);
    }
  }

  Future<void> _restartLiveWatch({required bool audioEnabled}) async {
    final operationGeneration = ++_screenOperationGeneration;
    await widget.runtime.restartWatching(audioEnabled: audioEnabled);
    if (!_isCurrentScreenOperation(operationGeneration)) return;
  }
}
