import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RequestBodyTooLargeException implements Exception {
  const RequestBodyTooLargeException({
    required this.maxBytes,
    required this.receivedBytes,
  });

  final int maxBytes;
  final int receivedBytes;

  @override
  String toString() =>
      'Request body exceeds $maxBytes bytes (received $receivedBytes).';
}

class RequestBodyReadTimeoutException implements Exception {
  const RequestBodyReadTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'Request body was not completed within $timeout.';
}

/// Reads small control-plane JSON requests without allowing an unbounded
/// request stream to grow in memory.
class BoundedJsonBodyReader {
  const BoundedJsonBodyReader({
    required this.maxBytes,
    this.readTimeout = const Duration(seconds: 10),
  }) : assert(maxBytes > 0);

  final int maxBytes;
  final Duration readTimeout;

  Future<Object?> read(HttpRequest request) => readStream(
        request,
        declaredLength: request.contentLength,
      );

  Future<Object?> readStream(
    Stream<List<int>> stream, {
    int declaredLength = -1,
  }) async {
    if (declaredLength > maxBytes) {
      throw RequestBodyTooLargeException(
        maxBytes: maxBytes,
        receivedBytes: declaredLength,
      );
    }

    final bytes = BytesBuilder(copy: false);
    final completed = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    final timer = Timer(readTimeout, () {
      if (completed.isCompleted) return;
      unawaited(subscription.cancel());
      completed.completeError(RequestBodyReadTimeoutException(readTimeout));
    });
    subscription = stream.listen(
      (chunk) {
        if (completed.isCompleted) return;
        final nextLength = bytes.length + chunk.length;
        if (nextLength > maxBytes) {
          unawaited(subscription.cancel());
          completed.completeError(RequestBodyTooLargeException(
            maxBytes: maxBytes,
            receivedBytes: nextLength,
          ));
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete();
      },
      cancelOnError: true,
    );
    try {
      await completed.future;
    } finally {
      timer.cancel();
    }

    final bodyBytes = bytes.takeBytes();
    if (bodyBytes.isEmpty) return null;
    final body = utf8.decode(bodyBytes);
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Future<Map<Object?, Object?>?> readObject(HttpRequest request) async {
    final json = await read(request);
    if (json == null) return null;
    if (json is! Map) throw const FormatException('Expected JSON object');
    return Map<Object?, Object?>.from(json);
  }
}
