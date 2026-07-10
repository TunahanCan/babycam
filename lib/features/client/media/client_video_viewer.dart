import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/media/media_session_telemetry.dart';

class ClientVideoViewer extends StatefulWidget {
  const ClientVideoViewer({
    super.key,
    required this.frame,
    this.error,
    this.fit = BoxFit.cover,
  });

  final Uint8List? frame;
  final Object? error;
  final BoxFit fit;

  @override
  State<ClientVideoViewer> createState() => _ClientVideoViewerState();
}

class _ClientVideoViewerState extends State<ClientVideoViewer> {
  late final LatestVideoFramePresentationQueue<ui.Image> _presentationQueue;
  ui.Image? _presentedImage;
  Object? _decodeError;

  @override
  void initState() {
    super.initState();
    _presentationQueue = LatestVideoFramePresentationQueue<ui.Image>(
      decode: _decodeJpeg,
      onPresented: _present,
      onDiscarded: (image) => image.dispose(),
      onError: _handleDecodeError,
      onCoalesced: () => MediaSessionTelemetry.shared.increment(
        MediaMetricName.videoCoalescedPresentationCount,
      ),
    );
    final frame = widget.frame;
    if (frame != null) _presentationQueue.offer(frame);
  }

  @override
  void didUpdateWidget(covariant ClientVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.frame, widget.frame)) return;
    final frame = widget.frame;
    if (frame == null) {
      _presentationQueue.clear();
      final previous = _presentedImage;
      _presentedImage = null;
      _decodeError = null;
      previous?.dispose();
      return;
    }
    _presentationQueue.offer(frame);
  }

  @override
  void dispose() {
    _presentationQueue.dispose();
    _presentedImage?.dispose();
    _presentedImage = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _presentedImage;
    if (image != null) {
      return RawImage(
        image: image,
        fit: widget.fit,
        filterQuality: FilterQuality.medium,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: widget.error == null && _decodeError == null
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.videocam_off_rounded, color: Colors.white70),
    );
  }

  Future<ui.Image> _decodeJpeg(Uint8List jpeg) async {
    // Decode directly instead of creating a new MemoryImage for every MJPEG
    // frame. This keeps transient live-video frames out of the global cache.
    return MediaSessionTelemetry.shared.measure(
      MediaMetricName.videoDecode,
      () async {
        final codec = await ui.instantiateImageCodec(jpeg);
        try {
          final decoded = await codec.getNextFrame();
          return decoded.image;
        } finally {
          codec.dispose();
        }
      },
    );
  }

  void _present(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    final startedAtUs = MediaSessionTelemetry.shared.nowUs;
    final previous = _presentedImage;
    setState(() {
      _presentedImage = image;
      _decodeError = null;
    });
    // The next build updates RawImage before the paint phase. Releasing the old
    // handle here keeps decoded video memory bounded even while frames are
    // paused or the application is not producing post-frame callbacks.
    previous?.dispose();
    MediaSessionTelemetry.shared.recordDurationUs(
      MediaMetricName.videoPresent,
      MediaSessionTelemetry.shared.nowUs - startedAtUs,
    );
  }

  void _handleDecodeError(Object error, StackTrace stackTrace) {
    if (!mounted || _presentedImage != null) return;
    setState(() => _decodeError = error);
  }
}

/// Serializes image decoding and retains only the newest frame received while
/// a decode is running. It bounds presentation work to one in-flight decode and
/// one pending byte buffer.
class LatestVideoFramePresentationQueue<T> {
  LatestVideoFramePresentationQueue({
    required Future<T> Function(Uint8List frame) decode,
    required void Function(T decoded) onPresented,
    required void Function(T decoded) onDiscarded,
    required void Function(Object error, StackTrace stackTrace) onError,
    void Function()? onCoalesced,
  })  : _decode = decode,
        _onPresented = onPresented,
        _onDiscarded = onDiscarded,
        _onError = onError,
        _onCoalesced = onCoalesced;

  final Future<T> Function(Uint8List frame) _decode;
  final void Function(T decoded) _onPresented;
  final void Function(T decoded) _onDiscarded;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final void Function()? _onCoalesced;

  Uint8List? _pendingFrame;
  bool _decodeInFlight = false;
  bool _disposed = false;
  int _generation = 0;
  int _coalescedFrameCount = 0;

  bool get decodeInFlight => _decodeInFlight;
  int get coalescedFrameCount => _coalescedFrameCount;

  void offer(Uint8List frame) {
    if (_disposed) return;
    if (_decodeInFlight) {
      if (_pendingFrame != null && !identical(_pendingFrame, frame)) {
        _coalescedFrameCount++;
        _onCoalesced?.call();
      }
      _pendingFrame = frame;
      return;
    }
    _start(frame);
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    _pendingFrame = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _pendingFrame = null;
  }

  void _start(Uint8List frame) {
    _decodeInFlight = true;
    final generation = _generation;
    unawaited(_decodeAndPresent(frame, generation));
  }

  Future<void> _decodeAndPresent(Uint8List frame, int generation) async {
    try {
      final decoded = await _decode(frame);
      if (_disposed || generation != _generation) {
        _onDiscarded(decoded);
      } else {
        _onPresented(decoded);
      }
    } catch (error, stackTrace) {
      if (!_disposed && generation == _generation && _pendingFrame == null) {
        _onError(error, stackTrace);
      }
    } finally {
      _decodeInFlight = false;
      if (!_disposed) {
        final pending = _pendingFrame;
        _pendingFrame = null;
        if (pending != null) _start(pending);
      }
    }
  }
}
