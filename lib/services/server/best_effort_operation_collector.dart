import 'dart:async';

/// Runs independent teardown operations without letting one failure prevent
/// later resources from being released.
///
/// Callers can preserve their existing error surface through [errors], while
/// diagnostics can use [failureMessages] to retain the operation label.
class BestEffortOperationCollector {
  final List<BestEffortOperationFailure> _failures = [];

  bool get hasFailures => _failures.isNotEmpty;

  List<Object> get errors => List<Object>.unmodifiable(
        _failures.map((failure) => failure.error),
      );

  List<String> get failureMessages => List<String>.unmodifiable(
        _failures.map((failure) => failure.toString()),
      );

  Future<void> attempt(
    String label,
    FutureOr<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      _failures.add(BestEffortOperationFailure(
        label: label,
        error: error,
        stackTrace: stackTrace,
      ));
    }
  }
}

class BestEffortOperationFailure {
  const BestEffortOperationFailure({
    required this.label,
    required this.error,
    required this.stackTrace,
  });

  final String label;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => '$label: $error';
}
