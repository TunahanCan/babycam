import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/server_session_operation_queue.dart';

void main() {
  test('session mutations execute in request order', () async {
    final queue = ServerSessionOperationQueue();
    final release = Completer<void>();
    final calls = <String>[];

    final first = queue.run(() async {
      calls.add('first:start');
      await release.future;
      calls.add('first:end');
    });
    final second = queue.run(() async => calls.add('second'));

    await Future<void>.delayed(Duration.zero);
    expect(calls, ['first:start']);
    release.complete();
    await Future.wait([first, second]);
    expect(calls, ['first:start', 'first:end', 'second']);
  });

  test('failed operation does not poison later cleanup', () async {
    final queue = ServerSessionOperationQueue();
    await expectLater(
      queue.run<void>(() async => throw StateError('response failed')),
      throwsStateError,
    );

    var cleaned = false;
    await queue.run(() async => cleaned = true);
    expect(cleaned, isTrue);
  });
}
