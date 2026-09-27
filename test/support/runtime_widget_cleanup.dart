import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/client/client_runtime.dart';

/// Run inside the widget test body (normally in `finally`). Role queues and
/// stream closures were created in that body's fake-async zone, so their
/// callbacks need pumping even when their futures have already completed.
/// Awaiting them later from `addTearDown` cannot advance the old fake zone.
Future<void> disposeClientRuntime(
    WidgetTester tester, ClientRuntime runtime) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  final closing = runtime.dispose().then((_) {
    completed = true;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    failureStack = stack;
    completed = true;
  });
  for (var frame = 0; frame < 110 && !completed; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(completed, isTrue,
      reason: 'Client shutdown must finish before leaving fake time.');
  await closing;
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
}
