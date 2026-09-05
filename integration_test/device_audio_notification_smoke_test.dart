import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:miucam/features/client/media/client_live_audio_pipeline.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/notification_service.dart';
import 'package:miucam/services/platform/pcm_audio_output.dart';
import 'package:miucam/services/server/wav_pcm16.dart';

const _sampleRate = 16000;
const _frameDuration = Duration(milliseconds: 20);
const _observationDuration = Duration(seconds: 3);
const _restartCount = 2;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final audioRuns = <Map<String, Object?>>[];
  final notificationReport = <String, Object?>{};
  final report = <String, Object?>{
    'schemaVersion': 1,
    'validation': 'device_audio_notification_smoke',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'mode': kProfileMode ? 'profile' : 'other',
    'audioSource': 'controlled localhost HTTP WAV/PCM16 stream',
    'audioScope':
        'HTTP parser, jitter buffer, real Android AudioTrack and restart; '
            'does not test LG microphone capture, external LAN, or acoustic fidelity',
    'sampleRate': _sampleRate,
    'channels': 1,
    'frameDurationMs': _frameDuration.inMilliseconds,
    'toneFrequencyHz': 440,
    'tonePeakPcm16': 1000,
    'observationDurationMsPerRun': _observationDuration.inMilliseconds,
    'restartCount': _restartCount,
    'audioRuns': audioRuns,
    'notification': notificationReport,
  };
  binding.reportData = report;

  testWidgets('real Android PCM playback survives two stop/restart cycles',
      (tester) async {
    _requireDeviceProfile();
    await _showTestScreen(tester, 'MiuCam ses aktarımı cihaz testi');
    const output = PcmAudioOutput();
    final source = await _ControlledWavSource.start();
    final pipeline = ClientLiveAudioPipeline(audioOutput: output);
    report['source'] = source.report;
    try {
      for (var runIndex = 0; runIndex <= _restartCount; runIndex++) {
        final statuses = <Map<String, Object?>>[];
        final nativeSamples = <Map<String, Object?>>[];
        final errors = <String>[];
        final runReport = <String, Object?>{
          'run': runIndex + 1,
          'pipelineStatuses': statuses,
          'nativeSamples': nativeSamples,
          'errors': errors,
          'passed': false,
        };
        audioRuns.add(runReport);
        final before = await output.status();
        runReport['nativeBefore'] = before;
        try {
          await pipeline.start(
            uri: source.uri,
            pairedServerHost: source.uri.host,
            pairedServerPort: source.uri.port,
            bearerToken: _ControlledWavSource.token,
            shouldRetry: (_) => false,
            onStatus: (status) => statuses.add(status.toJson()),
            onError: (error) => errors.add(error.toString()),
          );

          // Exclude startup priming from the steady playback underrun budget.
          final baseline = await _waitForNativePlayback(output);
          runReport['nativeAtPlaybackStart'] = baseline;
          final clock = Stopwatch()..start();
          while (clock.elapsed < _observationDuration) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            nativeSamples.add({
              'elapsedMs': clock.elapsedMilliseconds,
              ...await output.status(),
            });
          }
          final last = nativeSamples.last;
          runReport['observedDurationMs'] = clock.elapsedMilliseconds;
          runReport['nativeBytesWrittenDelta'] =
              _int(last, 'bytesWritten') - _int(baseline, 'bytesWritten');
          runReport['playbackHeadFramesDelta'] =
              _int(last, 'playbackHeadFrames') -
                  _int(baseline, 'playbackHeadFrames');
          runReport['steadyStateUnderrunDelta'] =
              _int(last, 'underrunCount') - _int(baseline, 'underrunCount');

          expect(errors, isEmpty);
          expect(last['started'], isTrue);
          expect(last['playState'], 3, reason: 'AudioTrack must be playing.');
          expect(last['trackState'], 1,
              reason: 'AudioTrack must be initialized.');
          expect(_int(last, 'starts') - _int(before, 'starts'), 1);
          expect(runReport['nativeBytesWrittenDelta'],
              greaterThanOrEqualTo(_sampleRate * 2 * 2));
          expect(runReport['playbackHeadFramesDelta'],
              greaterThanOrEqualTo(_sampleRate * 2));
          expect(_int(last, 'sessionFramesWritten'),
              greaterThanOrEqualTo(_int(last, 'playbackHeadFrames')));
          expect(runReport['steadyStateUnderrunDelta'], 0);
          expect(
              _int(last, 'writesDropped') - _int(before, 'writesDropped'), 0);
          expect(_int(last, 'writeErrors') - _int(before, 'writeErrors'), 0);
          expect(statuses, isNotEmpty);
          expect(statuses.last['wavHeaderParsed'], isTrue);
          expect(statuses.last['droppedBufferBytes'], 0);
          expect(statuses.last['nativeWriteCallsDropped'], 0);
          expect(statuses.last['playoutUnderruns'], 0);
          expect(statuses.last['reconnects'], 0);
        } finally {
          await pipeline.stop();
          runReport['nativeAfterStop'] = await output.status();
        }
        expect(pipeline.isRunning, isFalse);
        final stopped = runReport['nativeAfterStop']! as Map<String, Object?>;
        expect(stopped['started'], isFalse);
        expect(stopped['pendingWrites'], 0);
        runReport['passed'] = true;
      }
      expect(source.report['singleByteSplitFrames'], greaterThan(0));
      report['audioPassed'] = true;
    } finally {
      await pipeline.stop();
      await source.close();
      binding.reportData = report;
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('real Android notification is visible and its own ID is cleaned',
      (tester) async {
    _requireDeviceProfile();
    await _showTestScreen(tester, 'MiuCam bildirim cihaz testi');
    final plugin = FlutterLocalNotificationsPlugin();
    final service = NotificationService(AppStrings(const Locale('tr')));
    final alertId =
        'device-smoke-test-${DateTime.now().microsecondsSinceEpoch}';
    final notificationId = NotificationService.notificationIdFor(alertId);
    notificationReport.addAll({
      'alertId': alertId,
      'notificationId': notificationId,
      'scope': 'real Android notification post and active notification query',
      'passed': false,
    });
    try {
      final receipt = await service.showAlert(
        'Bu bir cihaz doğrulama testidir; gerçek bebek uyarısı değildir.',
        alertId: alertId,
        title: 'MiuCam cihaz testi',
        severity: 'warning',
      );
      notificationReport['receipt'] = {
        'posted': receipt.posted,
        'verifiedActive': receipt.verifiedActive,
        'error': receipt.error,
      };
      expect(receipt.posted, isTrue, reason: receipt.error);
      final visible = await _waitForNotification(plugin, notificationId);
      notificationReport['activeNotification'] = {
        'id': visible.id,
        'title': visible.title,
        'body': visible.body,
        'channelId': visible.channelId,
      };
      expect(visible.title, 'MiuCam cihaz testi');
      notificationReport['passed'] = true;
    } finally {
      await plugin.cancel(notificationId);
      notificationReport['cleanedUp'] =
          await _waitForNotificationRemoval(plugin, notificationId);
      binding.reportData = report;
    }
    expect(notificationReport['cleanedUp'], isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

void _requireDeviceProfile() {
  expect(Platform.isAndroid, isTrue,
      reason: 'Run this native smoke test on the connected Android device.');
  expect(kProfileMode, isTrue,
      reason: 'Run with flutter drive --profile; platform mocks are not used.');
}

Future<void> _showTestScreen(WidgetTester tester, String label) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: Text(label))),
  ));
  await tester.pump();
}

int _int(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! num) {
    throw StateError('Required native metric $key is missing: $values');
  }
  return value.toInt();
}

Future<Map<String, Object?>> _waitForNativePlayback(
    PcmAudioOutput output) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  Map<String, Object?> status = const {};
  while (DateTime.now().isBefore(deadline)) {
    status = await output.status();
    if (status['started'] == true &&
        _int(status, 'playbackHeadFrames') > 0 &&
        _int(status, 'sessionFramesWritten') > 0) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
      'Native AudioTrack never advanced its playback head: $status');
}

Future<ActiveNotification> _waitForNotification(
  FlutterLocalNotificationsPlugin plugin,
  int notificationId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    for (final notification in await plugin.getActiveNotifications()) {
      if (notification.id == notificationId) return notification;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Android did not expose test notification $notificationId.');
}

Future<bool> _waitForNotificationRemoval(
  FlutterLocalNotificationsPlugin plugin,
  int notificationId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (!(await plugin.getActiveNotifications())
        .any((notification) => notification.id == notificationId)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

class _ControlledWavSource {
  _ControlledWavSource._(this._server) {
    _server.listen((request) {
      final operation = _serve(request);
      _pumps.add(operation);
      unawaited(operation.whenComplete(() => _pumps.remove(operation)));
    });
  }

  static const token = 'localhost-device-smoke-token';
  final HttpServer _server;
  final _pumps = <Future<void>>{};
  bool _closed = false;
  final report = <String, Object?>{
    'transport': 'localhost HTTP',
    'requests': 0,
    'pcmFramesSent': 0,
    'pcmBytesSent': 0,
    'singleByteSplitFrames': 0,
    'fragmentationScope':
        'HTTP writes split after one PCM byte; TCP may coalesce packets',
  };

  Uri get uri => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: _server.port,
        path: '/controlled-device-audio.wav',
      );

  static Future<_ControlledWavSource> start() async => _ControlledWavSource._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );

  Future<void> _serve(HttpRequest request) async {
    var disconnected = false;
    final response = request.response;
    unawaited(response.done.then<void>(
      (_) => disconnected = true,
      onError: (Object _) => disconnected = true,
    ));
    try {
      if (request.uri.path != uri.path ||
          request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $token') {
        response.statusCode = HttpStatus.unauthorized;
        return;
      }
      report['requests'] = (report['requests']! as int) + 1;
      response.headers.contentType = ContentType('audio', 'wav');
      response.bufferOutput = false;
      final header = WavPcm16.header(
        sampleRate: _sampleRate,
        channels: 1,
        bitsPerSample: 16,
      );
      response.add(Uint8List.sublistView(header, 0, 1));
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      response.add(Uint8List.sublistView(header, 1));
      await response.flush();
      final clock = Stopwatch()..start();
      var frame = 0;
      while (!_closed && !disconnected) {
        final pcm = _toneFrame(frame);
        if (frame % 11 == 0) {
          response.add(Uint8List.sublistView(pcm, 0, 1));
          await response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 1));
          response.add(Uint8List.sublistView(pcm, 1));
          report['singleByteSplitFrames'] =
              (report['singleByteSplitFrames']! as int) + 1;
        } else {
          response.add(pcm);
        }
        await response.flush();
        report['pcmFramesSent'] = (report['pcmFramesSent']! as int) + 1;
        report['pcmBytesSent'] = (report['pcmBytesSent']! as int) + pcm.length;
        frame++;
        final waitUs =
            frame * _frameDuration.inMicroseconds - clock.elapsedMicroseconds;
        if (waitUs > 0) {
          await Future<void>.delayed(Duration(microseconds: waitUs));
        }
      }
    } on IOException {
      // Each stop deliberately closes the local stream before the next run.
    } on StateError {
      // HttpResponse may report an already-closed sink after client teardown.
      if (!_closed && !disconnected) rethrow;
    } finally {
      try {
        await response.close();
      } on IOException {
        // The client may already have torn down this response.
      }
    }
  }

  Uint8List _toneFrame(int frame) {
    const samplesPerFrame = _sampleRate * 20 ~/ 1000;
    final pcm = ByteData(samplesPerFrame * 2);
    for (var offset = 0; offset < samplesPerFrame; offset++) {
      final sample = frame * samplesPerFrame + offset;
      final fadeIn = math.min(1.0, sample / 160);
      final value =
          (1000 * fadeIn * math.sin(2 * math.pi * 440 * sample / _sampleRate))
              .round();
      pcm.setInt16(offset * 2, value, Endian.little);
    }
    return pcm.buffer.asUint8List();
  }

  Future<void> close() async {
    _closed = true;
    await _server.close(force: true);
    await Future.wait(_pumps.toList()).timeout(const Duration(seconds: 5));
  }
}
