import 'dart:math';

typedef RetryJitterSource = double Function();

abstract interface class RetryPolicy {
  Duration delayForAttempt(int attempt);
}

/// Stateless exponential retry timing with optional symmetric jitter.
///
/// Attempt zero returns [initialDelay] capped at [maxDelay]. Each later attempt
/// applies [multiplier] to the previous rounded millisecond value and caps it
/// at [maxDelay]. Keeping the calculation stateless lets independent retry
/// loops safely share a policy and makes any attempt directly testable.
class ExponentialBackoffPolicy implements RetryPolicy {
  ExponentialBackoffPolicy({
    required this.initialDelay,
    required this.maxDelay,
    this.multiplier = 1.7,
    this.jitterRatio = 0,
    RetryJitterSource? jitterSource,
  }) : _jitterSource = jitterSource ?? Random().nextDouble {
    if (initialDelay.isNegative) {
      throw ArgumentError.value(initialDelay, 'initialDelay', 'must be >= 0');
    }
    if (maxDelay.isNegative) {
      throw ArgumentError.value(maxDelay, 'maxDelay', 'must be >= 0');
    }
    if (!multiplier.isFinite || multiplier < 1) {
      throw ArgumentError.value(multiplier, 'multiplier', 'must be >= 1');
    }
    if (!jitterRatio.isFinite || jitterRatio < 0 || jitterRatio > 1) {
      throw ArgumentError.value(
        jitterRatio,
        'jitterRatio',
        'must be between 0 and 1',
      );
    }
  }

  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;
  final double jitterRatio;
  final RetryJitterSource _jitterSource;

  @override
  Duration delayForAttempt(int attempt) {
    if (attempt < 0) {
      throw ArgumentError.value(attempt, 'attempt', 'must be >= 0');
    }

    final maxDelayMs = maxDelay.inMilliseconds;
    var delayMs = initialDelay.inMilliseconds.clamp(0, maxDelayMs).toInt();
    for (var index = 0; index < attempt && delayMs < maxDelayMs; index++) {
      delayMs = (delayMs * multiplier).round().clamp(0, maxDelayMs).toInt();
    }
    if (jitterRatio == 0 || delayMs == 0) {
      return Duration(milliseconds: delayMs);
    }

    final sample = _jitterSource();
    if (!sample.isFinite || sample < 0 || sample > 1) {
      throw StateError('Retry jitter source must return a value from 0 to 1.');
    }
    final factor = 1 + ((sample * 2) - 1) * jitterRatio;
    final jitteredMs = (delayMs * factor).round().clamp(0, maxDelayMs).toInt();
    return Duration(milliseconds: jitteredMs);
  }
}
