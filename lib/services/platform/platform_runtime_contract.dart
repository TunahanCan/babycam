import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/async/serialized_async_executor.dart';

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
    this.playbackDemand = false,
    this.serverDemand = false,
    this.audioOutputActive = false,
    this.supportsServerInBackground = false,
    this.supportsAudioOutputInBackground = false,
    this.supportsMicrophoneInBackground = false,
    this.nativeServiceMediaAvailable = false,
    this.serviceOwnsMediaHardware = false,
    this.serviceOwnsNativeMediaHardware = false,
    this.externalCameraCaptureDemand = false,
    this.externalMicrophoneCaptureDemand = false,
    this.externalMediaCaptureDemand = false,
    this.nativeCameraRequested = false,
    this.nativeMicrophoneRequested = false,
    this.nativeCameraActive = false,
    this.nativeMicrophoneActive = false,
    this.nativeCameraError,
    this.nativeMicrophoneError,
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
      playbackDemand: map['playbackDemand'] as bool? ?? false,
      serverDemand: map['serverDemand'] as bool? ?? false,
      audioOutputActive: map['audioOutputActive'] as bool? ?? false,
      supportsServerInBackground:
          map['supportsServerInBackground'] as bool? ?? false,
      supportsAudioOutputInBackground:
          map['supportsAudioOutputInBackground'] as bool? ?? false,
      supportsMicrophoneInBackground:
          map['supportsMicrophoneInBackground'] as bool? ?? false,
      nativeServiceMediaAvailable:
          map['nativeServiceMediaAvailable'] as bool? ?? false,
      serviceOwnsMediaHardware:
          map['serviceOwnsMediaHardware'] as bool? ?? false,
      serviceOwnsNativeMediaHardware:
          map['serviceOwnsNativeMediaHardware'] as bool? ?? false,
      externalCameraCaptureDemand:
          map['externalCameraCaptureDemand'] as bool? ?? false,
      externalMicrophoneCaptureDemand:
          map['externalMicrophoneCaptureDemand'] as bool? ?? false,
      externalMediaCaptureDemand:
          map['externalMediaCaptureDemand'] as bool? ?? false,
      nativeCameraRequested: map['nativeCameraRequested'] as bool? ?? false,
      nativeMicrophoneRequested:
          map['nativeMicrophoneRequested'] as bool? ?? false,
      nativeCameraActive: map['nativeCameraActive'] as bool? ?? false,
      nativeMicrophoneActive: map['nativeMicrophoneActive'] as bool? ?? false,
      nativeCameraError: map['nativeCameraError']?.toString(),
      nativeMicrophoneError: map['nativeMicrophoneError']?.toString(),
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
  final bool playbackDemand;
  final bool serverDemand;
  final bool audioOutputActive;
  final bool supportsServerInBackground;
  final bool supportsAudioOutputInBackground;
  final bool supportsMicrophoneInBackground;
  final bool nativeServiceMediaAvailable;
  final bool serviceOwnsMediaHardware;
  final bool serviceOwnsNativeMediaHardware;
  final bool externalCameraCaptureDemand;
  final bool externalMicrophoneCaptureDemand;
  final bool externalMediaCaptureDemand;
  final bool nativeCameraRequested;
  final bool nativeMicrophoneRequested;
  final bool nativeCameraActive;
  final bool nativeMicrophoneActive;
  final String? nativeCameraError;
  final String? nativeMicrophoneError;
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
            ? serviceOwnsMediaHardware
                ? externalMediaCaptureDemand
                    ? 'Android foreground service WebRTC medya yakalayıcısını koruyor.'
                    : 'Android foreground service oda medyasını çalışır durumda tutuyor.'
                : 'Android foreground service medya donanımını hazırlıyor.'
            : 'Android arka plan talebi için foreground service görünürken başlatılmalıdır.',
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

  bool get requiresMediaPause =>
      type == 'mediaPauseRequired' ||
      (type == 'snapshot' &&
          details['platform'] == 'ios' &&
          (details['applicationState'] == 'inactive' ||
              details['applicationState'] == 'background'));
  bool get requestsMediaRecovery =>
      type == 'mediaRecoveryRequested' ||
      (type == 'snapshot' &&
          details['platform'] == 'ios' &&
          details['applicationState'] == 'foregroundActive');
  bool get isAudioLifecycleEvent => type.startsWith('audio');
  bool get isUnrecoverableAudioOutputLoss =>
      (type == 'audioFocusLost' && details['permanent'] == true) ||
      (type == 'audioInterruptionEnded' && details['recovered'] == false) ||
      (type == 'audioMediaServicesReset' && details['recovered'] == false) ||
      (type == 'audioOutputResumedFromBackground' &&
          details['recovered'] == false);
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
    bool playback = false,
    bool? nativeCameraCapture,
    bool? nativeMicrophoneCapture,
  }) {
    final serviceCameraCapture = camera && (nativeCameraCapture ?? camera);
    final serviceMicrophoneCapture =
        microphone && (nativeMicrophoneCapture ?? microphone);
    return _methodChannel.invokeMethod<void>('setMediaDemand', {
      'active': active,
      'camera': camera,
      'microphone': microphone,
      'playback': playback,
      'nativeCameraCapture': serviceCameraCapture,
      'nativeMicrophoneCapture': serviceMicrophoneCapture,
    });
  }

  /// Publishes room-server ownership to the native lifecycle layer.
  ///
  /// Android uses it to own the foreground host lease. iOS uses it together
  /// with active microphone demand to report its real background capability.
  Future<void> setServerDemand({required bool active}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('setServerDemand', {
        'active': active,
      });
    } on MissingPluginException {
      // Unit tests and older Android shells do not own the server lifecycle.
    }
  }

  static PlatformRuntimeSnapshot _fallbackSnapshot() {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => PlatformRuntimeKind.android,
      TargetPlatform.iOS => PlatformRuntimeKind.ios,
      _ => PlatformRuntimeKind.other,
    };
    return PlatformRuntimeSnapshot(
      platform: platform,
      applicationState: 'unknown',
      // No native method-channel implementation is available on this target,
      // so the fallback remains deliberately conservative.
      supportsCameraInBackground: false,
      cameraRequiresForegroundStart: true,
      backgroundRecoveryAfterProcessDeath: false,
      foregroundServiceActive: false,
      cameraDemand: false,
      microphoneDemand: false,
      playbackDemand: false,
      serverDemand: false,
      audioOutputActive: false,
      supportsServerInBackground: false,
      supportsAudioOutputInBackground: false,
      serviceOwnsMediaHardware: false,
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
    Future<void> Function(PlatformRuntimeEvent event)? onAudioOutputLost,
    void Function(PlatformRuntimeEvent event)? onTelemetry,
  })  : _events = events,
        _pauseMedia = pauseMedia,
        _recoverMedia = recoverMedia,
        _onAudioOutputLost = onAudioOutputLost,
        _onTelemetry = onTelemetry;

  final Stream<PlatformRuntimeEvent> _events;
  final Future<void> Function(String reason) _pauseMedia;
  final Future<void> Function(String reason) _recoverMedia;
  final Future<void> Function(PlatformRuntimeEvent event)? _onAudioOutputLost;
  final void Function(PlatformRuntimeEvent event)? _onTelemetry;
  StreamSubscription<PlatformRuntimeEvent>? _subscription;
  final _operations = SerializedAsyncExecutor();
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
    try {
      _onTelemetry?.call(event);
    } catch (_) {
      // Telemetry must never block the resource lifecycle state machine.
    }
    unawaited(
      _operations.run(() => _handle(event)).catchError((_) {
        // Native lifecycle failures are retried by later platform events.
      }),
    );
  }

  Future<void> _handle(PlatformRuntimeEvent event) async {
    if (_disposed) return;
    if (event.isUnrecoverableAudioOutputLoss) {
      await _onAudioOutputLost?.call(event);
    }
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
    await _operations.drain();
  }
}
