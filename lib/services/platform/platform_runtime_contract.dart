import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PlatformRuntimeKind { android, ios, other }

class PlatformRuntimeSnapshot {
  const PlatformRuntimeSnapshot({
    required this.platform,
    required this.applicationState,
    required this.supportsCameraInBackground,
    required this.cameraRequiresForegroundStart,
    required this.backgroundRecoveryAfterProcessDeath,
    required this.foregroundServiceActive,
    required this.cameraDemand,
    required this.microphoneDemand,
    required this.activityAttached,
    required this.serviceOwnsEngine,
    required this.engineAvailable,
    this.lastServiceStopReason,
    this.contractMessage,
  });

  factory PlatformRuntimeSnapshot.fromMap(Map<Object?, Object?> map) {
    final platformName = map['platform']?.toString();
    return PlatformRuntimeSnapshot(
      platform: switch (platformName) {
        'android' => PlatformRuntimeKind.android,
        'ios' => PlatformRuntimeKind.ios,
        _ => PlatformRuntimeKind.other,
      },
      applicationState: map['applicationState']?.toString() ?? 'unknown',
      supportsCameraInBackground:
          map['supportsCameraInBackground'] as bool? ?? false,
      cameraRequiresForegroundStart:
          map['cameraRequiresForegroundStart'] as bool? ?? true,
      backgroundRecoveryAfterProcessDeath:
          map['backgroundRecoveryAfterProcessDeath'] as bool? ?? false,
      foregroundServiceActive: map['foregroundServiceActive'] as bool? ?? false,
      cameraDemand: map['cameraDemand'] as bool? ?? false,
      microphoneDemand: map['microphoneDemand'] as bool? ?? false,
      activityAttached: map['activityAttached'] as bool? ?? false,
      serviceOwnsEngine: map['serviceOwnsEngine'] as bool? ?? false,
      engineAvailable: map['engineAvailable'] as bool? ?? false,
      lastServiceStopReason: map['lastServiceStopReason']?.toString(),
      contractMessage: map['contractMessage']?.toString(),
    );
  }

  final PlatformRuntimeKind platform;
  final String applicationState;
  final bool supportsCameraInBackground;
  final bool cameraRequiresForegroundStart;
  final bool backgroundRecoveryAfterProcessDeath;
  final bool foregroundServiceActive;
  final bool cameraDemand;
  final bool microphoneDemand;
  final bool activityAttached;
  final bool serviceOwnsEngine;
  final bool engineAvailable;
  final String? lastServiceStopReason;
  final String? contractMessage;

  bool get cameraMustPauseWhenBackgrounded =>
      platform == PlatformRuntimeKind.ios && !supportsCameraInBackground;

  String get userVisibleContract =>
      contractMessage ??
      switch (platform) {
        PlatformRuntimeKind.ios =>
          'iOS kamera yayını için MimiCam ön planda ve ekran açık kalmalıdır.',
        PlatformRuntimeKind.android => foregroundServiceActive
            ? 'Android foreground service oda yayınını çalışır durumda tutuyor.'
            : 'Android arka plan yayını için foreground service başlatılmalıdır.',
        PlatformRuntimeKind.other =>
          'Bu platformda arka plan kamera çalışması desteklenmiyor.',
      };
}

class PlatformRuntimeEvent {
  const PlatformRuntimeEvent({
    required this.type,
    required this.timestampMs,
    required this.sequence,
    required this.details,
  });

  factory PlatformRuntimeEvent.fromMap(Map<Object?, Object?> map) {
    final details = <String, Object?>{};
    for (final entry in map.entries) {
      if (entry.key is! String ||
          entry.key == 'type' ||
          entry.key == 'timestampMs' ||
          entry.key == 'sequence') {
        continue;
      }
      details[entry.key as String] = entry.value;
    }
    return PlatformRuntimeEvent(
      type: map['type']?.toString() ?? 'unknown',
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      details: Map.unmodifiable(details),
    );
  }

  final String type;
  final int timestampMs;
  final int sequence;
  final Map<String, Object?> details;

  bool get requiresMediaPause => type == 'mediaPauseRequired';
  bool get requestsMediaRecovery => type == 'mediaRecoveryRequested';
  bool get isAudioLifecycleEvent => type.startsWith('audio');
}

class PlatformRuntimeContract {
  const PlatformRuntimeContract({
    MethodChannel methodChannel =
        const MethodChannel('mimicam/platform_runtime'),
    EventChannel eventChannel =
        const EventChannel('mimicam/platform_runtime_events'),
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Future<PlatformRuntimeSnapshot> snapshot() async {
    try {
      final map = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'snapshot',
      );
      if (map != null) return PlatformRuntimeSnapshot.fromMap(map);
    } on MissingPluginException {
      // Unit tests and unsupported desktop targets use a conservative snapshot.
    }
    return _fallbackSnapshot();
  }

  Stream<PlatformRuntimeEvent> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => PlatformRuntimeEvent.fromMap(
            Map<Object?, Object?>.from(event as Map),
          ));

  Future<void> setMediaDemand({
    required bool active,
    required bool camera,
    required bool microphone,
  }) =>
      _methodChannel.invokeMethod<void>('setMediaDemand', {
        'active': active,
        'camera': camera,
        'microphone': microphone,
      });

  static PlatformRuntimeSnapshot _fallbackSnapshot() {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => PlatformRuntimeKind.android,
      TargetPlatform.iOS => PlatformRuntimeKind.ios,
      _ => PlatformRuntimeKind.other,
    };
    return PlatformRuntimeSnapshot(
      platform: platform,
      applicationState: 'unknown',
      supportsCameraInBackground: platform == PlatformRuntimeKind.android,
      cameraRequiresForegroundStart: true,
      backgroundRecoveryAfterProcessDeath: false,
      foregroundServiceActive: false,
      cameraDemand: false,
      microphoneDemand: false,
      activityAttached: false,
      serviceOwnsEngine: false,
      engineAvailable: false,
    );
  }
}

/// Serializes native lifecycle events so a background pause and foreground
/// recovery cannot race each other. The server runtime supplies the actual
/// camera stop/restart callbacks; the platform layer supplies the policy.
class PlatformMediaLifecycleCoordinator {
  PlatformMediaLifecycleCoordinator({
    required Stream<PlatformRuntimeEvent> events,
    required Future<void> Function(String reason) pauseMedia,
    required Future<void> Function(String reason) recoverMedia,
    void Function(PlatformRuntimeEvent event)? onTelemetry,
  })  : _events = events,
        _pauseMedia = pauseMedia,
        _recoverMedia = recoverMedia,
        _onTelemetry = onTelemetry;

  final Stream<PlatformRuntimeEvent> _events;
  final Future<void> Function(String reason) _pauseMedia;
  final Future<void> Function(String reason) _recoverMedia;
  final void Function(PlatformRuntimeEvent event)? _onTelemetry;
  StreamSubscription<PlatformRuntimeEvent>? _subscription;
  Future<void> _pending = Future.value();
  bool _pausedByPlatform = false;
  bool _disposed = false;

  bool get pausedByPlatform => _pausedByPlatform;

  void start() {
    if (_disposed || _subscription != null) return;
    _subscription = _events.listen(
      _enqueue,
      onError: (Object _, StackTrace __) {
        // Tests, desktop builds and an engine that is still attaching may not
        // have the native EventChannel. Lifecycle support remains best effort
        // there; Android/iOS production engines register it at startup.
      },
    );
  }

  void _enqueue(PlatformRuntimeEvent event) {
    _onTelemetry?.call(event);
    _pending = _pending.then((_) => _handle(event));
  }

  Future<void> _handle(PlatformRuntimeEvent event) async {
    if (_disposed) return;
    final reason = event.details['reason']?.toString() ?? event.type;
    if (event.requiresMediaPause && !_pausedByPlatform) {
      await _pauseMedia(reason);
      _pausedByPlatform = true;
      return;
    }
    if (event.requestsMediaRecovery && _pausedByPlatform) {
      await _recoverMedia(reason);
      _pausedByPlatform = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _pending;
  }
}
