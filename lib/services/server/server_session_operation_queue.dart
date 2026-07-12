import '../../core/async/serialized_async_executor.dart';

/// Serializes mutations that span the HTTP session registry, media runtime,
/// WebRTC peers and broadcast-access accounting.
///
/// Each caller receives its own failure, while the internal tail is kept
/// non-throwing so one failed response/cleanup cannot poison later teardown.
class ServerSessionOperationQueue {
  final _executor = SerializedAsyncExecutor(
    closedErrorMessage: 'Server session operation queue is closed.',
  );

  Future<T> run<T>(Future<T> Function() operation) => _executor.run(operation);

  Future<void> drain() => _executor.drain();

  Future<void> close() => _executor.close();
}
