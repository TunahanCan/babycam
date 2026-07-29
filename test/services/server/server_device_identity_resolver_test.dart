import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/server_device_identity_resolver.dart';

void main() {
  test('coalesces concurrent resolution and caches normalized identity',
      () async {
    final completion = Completer<String>();
    var calls = 0;
    final resolver = ServerDeviceIdentityResolver(() {
      calls++;
      return completion.future;
    });

    final first = resolver.resolve();
    final second = resolver.resolve();
    completion.complete('  stable-id  ');

    expect(await Future.wait([first, second]), ['stable-id', 'stable-id']);
    expect(await resolver.resolve(), 'stable-id');
    expect(calls, 1);
  });

  test('rejects empty identity and permits a later retry', () async {
    var calls = 0;
    final resolver = ServerDeviceIdentityResolver(() {
      calls++;
      return calls == 1 ? '   ' : 'recovered-id';
    });

    await expectLater(resolver.resolve(), throwsStateError);
    expect(await resolver.resolve(), 'recovered-id');
    expect(calls, 2);
  });
}
