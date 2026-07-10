import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/network/retry_policy.dart';

void main() {
  test('exponential delay mevcut 1.7 carpanli diziyi ve capi korur', () {
    final policy = ExponentialBackoffPolicy(
      initialDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 4),
    );

    expect(
      List.generate(7, (attempt) => policy.delayForAttempt(attempt)),
      const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 850),
        Duration(milliseconds: 1445),
        Duration(milliseconds: 2457),
        Duration(milliseconds: 4000),
        Duration(milliseconds: 4000),
        Duration(milliseconds: 4000),
      ],
    );
  });

  test('policy stateless oldugu icin attemptler siradan bagimsiz hesaplanir',
      () {
    final policy = ExponentialBackoffPolicy(
      initialDelay: const Duration(milliseconds: 700),
      maxDelay: const Duration(seconds: 4),
    );

    expect(policy.delayForAttempt(3), const Duration(milliseconds: 3439));
    expect(policy.delayForAttempt(0), const Duration(milliseconds: 700));
    expect(policy.delayForAttempt(3), const Duration(milliseconds: 3439));
  });

  test('initial delay max delayden buyukse ilk attempt maxa clamp edilir', () {
    final policy = ExponentialBackoffPolicy(
      initialDelay: const Duration(seconds: 30),
      maxDelay: const Duration(seconds: 4),
    );

    expect(policy.delayForAttempt(0), const Duration(seconds: 4));
    expect(policy.delayForAttempt(1), const Duration(seconds: 4));
  });

  test('jitter source injection deterministik alt orta ve ust delay uretir',
      () {
    final samples = [0.0, 0.5, 1.0].iterator;
    final policy = ExponentialBackoffPolicy(
      initialDelay: const Duration(seconds: 1),
      maxDelay: const Duration(seconds: 5),
      jitterRatio: 0.2,
      jitterSource: () {
        samples.moveNext();
        return samples.current;
      },
    );

    expect(policy.delayForAttempt(0), const Duration(milliseconds: 800));
    expect(policy.delayForAttempt(0), const Duration(milliseconds: 1000));
    expect(policy.delayForAttempt(0), const Duration(milliseconds: 1200));
  });

  test('pozitif jitter max delay capini asamaz', () {
    final policy = ExponentialBackoffPolicy(
      initialDelay: const Duration(seconds: 1),
      maxDelay: const Duration(seconds: 2),
      jitterRatio: 0.5,
      jitterSource: () => 1,
    );

    expect(policy.delayForAttempt(3), const Duration(seconds: 2));
  });
}
