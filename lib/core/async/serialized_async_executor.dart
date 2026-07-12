import 'dart:async';

/// Runs asynchronous commands in submission order without allowing one
/// failure to poison commands queued after it.
class SerializedAsyncExecutor {
  SerializedAsyncExecutor({
    this.closedErrorMessage = 'Serialized async executor is closed.',
  });

  final String closedErrorMessage;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  bool get isClosed => _closed;

  Future<T> run<T>(FutureOr<T> Function() command) {
    if (_closed) return Future<T>.error(StateError(closedErrorMessage));
    final next = _tail.then<T>(
      (_) => Future<T>.sync(command),
      onError: (_, __) => Future<T>.sync(command),
    );
    _tail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<void> drain() => _tail;

  Future<void> close() {
    _closed = true;
    return drain();
  }
}
