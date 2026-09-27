import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/client/media/client_live_audio_pipeline.dart';

void main() {
  for (final action in ['stop', 'terminate', 'replacement']) {
    testWidgets('$action removes the old audio reconnect timer',
        (tester) async {
      var requests = 0;
      final pipeline = ClientLiveAudioPipeline(
        retryDelay: const Duration(seconds: 30),
        maxRetryDelay: const Duration(seconds: 30),
        clientFactory: () {
          requests++;
          throw const SocketException('Room is offline.');
        },
      );
      await _start(pipeline);
      await tester.pump();
      expect(requests, 1);

      switch (action) {
        case 'stop':
          await pipeline.stop();
        case 'terminate':
          await pipeline.terminate();
        case 'replacement':
          await _start(pipeline, shouldRetry: (_) => false);
      }
      await tester.pump();
      expect(requests, action == 'replacement' ? 2 : 1);
      expect(pipeline.isRunning, isFalse);
      // testWidgets verifies there are no pending timers when this fake-async
      // body ends. Do not elapse the retry delay: that would conceal a leak.
    });
  }

  testWidgets('an error callback cannot arm retry after cancelling its run',
      (tester) async {
    var errors = 0;
    late final ClientLiveAudioPipeline pipeline;
    pipeline = ClientLiveAudioPipeline(
      retryDelay: const Duration(seconds: 30),
      maxRetryDelay: const Duration(seconds: 30),
      clientFactory: () => throw const SocketException('Room is offline.'),
    );
    await _start(pipeline, onError: (_) {
      errors++;
      pipeline.cancelImmediately();
    });
    await tester.pump();

    expect(errors, 1);
    expect(pipeline.isRunning, isFalse);
    // No later stop call is needed to clean up a timer created after cancel.
  });
}

Future<void> _start(
  ClientLiveAudioPipeline pipeline, {
  bool Function(Object)? shouldRetry,
  void Function(Object)? onError,
}) =>
    pipeline.start(
      uri: Uri.parse('http://127.0.0.1:8080/audio'),
      pairedServerHost: '127.0.0.1',
      pairedServerPort: 8080,
      shouldRetry: shouldRetry,
      onError: onError,
    );
