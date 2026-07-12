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
  late bool _keepScreenAwake;
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
    if (state.alertsActive) {
      await widget.runtime.stopAlertListening();
      return;
    }
    final started = await widget.runtime.startAlertListening();
    if (!started && mounted) {
      final strings = AppStrings.of(context);
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
        widget.runtime.alerts.isEmpty ? null : widget.runtime.alerts.last;
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
              strings.ui('nightClockAudioAlertsOn'),
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 88),
        children: [
          _Top(
            trailing: _ConnectedBadge(
              text: state.activeStream == null
                  ? strings.ui('measuring')
                  : strings.ui('connected'),
            ),
          ),
          const SizedBox(height: 14),
          _LiveOverviewCard(session: state.session, state: state),
          if (state.broadcastAccess != null) ...[
            const SizedBox(height: 14),
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
          ),
          const SizedBox(height: 16),
          _SectionLabel(
            icon: Icons.insights_rounded,
            title: strings.ui('roomStatus'),
            subtitle: strings.ui('liveStreamConnectedSubtitle'),
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
            title: strings.ui('watchPreferences'),
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
              onError: (error) => _showSnack(error.toString()),
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
                  onChanged: (_) => unawaited(_toggleNotifications(state)),
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

  Future<void> _refreshStreamSession() =>
      _restartLiveWatch(audioEnabled: _audioEnabled);

  Future<void> _restartLiveWatch({required bool audioEnabled}) async {
    final operationGeneration = ++_screenOperationGeneration;
    await widget.runtime.restartWatching(audioEnabled: audioEnabled);
    if (!_isCurrentScreenOperation(operationGeneration)) return;
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

class _LiveOverviewCard extends StatelessWidget {
  const _LiveOverviewCard({required this.session, required this.state});

  final PairingSession? session;
  final ClientRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isLive = state.activeStream != null;
    final title = session?.deviceName.trim().isNotEmpty == true
        ? session!.deviceName
        : strings.ui('liveWatching');
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF162B4A), Color(0xFF264D68)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24162B4A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isLive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: isLive ? _mint : Colors.white70,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLive ? _mint : Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        isLive
                            ? strings.ui('liveStreamConnectedSubtitle')
                            : strings.ui('measuring'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isLive ? Icons.check_circle_rounded : Icons.sync_rounded,
            color: isLive ? _mint : Colors.white70,
            size: 22,
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AspectRatio(
      aspectRatio: 16 / 9,
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
            ),
            const Positioned(top: 10, left: 12, child: _LiveBadge()),
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
  });

  final PairingSession? session;
  final ActiveStreamSession? activeStream;
  final bool audioEnabled;
  final ClientStreamHealthState? streamHealthState;
  final BoxFit fit;
  final Object? error;
  final Future<void> Function() onSessionRefreshRequired;
  final ValueChanged<Object> onFatalError;

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
      if (error != null) return _StreamErrorPanel(message: error.toString());
      return const _StreamPlaceholder();
    }
    final webRtc = widget.activeStream?.webRtc;
    if (widget.activeStream?.usesWebRtc == true && webRtc != null) {
      return RTCVideoView(
        webRtc.videoRenderer,
        objectFit: widget.fit == BoxFit.cover
            ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
            : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        placeholderBuilder: (_) => const _StreamPlaceholder(),
      );
    }
    final streamError = _streamError;
    if (_latestFrame == null && streamError != null) {
      return _StreamErrorPanel(message: streamError.toString());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ClientVideoViewer(
          frame: _latestFrame,
          error: streamError ?? widget.error,
          fit: widget.fit,
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
            value: !alertsActive
                ? strings.ui('notificationsOff')
                : alertsConnected
                    ? strings.ui('notificationsOn')
                    : strings.ui('clientTitleReconnecting'),
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
      height: 76,
      width: double.infinity,
      child: FilledButton(
        onPressed: spec.onTap,
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
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _navy,
        ),
        const Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: _pink, size: 9),
                SizedBox(width: 6),
                Text(
                  'MimiCam',
                  style: TextStyle(
                    color: _pink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
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
  const _ConnectedBadge({required this.text, this.dark = false});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: dark ? Colors.white.withValues(alpha: .10) : _mintSoft,
        shape: StadiumBorder(
          side: BorderSide(
            color: dark ? Colors.white24 : _mint.withValues(alpha: .45),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Color(0xFF42B883), size: 7),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF2A9474),
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
