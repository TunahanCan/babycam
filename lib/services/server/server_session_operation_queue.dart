import 'dart:async';

/// Serializes mutations that span the HTTP session registry, media runtime,
/// WebRTC peers and broadcast-access accounting.
///
/// Each caller receives its own failure, while the internal tail is kept
/// non-throwing so one failed response/cleanup cannot poison later teardown.
class ServerSessionOperationQueue {
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_closed) {
      return Future<T>.error(
        StateError('Server session operation queue is closed.'),
      );
    }
    final completer = Completer<T>();
    final next = _tail.then<void>(
      (_) => _execute(operation, completer),
      onError: (_) => _execute(operation, completer),
    );
    _tail = next.then<void>((_) {}, onError: (_) {});
    return completer.future;
  }

  Future<void> drain() => _tail;

  Future<void> close() async {
    _closed = true;
    await _tail;
  }

  Future<void> _execute<T>(
    Future<T> Function() operation,
    Completer<T> completer,
  ) async {
    try {
      final result = await operation();
      if (!completer.isCompleted) completer.complete(result);
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }
}
