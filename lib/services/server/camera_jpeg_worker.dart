import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../motion_analyzer.dart' show CameraImageJpegEncoder;

/// An owned camera-frame snapshot whose plane buffers can be moved to the JPEG
/// isolate without retaining camera-plugin buffers after their callback ends.
class TransferableCameraFrame {
  TransferableCameraFrame._({
    required this.width,
    required this.height,
    required this.formatRaw,
    required this.formatGroupIndex,
    required List<_TransferableCameraPlane> planes,
  }) : _planes = planes;

  factory TransferableCameraFrame.capture(CameraImage frame) =>
      TransferableCameraFrame._(
        width: frame.width,
        height: frame.height,
        formatRaw: frame.format.raw,
        formatGroupIndex: frame.format.group.index,
        planes: frame.planes
            .map(
              (plane) => _TransferableCameraPlane(
                bytes: TransferableTypedData.fromList([plane.bytes]),
                bytesPerPixel: plane.bytesPerPixel,
                bytesPerRow: plane.bytesPerRow,
                height: plane.height,
                width: plane.width,
              ),
            )
            .toList(growable: false),
      );

  final int width;
  final int height;
  final Object? formatRaw;
  final int formatGroupIndex;
  final List<_TransferableCameraPlane> _planes;

  Map<String, Object?> toMessage({
    required int requestId,
    required int quality,
    int? targetWidth,
    int? targetHeight,
  }) =>
      {
        'type': 'encode',
        'requestId': requestId,
        'quality': quality,
        'targetWidth': targetWidth,
        'targetHeight': targetHeight,
        'width': width,
        'height': height,
        'formatRaw': formatRaw,
        'formatGroupIndex': formatGroupIndex,
        'planes': _planes.map((plane) => plane.toMessage()).toList(),
      };
}

class _TransferableCameraPlane {
  const _TransferableCameraPlane({
    required this.bytes,
    required this.bytesPerPixel,
    required this.bytesPerRow,
    required this.height,
    required this.width,
  });

  final TransferableTypedData bytes;
  final int? bytesPerPixel;
  final int bytesPerRow;
  final int? height;
  final int? width;

  Map<String, Object?> toMessage() => {
        'bytes': bytes,
        'bytesPerPixel': bytesPerPixel,
        'bytesPerRow': bytesPerRow,
        'height': height,
        'width': width,
      };
}

/// A single persistent isolate for CPU-heavy JPEG conversion.
///
/// MiuCamServer owns the capacity-one latest-frame mailbox. Consequently this
/// worker receives at most one encode at a time and does not build another
/// unbounded queue.
class CameraJpegWorker {
  ReceivePort? _responses;
  Isolate? _isolate;
  SendPort? _commands;
  Future<SendPort>? _starting;
  final _pending = <int, Completer<Uint8List>>{};
  int _nextRequestId = 0;
  int _spawnCount = 0;
  bool _disposed = false;

  int get debugSpawnCount => _spawnCount;

  Future<Uint8List> encode(
    TransferableCameraFrame frame, {
    required int quality,
    int? targetWidth,
    int? targetHeight,
  }) async {
    if (_disposed) throw StateError('CameraJpegWorker is disposed.');
    final commands = await _ensureStarted();
    if (_disposed) throw StateError('CameraJpegWorker is disposed.');
    final requestId = ++_nextRequestId;
    final completer = Completer<Uint8List>();
    _pending[requestId] = completer;
    try {
      commands.send(frame.toMessage(
        requestId: requestId,
        quality: quality,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      ));
    } catch (_) {
      _pending.remove(requestId);
      rethrow;
    }
    return completer.future;
  }

  Future<SendPort> _ensureStarted() {
    final commands = _commands;
    if (commands != null) return Future<SendPort>.value(commands);
    return _starting ??= _start();
  }

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    _responses = responses;
    responses.listen((message) {
      if (message is SendPort) {
        _commands = message;
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message == null) {
        _handleWorkerTermination(
          ready: ready,
          error: StateError('JPEG worker stopped unexpectedly.'),
        );
        return;
      }
      if (message is List && message.length == 2) {
        _handleWorkerTermination(
          ready: ready,
          error: RemoteError(
            message.first.toString(),
            message.last.toString(),
          ),
        );
        return;
      }
      _handleResponse(message);
    });
    try {
      _isolate = await Isolate.spawn<SendPort>(
        _cameraJpegWorkerMain,
        responses.sendPort,
        debugName: 'miucam-jpeg-worker',
        onError: responses.sendPort,
        onExit: responses.sendPort,
        errorsAreFatal: true,
      );
      _spawnCount++;
      return await ready.future;
    } catch (_) {
      responses.close();
      if (identical(_responses, responses)) _responses = null;
      _commands = null;
      _isolate = null;
      _starting = null;
      rethrow;
    }
  }

  void _handleWorkerTermination({
    required Completer<SendPort> ready,
    required Object error,
  }) {
    _commands = null;
    _isolate = null;
    _starting = null;
    if (!ready.isCompleted) ready.completeError(error);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _responses?.close();
    _responses = null;
  }

  void _handleResponse(Object? message) {
    if (message is! Map) return;
    final requestId = message['requestId'];
    if (requestId is! int) return;
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    final bytes = message['bytes'];
    if (bytes is TransferableTypedData) {
      completer.complete(bytes.materialize().asUint8List());
      return;
    }
    completer.completeError(
      RemoteError(
        message['error']?.toString() ?? 'JPEG worker failed.',
        message['stackTrace']?.toString() ?? '',
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
    }
    _commands?.send(const {'type': 'close'});
    _isolate?.kill(priority: Isolate.immediate);
    _responses?.close();
    _commands = null;
    _isolate = null;
    _responses = null;
    final error = StateError('CameraJpegWorker is disposed.');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

void _cameraJpegWorkerMain(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  commands.listen((message) {
    if (message is! Map) return;
    if (message['type'] == 'close') {
      commands.close();
      return;
    }
    final requestId = message['requestId'];
    if (requestId is! int) return;
    try {
      final frame = _cameraImageFromMessage(message);
      final groupIndex = message['formatGroupIndex'];
      final formatGroup = groupIndex is int &&
              groupIndex >= 0 &&
              groupIndex < ImageFormatGroup.values.length
          ? ImageFormatGroup.values[groupIndex]
          : ImageFormatGroup.unknown;
      final jpeg = CameraImageJpegEncoder.encode(
        frame,
        quality: message['quality'] as int? ?? 70,
        formatGroup: formatGroup,
        targetWidth: message['targetWidth'] as int?,
        targetHeight: message['targetHeight'] as int?,
      );
      responses.send({
        'requestId': requestId,
        'bytes': TransferableTypedData.fromList([jpeg]),
      });
    } catch (error, stackTrace) {
      responses.send({
        'requestId': requestId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
  });
}

CameraImage _cameraImageFromMessage(Map<Object?, Object?> message) {
  final planeMessages = message['planes'] as List<Object?>;
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': message['formatRaw'],
    'width': message['width'],
    'height': message['height'],
    'planes': planeMessages.map((value) {
      final plane = value as Map<Object?, Object?>;
      final bytes = plane['bytes'] as TransferableTypedData;
      return {
        'bytes': bytes.materialize().asUint8List(),
        'bytesPerPixel': plane['bytesPerPixel'],
        'bytesPerRow': plane['bytesPerRow'],
        'height': plane['height'],
        'width': plane['width'],
      };
    }).toList(growable: false),
  });
}
