import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/http_media_response_lifecycle.dart';

void main() {
  test('successful flush still rejects a peer whose TCP connection is gone',
      () async {
    final response = _Response();
    final lifecycle =
        HttpMediaResponseLifecycle(timeout: const Duration(seconds: 1));
    await lifecycle.flush(response);
    expect(response.flushCalls, 1);
    response.connection = null;
    await expectLater(lifecycle.flush(response), throwsA(isA<HttpException>()));
  });

  test('stalled flush times out and teardown bounds the underlying response',
      () async {
    const timeout = Duration(milliseconds: 10);
    final response = _Response()..closeResult = Completer<void>().future;
    final pendingFlush = Completer<void>();
    final lifecycle = HttpMediaResponseLifecycle(
        timeout: timeout, flusher: (_) => pendingFlush.future);
    await expectLater(
        lifecycle.flush(response), throwsA(isA<TimeoutException>()));
    await lifecycle.close(response).timeout(const Duration(seconds: 1));
    expect(response.deadline, timeout,
        reason: 'Future.timeout alone does not terminate a backlogged socket.');
    expect(response.closeCalls, 1);
    pendingFlush.complete();
  });

  test('socket close failure stays contained for independent viewer cleanup',
      () async {
    final response = _Response()
      ..closeFailure = const SocketException('closed');
    final lifecycle =
        HttpMediaResponseLifecycle(timeout: const Duration(seconds: 1));
    await lifecycle.close(response);
    expect(response.closeCalls, 1);
    expect(response.deadline, const Duration(seconds: 1));
  });
}

class _Response implements HttpResponse {
  HttpConnectionInfo? connection = _Connection();
  Future<void>? closeResult;
  Object? closeFailure;
  int flushCalls = 0;
  int closeCalls = 0;
  @override
  Duration? deadline;
  @override
  HttpConnectionInfo? get connectionInfo => connection;
  @override
  Future<void> flush() async {
    flushCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeFailure != null) throw closeFailure!;
    await closeResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection implements HttpConnectionInfo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
