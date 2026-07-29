import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/best_effort_operation_collector.dart';

void main() {
  test('a failed operation does not prevent later cleanup', () async {
    final collector = BestEffortOperationCollector();
    var released = false;

    await collector.attempt('camera', () => throw StateError('busy'));
    await collector.attempt('microphone', () => released = true);

    expect(released, isTrue);
    expect(collector.errors, hasLength(1));
    expect(collector.errors.single, isA<StateError>());
    expect(collector.failureMessages.single, contains('camera:'));
  });

  test('successful collector remains empty', () async {
    final collector = BestEffortOperationCollector();

    await collector.attempt('server', () async {});

    expect(collector.hasFailures, isFalse);
    expect(collector.failureMessages, isEmpty);
  });
}
