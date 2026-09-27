import 'dart:async';

import '../../../core/async/serialized_async_executor.dart';

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
    this.operationTimeout = const Duration(seconds: 8),
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
            onStopAudio != null {
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'must be positive',
      );
    }
  }

  final Future<void> Function()? _onStart;
  final Future<void> Function()? _onStop;
  final Future<void> Function()? _onStartVideo;
  final Future<void> Function()? _onStopVideo;
  final Future<void> Function()? _onStartAudio;
  final Future<void> Function()? _onStopAudio;
  final Future<void> Function(MediaResourceDemand demand)? _onDemandChanged;
  final bool _usesIndependentResources;
  final Duration operationTimeout;

  final _operations = SerializedAsyncExecutor();
  final _pendingResourceOperations = <Future<void>>{};
  Future<void>? _disposeOperation;
  bool _closing = false;
  bool _shutdownComplete = false;
  MediaResourceDemand _activeDemand = MediaResourceDemand.none;
  MediaResourceDemand _requestedDemand = MediaResourceDemand.none;
  bool _suspended = false;
  bool _combinedMayBeActive = false;
  bool _videoMayBeActive = false;
  bool _audioMayBeActive = false;
  int _intentGeneration = 0;
  final _resourceRecoveryTimers = <_MediaResource, Timer>{};
  final _resourceRecoveryAttempts = <_MediaResource, int>{};

  bool get isActive => !_activeDemand.isEmpty;
  bool get videoActive => _activeDemand.video;
  bool get audioActive => _activeDemand.audio;
  MediaResourceDemand get activeDemand => _activeDemand;
  MediaResourceDemand get requestedDemand => _requestedDemand;
  bool get isSuspended => _suspended;

  Future<void> start() => reconcile(MediaResourceDemand.all);

  Future<void> stop() => reconcile(MediaResourceDemand.none);

  Future<void> reconcile(MediaResourceDemand demand) {
    if (_closing && !demand.isEmpty) {
      return Future<void>.error(StateError('Media runtime is closing.'));
    }
    _requestedDemand = demand;
    return _enqueue(
      _suspended ? MediaResourceDemand.none : demand,
      ++_intentGeneration,
    );
  }

  Future<void> suspend() {
    _suspended = true;
    return _enqueue(MediaResourceDemand.none, ++_intentGeneration);
  }

  Future<void> resume() {
    if (_closing) {
      return Future<void>.error(StateError('Media runtime is closing.'));
    }
    _suspended = false;
    return _enqueue(_requestedDemand, ++_intentGeneration);
  }

  /// Terminal ownership barrier used before another application role starts.
  ///
  /// A timeout during normal operation does not cancel native acquisition.
  /// Wait for those operations as well as the command queue, then release all
  /// resources. Failure remains retryable, but never re-enables acquisition.
  Future<void> dispose() {
    final current = _disposeOperation;
    if (current != null) return current;
    if (_shutdownComplete) return Future<void>.value();
    _closing = true;
    _suspended = true;
    _requestedDemand = MediaResourceDemand.none;
    ++_intentGeneration;
    for (final timer in _resourceRecoveryTimers.values) {
      timer.cancel();
    }
    _resourceRecoveryTimers.clear();
    _resourceRecoveryAttempts.clear();
    late final Future<void> operation;
    operation = _dispose().whenComplete(() {
      if (identical(_disposeOperation, operation)) _disposeOperation = null;
    });
    return _disposeOperation = operation;
  }

  Future<void> _dispose() async {
    await _operations.drain();
    // These futures settle even if the original operation reported a timeout.
    // A still-pending native operation makes shutdown unconfirmed, so callers
    // must keep the next role inactive until a subsequent attempt succeeds.
    await Future.wait(_pendingResourceOperations.toList())
        .timeout(operationTimeout);
    await _operations.run(() async {
      Object? firstError;
      StackTrace? firstStack;
      final resources = _usesIndependentResources
          ? [_MediaResource.video, _MediaResource.audio]
          : [_MediaResource.combined];
      for (final resource in resources) {
        final mayBeActive = switch (resource) {
          _MediaResource.video => _activeDemand.video || _videoMayBeActive,
          _MediaResource.audio => _activeDemand.audio || _audioMayBeActive,
          _MediaResource.combined =>
            !_activeDemand.isEmpty || _combinedMayBeActive,
        };
        if (!mayBeActive) continue;
        try {
          await _invokeResourceOperation(
            callback: switch (resource) {
              _MediaResource.video => _onStopVideo,
              _MediaResource.audio => _onStopAudio,
              _MediaResource.combined => _onStop,
            },
            resource: resource,
            starting: false,
            generation: _intentGeneration,
          );
          _markResourceInactive(resource);
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStack ??= stackTrace;
        }
      }
      try {
        await _publishActiveDemand(_intentGeneration);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStack!);
      }
    });
    await _operations.close();
    _shutdownComplete = true;
  }

  Future<void> _enqueue(MediaResourceDemand demand, int generation) {
    return _operations.run(() async {
      if (generation != _intentGeneration) return;
      await _apply(demand, generation);
    });
  }

  Future<void> _apply(
    MediaResourceDemand target,
    int generation,
  ) async {
    if (_usesIndependentResources) {
      await _applyIndependent(target, generation);
    } else {
      await _applyCombined(target, generation);
    }
    if (generation != _intentGeneration) return;
    await _publishActiveDemand(generation);
  }

  Future<void> _applyCombined(
    MediaResourceDemand target,
    int generation,
  ) async {
    if (target.isEmpty && _activeDemand.isEmpty && !_combinedMayBeActive) {
      return;
    }
    if (!target.isEmpty && !_activeDemand.isEmpty && !_combinedMayBeActive) {
      // A legacy combined source cannot represent video/audio independently,
      // but retaining the requested shape keeps runtime state truthful.
      _activeDemand = target;
      return;
    }
    if (!target.isEmpty) {
      _combinedMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStart,
          resource: _MediaResource.combined,
          starting: true,
          generation: generation,
        );
      } catch (_) {
        if (generation == _intentGeneration) {
          _combinedMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.combined);
        }
        rethrow;
      }
      if (generation != _intentGeneration) return;
      _activeDemand = target;
      _combinedMayBeActive = false;
      _resetResourceRecovery(_MediaResource.combined);
      return;
    }
    if (!_activeDemand.isEmpty || _combinedMayBeActive) {
      _combinedMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStop,
          resource: _MediaResource.combined,
          starting: false,
          generation: generation,
        );
      } catch (_) {
        if (generation == _intentGeneration) {
          _combinedMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.combined);
        }
        rethrow;
      }
      if (generation == _intentGeneration) {
        _activeDemand = MediaResourceDemand.none;
        _combinedMayBeActive = false;
        _resetResourceRecovery(_MediaResource.combined);
      }
    }
  }

  Future<void> _applyIndependent(
    MediaResourceDemand target,
    int generation,
  ) async {
    // Stop resources no longer demanded before acquiring new hardware. This
    // avoids a transient privacy indicator for the wrong media resource when
    // switching between video-only and audio-only sessions.
    if ((_activeDemand.video || _videoMayBeActive) && !target.video) {
      _videoMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStopVideo,
          resource: _MediaResource.video,
          starting: false,
          generation: generation,
        );
        if (generation == _intentGeneration) {
          _videoMayBeActive = false;
          _activeDemand = MediaResourceDemand(
            video: false,
            audio: _activeDemand.audio,
          );
          _resetResourceRecovery(_MediaResource.video);
        }
      } catch (_) {
        if (generation == _intentGeneration) {
          _videoMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.video);
        }
        rethrow;
      }
      if (generation != _intentGeneration) return;
    }
    if ((_activeDemand.audio || _audioMayBeActive) && !target.audio) {
      _audioMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStopAudio,
          resource: _MediaResource.audio,
          starting: false,
          generation: generation,
        );
        if (generation == _intentGeneration) {
          _audioMayBeActive = false;
          _activeDemand = MediaResourceDemand(
            video: _activeDemand.video,
            audio: false,
          );
          _resetResourceRecovery(_MediaResource.audio);
        }
      } catch (_) {
        if (generation == _intentGeneration) {
          _audioMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.audio);
        }
        rethrow;
      }
      if (generation != _intentGeneration) return;
    }
    if ((!_activeDemand.video || _videoMayBeActive) && target.video) {
      _videoMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStartVideo,
          resource: _MediaResource.video,
          starting: true,
          generation: generation,
        );
      } catch (_) {
        if (generation == _intentGeneration) {
          _videoMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.video);
        }
        rethrow;
      }
      if (generation != _intentGeneration) return;
      _videoMayBeActive = false;
      _resetResourceRecovery(_MediaResource.video);
      _activeDemand = MediaResourceDemand(
        video: true,
        audio: _activeDemand.audio,
      );
    }
    if ((!_activeDemand.audio || _audioMayBeActive) && target.audio) {
      _audioMayBeActive = true;
      try {
        await _invokeResourceOperation(
          callback: _onStartAudio,
          resource: _MediaResource.audio,
          starting: true,
          generation: generation,
        );
      } catch (_) {
        if (generation == _intentGeneration) {
          _audioMayBeActive = true;
          _scheduleResourceRecovery(_MediaResource.audio);
        }
        rethrow;
      }
      if (generation != _intentGeneration) return;
      _audioMayBeActive = false;
      _resetResourceRecovery(_MediaResource.audio);
      _activeDemand = MediaResourceDemand(
        video: _activeDemand.video,
        audio: true,
      );
    }
  }

  Future<void> _publishActiveDemand(int generation) async {
    final callback = _onDemandChanged;
    if (callback == null) return;
    final operation = Future<void>.sync(() => callback(_activeDemand));
    _trackNativeOperation(operation);
    var timedOut = false;
    operation.then<void>(
      (_) {
        if (timedOut) _scheduleDemandRepair();
      },
      onError: (Object _, StackTrace __) {
        if (timedOut) _scheduleDemandRepair();
      },
    );
    await operation.timeout(
      operationTimeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException(
          'Media demand callback timed out.',
          operationTimeout,
        );
      },
    );
  }

  Future<void> _invokeResourceOperation({
    required Future<void> Function()? callback,
    required _MediaResource resource,
    required bool starting,
    required int generation,
  }) async {
    if (callback == null) return;
    final operation = Future<void>.sync(callback);
    _trackNativeOperation(operation);
    var timedOut = false;
    operation.then<void>(
      (_) {
        if (timedOut) {
          _scheduleResourceRepair(
            resource: resource,
            starting: starting,
            outcome: _LateResourceOutcome.succeeded,
          );
        }
      },
      onError: (Object _, StackTrace __) {
        if (timedOut) {
          _scheduleResourceRepair(
            resource: resource,
            starting: starting,
            outcome: _LateResourceOutcome.failed,
          );
        }
      },
    );
    await operation.timeout(
      operationTimeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException(
          'Media ${starting ? 'start' : 'stop'} timed out for '
          '${resource.name}.',
          operationTimeout,
        );
      },
    );
  }

  void _trackNativeOperation(Future<void> operation) {
    late final Future<void> settled;
    settled = operation
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pendingResourceOperations.remove(settled));
    _pendingResourceOperations.add(settled);
  }

  void _scheduleResourceRepair({
    required _MediaResource resource,
    required bool starting,
    required _LateResourceOutcome outcome,
  }) {
    if (_closing) return;
    unawaited(_operations.run(() async {
      final target = _suspended ? MediaResourceDemand.none : _requestedDemand;
      final generation = _intentGeneration;
      final wanted = switch (resource) {
        _MediaResource.combined => !target.isEmpty,
        _MediaResource.video => target.video,
        _MediaResource.audio => target.audio,
      };
      if (starting) {
        if (outcome == _LateResourceOutcome.succeeded) {
          _markResourceConfirmedActive(resource, target);
          if (wanted) {
            await _publishActiveDemand(generation);
            return;
          }
        } else {
          _markResourceUncertain(resource, forceReassert: wanted);
        }
      } else {
        if (outcome == _LateResourceOutcome.succeeded) {
          _markResourceInactive(resource);
        } else {
          _markResourceUncertain(resource, forceReassert: wanted);
        }
      }
      await _apply(target, generation);
    }).catchError((Object _, StackTrace __) {}));
  }

  void _scheduleDemandRepair() {
    if (_closing) return;
    final observedGeneration = _intentGeneration;
    unawaited(_operations.run(() async {
      if (observedGeneration != _intentGeneration) return;
      await _publishActiveDemand(observedGeneration);
    }).catchError((Object _, StackTrace __) {}));
  }

  void _scheduleResourceRecovery(_MediaResource resource) {
    if (_closing) return;
    if (_resourceRecoveryTimers.containsKey(resource)) return;
    final attempt = _resourceRecoveryAttempts[resource] ?? 0;
    // Persistent native/permission failures must not wake the device and
    // re-open hardware ten times per second. Keep the first retry prompt,
    // then back off while retaining eventual cleanup of uncertain resources.
    final delayMs = (100 * (1 << attempt)).clamp(100, 5000);
    _resourceRecoveryAttempts[resource] = (attempt + 1).clamp(0, 6);
    _resourceRecoveryTimers[resource] = Timer(
      Duration(milliseconds: delayMs),
      () {
        _resourceRecoveryTimers.remove(resource);
        unawaited(_retryResourceRecovery(resource));
      },
    );
  }

  void _resetResourceRecovery(_MediaResource resource) {
    _resourceRecoveryTimers.remove(resource)?.cancel();
    _resourceRecoveryAttempts.remove(resource);
  }

  Future<void> _retryResourceRecovery(_MediaResource resource) async {
    final generation = _intentGeneration;
    final target = _suspended ? MediaResourceDemand.none : _requestedDemand;
    final wanted = switch (resource) {
      _MediaResource.combined => !target.isEmpty,
      _MediaResource.video => target.video,
      _MediaResource.audio => target.audio,
    };
    if (wanted) {
      _markResourceUncertain(resource, forceReassert: true);
    }
    try {
      await _operations.run(() async {
        if (generation != _intentGeneration) return;
        await _apply(target, generation);
      });
    } catch (_) {
      // The stop path retains uncertainty and schedules the next retry.
    }
  }

  void _markResourceConfirmedActive(
    _MediaResource resource,
    MediaResourceDemand target,
  ) {
    switch (resource) {
      case _MediaResource.combined:
        _combinedMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = target.isEmpty ? MediaResourceDemand.all : target;
      case _MediaResource.video:
        _videoMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = MediaResourceDemand(
          video: true,
          audio: _activeDemand.audio,
        );
      case _MediaResource.audio:
        _audioMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = MediaResourceDemand(
          video: _activeDemand.video,
          audio: true,
        );
    }
  }

  void _markResourceInactive(_MediaResource resource) {
    switch (resource) {
      case _MediaResource.combined:
        _combinedMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = MediaResourceDemand.none;
      case _MediaResource.video:
        _videoMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = MediaResourceDemand(
          video: false,
          audio: _activeDemand.audio,
        );
      case _MediaResource.audio:
        _audioMayBeActive = false;
        _resetResourceRecovery(resource);
        _activeDemand = MediaResourceDemand(
          video: _activeDemand.video,
          audio: false,
        );
    }
  }

  void _markResourceUncertain(
    _MediaResource resource, {
    required bool forceReassert,
  }) {
    switch (resource) {
      case _MediaResource.combined:
        _combinedMayBeActive = true;
        if (forceReassert) _activeDemand = MediaResourceDemand.none;
      case _MediaResource.video:
        _videoMayBeActive = true;
        if (forceReassert) {
          _activeDemand = MediaResourceDemand(
            video: false,
            audio: _activeDemand.audio,
          );
        }
      case _MediaResource.audio:
        _audioMayBeActive = true;
        if (forceReassert) {
          _activeDemand = MediaResourceDemand(
            video: _activeDemand.video,
            audio: false,
          );
        }
    }
  }
}

enum _LateResourceOutcome { succeeded, failed }

enum _MediaResource { combined, video, audio }
