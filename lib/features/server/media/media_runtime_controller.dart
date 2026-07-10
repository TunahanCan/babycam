import 'dart:async';

class MediaResourceDemand {
  const MediaResourceDemand({
    required this.video,
    required this.audio,
    bool? serviceVideoCapture,
    bool? serviceAudioCapture,
  })  : assert(serviceVideoCapture != true || video),
        assert(serviceAudioCapture != true || audio),
        serviceVideoCapture = serviceVideoCapture ?? video,
        serviceAudioCapture = serviceAudioCapture ?? audio;

  static const none = MediaResourceDemand(video: false, audio: false);
  static const all = MediaResourceDemand(video: true, audio: true);

  final bool video;
  final bool audio;
  final bool serviceVideoCapture;
  final bool serviceAudioCapture;

  bool get isEmpty => !video && !audio;

  @override
  bool operator ==(Object other) =>
      other is MediaResourceDemand &&
      other.video == video &&
      other.audio == audio &&
      other.serviceVideoCapture == serviceVideoCapture &&
      other.serviceAudioCapture == serviceAudioCapture;

  @override
  int get hashCode =>
      Object.hash(video, audio, serviceVideoCapture, serviceAudioCapture);

  @override
  String toString() => 'MediaResourceDemand(video: $video, audio: $audio, '
      'serviceVideoCapture: $serviceVideoCapture, '
      'serviceAudioCapture: $serviceAudioCapture)';
}

/// Serial, race-safe reconciler for independently owned camera and microphone
/// resources.
///
/// Calls are queued in request order. A stop requested while a platform start
/// is in flight therefore waits for that start and deterministically releases
/// it. Failed operations do not poison the queue; a later demand can retry or
/// shut down resources that did start successfully.
class MediaRuntimeController {
  MediaRuntimeController({
    Future<void> Function()? onStart,
    Future<void> Function()? onStop,
    Future<void> Function()? onStartVideo,
    Future<void> Function()? onStopVideo,
    Future<void> Function()? onStartAudio,
    Future<void> Function()? onStopAudio,
    Future<void> Function(MediaResourceDemand demand)? onDemandChanged,
  })  : _onStart = onStart,
        _onStop = onStop,
        _onStartVideo = onStartVideo,
        _onStopVideo = onStopVideo,
        _onStartAudio = onStartAudio,
        _onStopAudio = onStopAudio,
        _onDemandChanged = onDemandChanged,
        _usesIndependentResources = onStartVideo != null ||
            onStopVideo != null ||
            onStartAudio != null ||
            onStopAudio != null;

  final Future<void> Function()? _onStart;
  final Future<void> Function()? _onStop;
  final Future<void> Function()? _onStartVideo;
  final Future<void> Function()? _onStopVideo;
  final Future<void> Function()? _onStartAudio;
  final Future<void> Function()? _onStopAudio;
  final Future<void> Function(MediaResourceDemand demand)? _onDemandChanged;
  final bool _usesIndependentResources;

  Future<void> _tail = Future<void>.value();
  MediaResourceDemand _activeDemand = MediaResourceDemand.none;
  MediaResourceDemand _requestedDemand = MediaResourceDemand.none;
  bool _suspended = false;

  bool get isActive => !_activeDemand.isEmpty;
  bool get videoActive => _activeDemand.video;
  bool get audioActive => _activeDemand.audio;
  MediaResourceDemand get activeDemand => _activeDemand;
  MediaResourceDemand get requestedDemand => _requestedDemand;
  bool get isSuspended => _suspended;

  Future<void> start() => reconcile(MediaResourceDemand.all);

  Future<void> stop() => reconcile(MediaResourceDemand.none);

  Future<void> reconcile(MediaResourceDemand demand) {
    _requestedDemand = demand;
    return _enqueue(_suspended ? MediaResourceDemand.none : demand);
  }

  Future<void> suspend() {
    _suspended = true;
    return _enqueue(MediaResourceDemand.none);
  }

  Future<void> resume() {
    _suspended = false;
    return _enqueue(_requestedDemand);
  }

  Future<void> _enqueue(MediaResourceDemand demand) {
    final operation = _tail.then<void>(
      (_) => _apply(demand),
      onError: (_) => _apply(demand),
    );
    // Keep a non-throwing queue tail so one platform error does not prevent a
    // later stop/retry. The caller still receives [operation]'s real error.
    _tail = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> _apply(MediaResourceDemand target) async {
    if (_usesIndependentResources) {
      await _applyIndependent(target);
      await _onDemandChanged?.call(_activeDemand);
      return;
    }
    await _applyCombined(target);
    await _onDemandChanged?.call(_activeDemand);
  }

  Future<void> _applyCombined(MediaResourceDemand target) async {
    if (target.isEmpty == _activeDemand.isEmpty) {
      // A legacy combined source cannot represent video/audio independently,
      // but retaining the requested shape keeps runtime state truthful.
      if (!target.isEmpty) _activeDemand = target;
      return;
    }
    if (!target.isEmpty) {
      await (_onStart?.call() ?? Future<void>.value());
      _activeDemand = target;
      return;
    }
    try {
      await (_onStop?.call() ?? Future<void>.value());
    } finally {
      _activeDemand = MediaResourceDemand.none;
    }
  }

  Future<void> _applyIndependent(MediaResourceDemand target) async {
    // Stop resources no longer demanded before acquiring new hardware. This
    // avoids a transient privacy indicator for the wrong media resource when
    // switching between video-only and audio-only sessions.
    if (_activeDemand.video && !target.video) {
      await (_onStopVideo?.call() ?? Future<void>.value());
      _activeDemand = MediaResourceDemand(
        video: false,
        audio: _activeDemand.audio,
      );
    }
    if (_activeDemand.audio && !target.audio) {
      await (_onStopAudio?.call() ?? Future<void>.value());
      _activeDemand = MediaResourceDemand(
        video: _activeDemand.video,
        audio: false,
      );
    }
    if (!_activeDemand.video && target.video) {
      await (_onStartVideo?.call() ?? Future<void>.value());
      _activeDemand = MediaResourceDemand(
        video: true,
        audio: _activeDemand.audio,
      );
    }
    if (!_activeDemand.audio && target.audio) {
      await (_onStartAudio?.call() ?? Future<void>.value());
      _activeDemand = MediaResourceDemand(
        video: _activeDemand.video,
        audio: true,
      );
    }
  }
}
