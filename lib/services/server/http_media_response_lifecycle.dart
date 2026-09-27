import 'dart:async';
import 'dart:io';

typedef HttpMediaResponseFlusher = Future<void> Function(HttpResponse response);

/// Shared socket lifecycle for the HTTP audio and video adapters.
///
/// A Dart flush may hide a disconnected peer's socket error. A timeout alone
/// also only ends the await; it cannot release a backlogged TCP connection.
/// Keep both transport-specific frame formats behind the same close policy.
class HttpMediaResponseLifecycle {
  HttpMediaResponseLifecycle({
    required this.timeout,
    HttpMediaResponseFlusher? flusher,
  }) : _flusher = flusher ?? _flushResponse;

  final Duration timeout;
  final HttpMediaResponseFlusher _flusher;

  Future<void> flush(HttpResponse response) async {
    await _flusher(response).timeout(timeout);
    if (response.connectionInfo == null) {
      throw const HttpException('Media connection closed.');
    }
  }

  Future<void> close(HttpResponse response) async {
    try {
      response.deadline = timeout;
      await response.close().timeout(timeout);
    } catch (_) {
      // Teardown is best effort; other viewers still need to be released.
    }
  }

  static Future<void> _flushResponse(HttpResponse response) => response.flush();
}
