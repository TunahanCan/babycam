import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/async/serialized_async_executor.dart';

void main() {
  test('commands run in submission order', () async {
    final executor = SerializedAsyncExecutor();
    final release = Completer<void>();
    final calls = <String>[];

    final first = executor.run(() async {
      calls.add('first:start');
      await release.future;
      calls.add('first:end');
    });
    final second = executor.run(() => calls.add('second'));

    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first:start']);
    release.complete();
    await Future.wait([first, second]);
    expect(calls, ['first:start', 'first:end', 'second']);
  });

  test('failed command does not poison the queue', () async {
    final executor = SerializedAsyncExecutor();

    await expectLater(
      executor.run<void>(() => throw StateError('failed')),
      throwsStateError,
    );

    expect(await executor.run(() => 42), 42);
  });

  test('close drains accepted commands and rejects new commands', () async {
    final executor = SerializedAsyncExecutor(
      closedErrorMessage: 'queue closed',
    );
    final release = Completer<void>();
    final accepted = executor.run(() => release.future);
    final close = executor.close();

    await expectLater(
      executor.run<void>(() {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'queue closed',
        ),
      ),
    );
    release.complete();
    await Future.wait([accepted, close]);
  });
}
