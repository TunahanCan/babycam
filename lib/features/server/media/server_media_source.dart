import 'dart:async';
import 'dart:typed_data';

import '../../../analysis/video/luma_frame.dart';

typedef ServerVideoFrameSink = void Function(Uint8List jpeg);
typedef ServerAudioChunkSink = void Function(Uint8List pcm16le);
typedef ServerMediaErrorSink = void Function(Object error, StackTrace stack);

/// Signals that media delivery lost temporal continuity even if native capture
/// recovers automatically.
///
/// Consumers must reset both audio and video evidence before accepting frames
/// from the replacement stream. This prevents an alert episode from spanning
/// an unobserved capture interval.
class ServerMediaStreamDiscontinuity implements Exception {
  const ServerMediaStreamDiscontinuity(this.reason);

  final String reason;

  @override
  String toString() => 'ServerMediaStreamDiscontinuity: $reason';
}

/// Capture metadata for the audio chunk currently being delivered by a
/// [ServerMediaSource].
///
/// [discontinuityBefore] means temporal evidence from earlier chunks must not
/// be joined to this chunk. Native sources set it when capture restarts, a
/// bounded transport queue drops audio, or the monotonic capture clock reveals
/// a gap.
class ServerAudioChunkMetadata {
  const ServerAudioChunkMetadata({
    required this.capturedAtMs,
    this.capturedAtMonoUs,
    this.sequence,
    this.sampleRate,
    this.channels,
    this.discontinuityBefore = false,
  });

  final int capturedAtMs;
  final int? capturedAtMonoUs;
  final int? sequence;
  final int? sampleRate;
  final int? channels;
  final bool discontinuityBefore;
}

/// Optional timing plane for sources whose capture metadata would otherwise be
/// lost by the byte-only [ServerAudioChunkSink] compatibility API.
///
/// The value is non-null only during the synchronous [ServerAudioChunkSink]
/// invocation. This keeps existing media sources unchanged while allowing
/// service-owned/native capture to preserve timestamps and drop boundaries.
abstract interface class ServerAudioChunkMetadataSource {
  ServerAudioChunkMetadata? get currentAudioChunkMetadata;
}

abstract class ServerMediaSource {
  bool get isActive;
  ServerMediaSourceSnapshot get snapshot;

  Future<void> start({
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) =>
      reconcile(
        video: true,
        audio: true,
        onVideoFrame: onVideoFrame,
        onAudioChunk: onAudioChunk,
        onError: onError,
      );

  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  });

  Future<void> stop();
  void resetDiagnostics();
}

/// Optional local-preview surface for media engines that do not expose a
/// Flutter camera controller (for example Android's service-owned CameraX
/// engine).
abstract interface class ServerJpegPreviewSource {
  Uint8List? get latestPreviewFrame;
  Stream<Uint8List> get previewFrames;
}

/// Optional analysis plane exposed by service-owned/native video sources.
/// Keeping this separate from JPEG delivery avoids decoding compressed frames
/// on the Dart isolate just to run motion detection.
abstract interface class ServerLumaFrameSource {
  Stream<LumaFrame> get lumaFrames;
}

/// Optional capture/encode policy sink for native media engines. The thermal
/// governor uses this to reduce work at the producer instead of dropping
/// already-encoded frames after they cross the platform channel.
abstract interface class ServerMediaPolicySink {
  Future<void> applyMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  });
}

class ServerMediaSourceSnapshot {
  const ServerMediaSourceSnapshot({
    required this.active,
    required this.videoFrames,
    required this.audioChunks,
    required this.lastVideoFrameAtMs,
    required this.lastVideoFrameBytes,
    required this.lastAudioChunkAtMs,
    required this.lastAudioChunkBytes,
    required this.lastError,
  });

  final bool active;
  final int videoFrames;
  final int audioChunks;
  final int? lastVideoFrameAtMs;
  final int lastVideoFrameBytes;
  final int? lastAudioChunkAtMs;
  final int lastAudioChunkBytes;
  final String? lastError;

  Map<String, Object?> toJson() => {
        'active': active,
        'videoFrames': videoFrames,
        'audioChunks': audioChunks,
        'lastVideoFrameAtMs': lastVideoFrameAtMs,
        'lastVideoFrameBytes': lastVideoFrameBytes,
        'lastAudioChunkAtMs': lastAudioChunkAtMs,
        'lastAudioChunkBytes': lastAudioChunkBytes,
        'lastError': lastError,
      };
}
