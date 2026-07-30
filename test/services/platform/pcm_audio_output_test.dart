import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/platform/pcm_audio_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playback leases publish monotonic owned native operations', () async {
    const channel = MethodChannel('test/miucam_pcm_audio_owned_operations');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' || 'write' || 'stop' => true,
        'status' => <String, Object?>{},
        _ => null,
      };
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const output = PcmAudioOutput(channel: channel);
    final first = output.createPlaybackLease();
    final second = output.createPlaybackLease();

    await first.start(sampleRate: 16000, channels: 1);
    expect(await first.write(Uint8List.fromList([1, 0])), isTrue);
    await first.stop();
    await second.start(sampleRate: 24000, channels: 2);
    expect(await first.write(Uint8List.fromList([2, 0])), isFalse);
    await first.stop();
    expect(await second.write(Uint8List.fromList([3, 0])), isTrue);
    await output.resetPlayback();

    expect(
      calls.map((call) => call.method),
      ['start', 'write', 'stop', 'start', 'write', 'stop'],
    );
    final arguments = calls
        .map((call) => call.arguments! as Map<Object?, Object?>)
        .toList(growable: false);
    final operationIds = arguments
        .map((args) => args['operationId']! as int)
        .toList(growable: false);
    expect(
      operationIds.indexed
          .skip(1)
          .every((entry) => entry.$2 > operationIds[entry.$1 - 1]),
      isTrue,
    );
    final firstLeaseId = arguments.first['leaseId'];
    final secondLeaseId = arguments[3]['leaseId'];
    expect(firstLeaseId, isNotNull);
    expect(secondLeaseId, isNot(firstLeaseId));
    expect(arguments[2]['leaseId'], firstLeaseId);
    expect(arguments.last['reset'], isTrue);
    expect(arguments.last.containsKey('leaseId'), isFalse);
  });

  test('native ownership rejection fails playback start', () async {
    const channel = MethodChannel('test/miucam_pcm_audio_rejected_start');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const output = PcmAudioOutput(channel: channel);

    await expectLater(
      output.createPlaybackLease().start(sampleRate: 16000, channels: 1),
      throwsA(isA<StateError>()),
    );
  });
}
