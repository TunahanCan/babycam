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
import '../client_runtime.dart';
import '../controls/room_controls_panel.dart';
import 'active_stream_session.dart';
import 'client_media_stream_supervisor.dart';
import 'client_stream_health_state.dart';
import 'client_video_viewer.dart';
import 'webrtc/webrtc_client_connector.dart';
import 'webrtc/webrtc_client_media_supervisor.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.runtime,
    this.initialTab = 0,
    this.keepScreenAwake = true,
    this.onKeepScreenAwakeChanged,
  });

  final ClientRuntime runtime;
  final int initialTab;
  final bool keepScreenAwake;
  final ValueChanged<bool>? onKeepScreenAwakeChanged;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  late int _tab;
  bool _audioEnabled = true;
  bool _fullscreen = false;
  bool _nightClock = false;
  bool _purchaseBusy = false;
  bool _notificationsBusy = false;
  bool _streamRetryBusy = false;
  late bool _keepScreenAwake;
  _WatchAlertFilter _historyFilter = _WatchAlertFilter.all;
  BoxFit _videoFit = BoxFit.cover;
  DateTime _clockNow = DateTime.now();
  Timer? _clockTimer;
  late final int _presentationToken;
  int _screenOperationGeneration = 0;
  bool _screenDisposed = false;

  @override
  void initState() {
    super.initState();
    _presentationToken = widget.runtime.claimWatchPresentation();
    _tab = widget.initialTab.clamp(0, 2);
    _keepScreenAwake = widget.keepScreenAwake;
    unawaited(_applyWakelock(_keepScreenAwake));
    _startLiveWatch();
  }

  @override
  void dispose() {
    _screenDisposed = true;
    _screenOperationGeneration++;
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _clockTimer?.cancel();
    if (_keepScreenAwake) unawaited(_applyWakelock(false));
    unawaited(widget.runtime
        .releaseWatchPresentation(_presentationToken)
        .catchError((Object _) {}));
    super.dispose();
  }

  void _startLiveWatch() {
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
    unawaited(_applyWakelock(enabled));
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

  Future<void> _unlockBroadcastAccess() async {
    if (_purchaseBusy) return;
    final strings = AppStrings.of(context);
    setState(() => _purchaseBusy = true);
    try {
      await widget.runtime.unlockBroadcastAccess();
      if (!mounted) return;
      _showSnack(strings.ui('broadcastAccessUnlocked'));
      _startLiveWatch();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_purchaseMessage(strings, error));
    } finally {
      if (mounted) setState(() => _purchaseBusy = false);
    }
  }

  Future<void> _restoreBroadcastAccess() async {
    if (_purchaseBusy) return;
    final strings = AppStrings.of(context);
    setState(() => _purchaseBusy = true);
    try {
      await widget.runtime.restoreBroadcastAccessPurchase();
      if (!mounted) return;
      _showSnack(strings.ui('broadcastAccessUnlocked'));
      _startLiveWatch();
    } catch (error) {
      if (!mounted) return;
      _showSnack(_purchaseMessage(strings, error));
    } finally {
      if (mounted) setState(() => _purchaseBusy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _purchaseMessage(AppStrings strings, Object error) {
    if (error is BroadcastPurchaseException) {
      return switch (error.result.status) {
        BroadcastPurchaseStatus.pending => strings.ui('purchasePending'),
        BroadcastPurchaseStatus.canceled => strings.ui('purchaseCanceled'),
        BroadcastPurchaseStatus.unavailable =>
          strings.ui('purchaseUnavailable'),
        _ => error.result.message ?? strings.ui('purchaseFailed'),
      };
    }
    if (error is BroadcastAccessLockedException) {
      return strings.ui('broadcastAccessLockedBody');
    }
    return strings.ui('purchaseFailed');
  }

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
      if (!started && mounted) {
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
    _clockTimer?.cancel();
    setState(() {
      _nightClock = true;
      _fullscreen = false;
      _clockNow = DateTime.now();
    });
    unawaited(() async {
      try {
        await widget.runtime.stopWatching();
      } catch (_) {}
    }());
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_nightClock) return;
      setState(() => _clockNow = DateTime.now());
    });
  }

  void _exitNightClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
    setState(() => _nightClock = false);
    _startLiveWatch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? widget.runtime.currentState;
        if (_nightClock) {
          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _exitNightClock();
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: _nightClockView(context, state),
            ),
          );
        }
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

  Widget _nightClockView(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final quality = state.networkQuality?.tier ?? NetworkQualityTier.unknown;
    final alert =
        widget.runtime.alerts.isEmpty ? null : widget.runtime.alerts.first;
    final time = '${_clockNow.hour.toString().padLeft(2, '0')}:'
        '${_clockNow.minute.toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                _RoundIconButton(
                  icon: Icons.close_rounded,
                  tooltip: strings.ui('exitNightClock'),
                  onTap: _exitNightClock,
                ),
                const Spacer(),
                _ConnectedBadge(
                  text: _VideoPanel._networkLabel(strings, quality),
                  dark: true,
                ),
              ],
            ),
            const Spacer(),
            Text(
              time,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              !state.alertsActive
                  ? strings.ui('notificationsOff')
                  : widget.runtime.alertTransportConnected
                      ? strings.ui('nightClockAudioAlertsOn')
                      : strings.ui('clientTitleReconnecting'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
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
                          : '${_formatAlertTime(alert.timestampMs)} · '
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
          ],
        ),
      ),
    );
  }

  Widget _watch(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final quality = state.networkQuality;
    final profile = state.mediaProfile;
    final connection = _WatchConnectionPresentation.fromState(state, strings);
    final roomName = state.session?.deviceName.trim();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          _Top(
            title: roomName?.isNotEmpty == true
                ? roomName!
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
            _BroadcastAccessCard(
              snapshot: state.broadcastAccess!,
              busy: _purchaseBusy,
              onUnlock: widget.runtime.canManageBroadcastPurchase
                  ? _unlockBroadcastAccess
                  : null,
              onRestore: widget.runtime.canManageBroadcastPurchase
                  ? _restoreBroadcastAccess
                  : null,
            ),
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
              onError: (_) => _showSnack(strings.ui('roomControlFailed')),
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
                _Filter(
                  strings.ui('all'),
                  _historyFilter == _WatchAlertFilter.all,
                  onTap: () => setState(
                    () => _historyFilter = _WatchAlertFilter.all,
                  ),
                ),
                const SizedBox(width: 10),
                _Filter(
                  strings.ui('audio'),
                  _historyFilter == _WatchAlertFilter.audio,
                  onTap: () => setState(
                    () => _historyFilter = _WatchAlertFilter.audio,
                  ),
                ),
                const SizedBox(width: 10),
                _Filter(
                  strings.ui('motion'),
                  _historyFilter == _WatchAlertFilter.motion,
                  onTap: () => setState(
                    () => _historyFilter = _WatchAlertFilter.motion,
                  ),
                ),
                const SizedBox(width: 10),
                _Filter(
                  strings.ui('system'),
                  _historyFilter == _WatchAlertFilter.system,
                  onTap: () => setState(
                    () => _historyFilter = _WatchAlertFilter.system,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<AlertEventDto>>(
            stream: widget.runtime.alertUpdates,
            initialData: widget.runtime.alerts,
            builder: (context, snapshot) => _AlertTimeline(
              alerts: _filterHistory(snapshot.data ?? const []),
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

  List<AlertEventDto> _filterHistory(List<AlertEventDto> alerts) =>
      switch (_historyFilter) {
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

  Future<void> _restartLiveWatch({required bool audioEnabled}) async {
    final operationGeneration = ++_screenOperationGeneration;
    await widget.runtime.restartWatching(audioEnabled: audioEnabled);
    if (!_isCurrentScreenOperation(operationGeneration)) return;
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

class _BroadcastAccessCard extends StatelessWidget {
  const _BroadcastAccessCard({
    required this.snapshot,
    required this.busy,
    required this.onUnlock,
    required this.onRestore,
  });

  final BroadcastAccessSnapshot snapshot;
  final bool busy;
  final VoidCallback? onUnlock;
  final VoidCallback? onRestore;

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
        ? strings.ui('broadcastAccessUnlockedBody')
        : locked
            ? strings.ui('broadcastAccessLockedBody')
            : strings.uiFormat('broadcastAccessTrialBody', {
                'remaining': _remainingText(snapshot.remaining),
                'price': snapshot.priceLabel,
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
            if (onUnlock != null && onRestore != null)
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : onUnlock,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_rounded),
                    label: Text(
                      strings.uiFormat('unlockLifetimePrice', {
                        'price': snapshot.priceLabel,
                      }),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRestore,
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(strings.ui('restorePurchase')),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _remainingText(Duration duration) {
    final totalMinutes = duration.inMinutes.clamp(0, 24 * 60);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes dk';
    if (minutes == 0) return '$hours sa';
    return '$hours sa $minutes dk';
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
                                '${_formatAlertTime(item.timestampMs)}',
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

class _LiveMetricGrid extends StatelessWidget {
  const _LiveMetricGrid({
    required this.quality,
    required this.profile,
    required this.audioEnabled,
    required this.alertsActive,
    required this.alertsConnected,
  });

  final NetworkQualitySnapshot? quality;
  final MediaQualityProfile? profile;
  final bool audioEnabled;
  final bool alertsActive;
  final bool alertsConnected;

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
            ? strings.ui('notificationsOn')
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
  final family = alert.category;
  return switch (family) {
    AlertCategory.motion => strings.ui('motionDetectedTitle'),
    AlertCategory.audio => strings.ui('cryDetectedTitle'),
    AlertCategory.system => strings.notificationTitle,
  };
}

Color _alertColor(AlertEventDto alert) {
  final family = alert.category;
  return switch (family) {
    AlertCategory.motion => _amber,
    AlertCategory.audio => _pink,
    AlertCategory.system => _mint,
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              title ?? 'MimiCam',
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
const _amber = Color(0xFFFFD37B);

const _title = TextStyle(
    color: _navy, fontSize: 30, height: 1.08, fontWeight: FontWeight.w900);
const _subtitle = TextStyle(color: _slate, fontSize: 15.5, height: 1.25);
