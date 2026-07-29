import 'dart:async';
import 'dart:math';

import '../../core/media/adaptive_media_profile.dart';
import '../../features/server/media/webrtc/webrtc_server_gateway.dart';
import 'media_resource_governor.dart';

typedef ResourceMonitoringProbe = bool Function();
typedef ResourceProfileRefresh = Future<void> Function();
typedef ResourceWatchdogErrorHandler = void Function(Object error);

/// Owns resource-decision hysteresis, watchdog scheduling and WebRTC policy
/// translation. MiuCamServer supplies measurements and applies the resulting
/// profile, while this coordinator keeps the state-machine mechanics local.
class ServerResourcePolicyCoordinator {
  ServerResourcePolicyCoordinator({
    required MediaResourceGovernor governor,
    required ResourceMonitoringProbe monitoringRequired,
    required ResourceProfileRefresh refreshProfile,
    required void Function() onMonitoringIdle,
    required ResourceWatchdogErrorHandler onWatchdogError,
    Duration watchdogInterval = const Duration(seconds: 10),
    MediaResourceDecisionStabilizer? stabilizer,
  })  : _governor = governor,
        _stabilizer = stabilizer ?? MediaResourceDecisionStabilizer(),
        _watchdog = ServerResourceWatchdog(
          monitoringRequired: monitoringRequired,
          refreshProfile: refreshProfile,
          onMonitoringIdle: onMonitoringIdle,
          onError: onWatchdogError,
          interval: watchdogInterval,
        );

  final MediaResourceGovernor _governor;
  final MediaResourceDecisionStabilizer _stabilizer;
  final ServerResourceWatchdog _watchdog;

  MediaResourceGovernorDecision evaluate(MediaResourceGovernorInput input) =>
      _stabilizer.stabilize(_governor.evaluate(input));

  void resetDecision() => _stabilizer.reset();

  void reconcileWatchdog() => _watchdog.reconcile();

  Future<void> refreshNow() => _watchdog.refreshNow();

  void dispose() => _watchdog.dispose();

  WebRtcMediaPolicy webRtcPolicyFor(
    MediaQualityProfile profile,
    MediaResourceGovernorDecision decision,
  ) {
    final pixelsPerSecond = profile.width * profile.height * profile.targetFps;
    final bitrate =
        (pixelsPerSecond * .10).round().clamp(120000, 2500000).toInt();
    const sourcePixels = 1280 * 720;
    final targetPixels = max(1, profile.width * profile.height);
    final scale = sqrt(sourcePixels / targetPixels).clamp(1.0, 4.0).toDouble();
    return WebRtcMediaPolicy(
      maxVideoBitrateBps: bitrate,
      maxVideoFrameRate: profile.targetFps,
      scaleResolutionDownBy: scale,
      videoEnabled: !decision.audioOnly,
    );
  }
}

/// Periodically refreshes resource measurements while media is active.
/// Refreshes never overlap, and a stopped activity probe cancels the timer
/// immediately even if an earlier refresh is still completing.
class ServerResourceWatchdog {
  ServerResourceWatchdog({
    required ResourceMonitoringProbe monitoringRequired,
    required ResourceProfileRefresh refreshProfile,
    required void Function() onMonitoringIdle,
    required ResourceWatchdogErrorHandler onError,
    required Duration interval,
  })  : _monitoringRequired = monitoringRequired,
        _refreshProfile = refreshProfile,
        _onMonitoringIdle = onMonitoringIdle,
        _onError = onError,
        _interval = interval;

  final ResourceMonitoringProbe _monitoringRequired;
  final ResourceProfileRefresh _refreshProfile;
  final void Function() _onMonitoringIdle;
  final ResourceWatchdogErrorHandler _onError;
  final Duration _interval;

  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false;

  bool get isScheduled => _timer != null;
  bool get isRefreshing => _inFlight != null;

  void reconcile() {
    if (_disposed) return;
    if (!_monitoringRequired()) {
      _timer?.cancel();
      _timer = null;
      _onMonitoringIdle();
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) {
      unawaited(refreshNow());
    });
    unawaited(refreshNow());
  }

  Future<void> refreshNow() {
    if (_disposed) return Future<void>.value();
    final current = _inFlight;
    if (current != null) return current;

    late final Future<void> refresh;
    refresh = Future<void>.sync(_refreshProfile).catchError((Object error) {
      _onError(error);
    }).whenComplete(() {
      if (identical(_inFlight, refresh)) _inFlight = null;
      reconcile();
    });
    _inFlight = refresh;
    return refresh;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
