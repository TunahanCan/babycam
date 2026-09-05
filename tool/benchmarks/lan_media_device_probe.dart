// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'package:miucam/features/client/media/mjpeg_stream_parser.dart';
import 'package:miucam/features/client/media/wav_pcm_stream_parser.dart';
import 'package:miucam/services/server/wav_pcm16.dart';

/// Exercises a real room device using the production media parsers.
/// Credentials stay in an environment-selected local file, never in reports.
/// This measures LAN receive timing, not physical speaker or display latency.
Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    options[args[i]] = args[i + 1];
  }
  if (options['--self-test'] == 'true') {
    await _selfTest();
    return;
  }
  final base = Uri.parse(options['--base-url'] ?? '');
  final output = options['--output'];
  final credentialPath = Platform.environment['MIUCAM_PROBE_CREDENTIALS'];
  if (base.scheme != 'http' ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      output == null ||
      credentialPath == null) {
    stderr
        .writeln('Usage: MIUCAM_PROBE_CREDENTIALS=/private/file.json dart run '
            'tool/benchmarks/lan_media_device_probe.dart '
            '--base-url http://DEVICE:8080 --output report.json '
            '[--seconds 30] [--video true] [--audio true] [--controls true] '
            '[--events true]');
    exitCode = 64;
    return;
  }
  final probe = _Probe(base, File(credentialPath));
  final report = <String, Object?>{
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'baseUrl': base.toString(),
    'measurement': 'host LAN receive; no physical playout latency claim',
  };
  final attempt = 'device-probe-${DateTime.now().microsecondsSinceEpoch}';
  WebSocket? events;
  Timer? eventDeadline;
  var eventWindowOpen = false;
  var eventMessages = 0;
  String? eventFailure;
  try {
    await probe.authenticate();
    report['unauthorizedStatus'] =
        (await probe.request('/status', authenticated: false)).$1;
    if (report['unauthorizedStatus'] != 401) {
      throw StateError('Private status accepted an unauthenticated request.');
    }
    report['before'] = probe.statusForReport(await probe.json('/status'));
    final video = options['--video'] != 'false';
    final audio = options['--audio'] != 'false';
    report['requestedChecks'] = {
      'video': video,
      'audio': audio,
      'controls': options['--controls'] == 'true',
      'events': options['--events'] == 'true',
    };
    final start = await probe.json('/session/start', body: {
      'streamAttemptId': attempt,
      'video': video,
      'audio': audio,
    });
    final streamToken = start['streamToken'] as String;
    probe.secrets.add(streamToken);
    report['session'] = probe.redact(start);
    final eventCounts = <String, int>{};
    if (options['--events'] == 'true') {
      events = await WebSocket.connect(
        base
            .resolve('/ws/events?alertReplayV=1')
            .replace(scheme: 'ws')
            .toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer ${probe.token}'},
      ).timeout(const Duration(seconds: 15));
      events.pingInterval = const Duration(seconds: 5);
      eventWindowOpen = true;
      events.listen((data) {
        if (!eventWindowOpen) return;
        try {
          if (data is! String || data.length > 1024 * 1024) {
            throw const FormatException('Invalid event message.');
          }
          final event = jsonDecode(data) as Map;
          final rawType = '${event['type'] ?? 'unknown'}';
          final type =
              eventCounts.containsKey(rawType) || eventCounts.length < 32
                  ? rawType.substring(0, min(80, rawType.length))
                  : 'other';
          eventMessages++;
          eventCounts.update(type, (n) => n + 1, ifAbsent: () => 1);
          final id = event['id'];
          if (id is String) {
            events?.add(jsonEncode({'type': 'alertAck', 'alertId': id}));
          }
        } catch (_) {
          eventFailure = 'Event message parsing or acknowledgement failed.';
        }
      }, onError: (Object _) {
        if (eventWindowOpen) eventFailure = 'Event socket reported an error.';
      }, onDone: () {
        if (eventWindowOpen) {
          eventFailure = 'Event socket closed before deadline.';
        }
      });
    }
    final seconds = int.parse(options['--seconds'] ?? '30');
    if (seconds <= 0) throw ArgumentError('seconds must be positive');
    eventDeadline = Timer(Duration(seconds: seconds), () {
      eventWindowOpen = false;
    });
    final samplesFile = File('$output.jsonl');
    await samplesFile.parent.create(recursive: true);
    final samples = samplesFile.openWrite();
    try {
      final results = await Future.wait([
        if (video) probe.media('video', streamToken, seconds),
        if (audio) probe.media('audio', streamToken, seconds),
        () async {
          final clock = Stopwatch()..start();
          var sampleCount = 0;
          var sampleBytes = 0;
          final intervalMs = max(5000, (seconds * 1000 / 512).ceil());
          while (clock.elapsed.inSeconds < seconds && sampleCount < 512) {
            final status = await probe.json('/status');
            final line = jsonEncode({
              'at': DateTime.now().toUtc().toIso8601String(),
              'elapsedMs': clock.elapsedMilliseconds,
              'status': probe.statusForReport(status),
            });
            samples.writeln(line);
            sampleCount++;
            sampleBytes += utf8.encode(line).length + 1;
            await samples.flush();
            final remainingMs = seconds * 1000 - clock.elapsedMilliseconds;
            if (remainingMs > 0) {
              await Future<void>.delayed(
                  Duration(milliseconds: min(intervalMs, remainingMs)));
            }
          }
          return <String, Object?>{
            'kind': 'status',
            'result': sampleCount > 0 ? 'pass' : 'fail',
            'samples': sampleCount,
            'jsonlBytes': sampleBytes,
            'maxStatusBytesPerSample': 16 * 1024,
            'maxSamples': 512,
            'pollIntervalMs': intervalMs,
          };
        }(),
      ]);
      report['media'] = results;
      if (results.any((result) => result['result'] != 'pass')) {
        throw StateError(
            'Media continuity validation failed; see media metrics.');
      }
    } finally {
      await samples.close();
    }
    report['eventCounts'] = eventCounts;
    if (options['--events'] == 'true') {
      report['events'] = {
        'messages': eventMessages,
        'error': eventFailure,
        'pingIntervalMs': 5000,
        'remainedOpenUntilDeadline': eventFailure == null,
        'alertStimulus': 'not_generated_by_probe',
        if (eventMessages == 0)
          'coverage': 'no alert stimulated or observed; socket continuity only',
        'measurement':
            'socket continuity and ACK sending; no notification UI claim',
      };
      if (eventFailure != null) {
        throw StateError(eventFailure!);
      }
    }
    eventWindowOpen = false;
    report['during'] = probe.statusForReport(await probe.json('/status'));
    if (options['--controls'] == 'true') {
      final controls = <Object?>[];
      report['controls'] = controls;
      await probe.controls(results: controls);
    }
    report['result'] = 'pass';
  } catch (e, s) {
    report['result'] = 'fail';
    report['error'] = probe.redactText(e.toString());
    stderr.writeln(probe.redactText('$e\n$s'));
    exitCode = 1;
  } finally {
    eventDeadline?.cancel();
    eventWindowOpen = false;
    try {
      if (events != null) {
        events.add(jsonEncode({'type': 'alertDetach'}));
        await events.close().timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
    try {
      if (probe.token.isNotEmpty) {
        await probe.json('/session/stop', body: {'streamAttemptId': attempt});
        await Future<void>.delayed(const Duration(seconds: 2));
        report['after'] = probe.statusForReport(await probe.json('/status'));
      }
    } catch (e) {
      report['cleanupError'] = probe.redactText(e.toString());
      report['result'] = 'fail';
      exitCode = 1;
    }
    probe.client.close(force: true);
    report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(probe.redact(report))}\n');
    print(jsonEncode({
      'result': report['result'],
      'output': output,
      'media': report['media'],
      'error': report['error']
    }));
  }
}

Future<String> _readBoundedResponse(HttpClientResponse response) async {
  final iterator = StreamIterator<List<int>>(response);
  final bytes = BytesBuilder(copy: false);
  Future<String> read() async {
    while (await iterator.moveNext()) {
      if (bytes.length + iterator.current.length > 2 * 1024 * 1024) {
        throw const FormatException('JSON response exceeded the 2 MiB limit.');
      }
      bytes.add(iterator.current);
    }
    return utf8.decode(bytes.takeBytes());
  }

  try {
    return await read().timeout(const Duration(seconds: 20));
  } finally {
    await iterator.cancel();
  }
}

void _requireState(
    String operation, Map response, Map<String, Object?> expected) {
  final state = response['state'];
  if (response['ok'] != true || state is! Map || state['lastError'] != null) {
    throw StateError('$operation failed: ok=${response['ok']}, '
        'deviceError=${state is Map ? state['lastError'] : 'missing state'}.');
  }
  for (final entry in expected.entries) {
    final actual = state[entry.key];
    final wanted = entry.value;
    final matches = wanted is num && actual is num
        ? (wanted - actual).abs() <= .001
        : actual == wanted;
    if (!matches) {
      throw StateError('$operation did not apply ${entry.key}: '
          'expected=$wanted actual=$actual.');
    }
  }
}

class _GapStatistics {
  final _histogram = List<int>.filled(10001, 0);
  int count = 0;
  int maximum = 0;
  int over500 = 0;

  void add(int value) {
    final gap = max(0, value);
    _histogram[min(gap, 10000)]++;
    maximum = max(maximum, gap);
    count++;
    if (gap > 500) over500++;
  }

  int? get p95 {
    if (count == 0) return null;
    final target = (count * .95).ceil();
    var accumulated = 0;
    for (var index = 0; index < _histogram.length; index++) {
      accumulated += _histogram[index];
      if (accumulated >= target) return index == 10000 ? maximum : index;
    }
    return maximum;
  }
}

/// Deterministic local servers prove the acceptance gates reject interrupted
/// and starved streams. No phone, credentials, or pairing are used here.
Future<void> _selfTest() async {
  void check(bool condition, String message) {
    if (!condition) throw StateError('Self-test failed: $message');
  }

  for (final behavior in ['early_eof', 'stalled', 'healthy']) {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final timers = <Timer>[];
    server.listen((request) async {
      final response = request.response;
      response.bufferOutput = false;
      response.headers.contentType = ContentType('audio', 'wav');
      response.add(
          WavPcm16.header(sampleRate: 16000, channels: 1, bitsPerSample: 16));
      response.add(Uint8List(640));
      await response.flush();
      if (behavior == 'early_eof') {
        await response.close();
      } else if (behavior == 'healthy') {
        timers.add(Timer.periodic(const Duration(milliseconds: 20), (timer) {
          try {
            response.add(Uint8List(640));
            unawaited(
                response.flush().catchError((Object _) => timer.cancel()));
          } catch (_) {
            timer.cancel();
          }
        }));
      }
    });
    final probe =
        _Probe(Uri.parse('http://127.0.0.1:${server.port}'), File('unused'));
    try {
      final result = await probe.media('audio', 'self-test-only', 1);
      check(result['result'] == (behavior == 'healthy' ? 'pass' : 'fail'),
          behavior);
      if (behavior == 'early_eof') {
        check(
            (result['failures'] as List)
                .contains('stream_ended_before_deadline'),
            'early EOF must fail even with valid PCM bytes');
      }
      if (behavior == 'stalled') {
        check(
            (result['failures'] as List)
                .contains('insufficient_audio_coverage'),
            'open but starved socket must fail');
      }
    } finally {
      for (final timer in timers) {
        timer.cancel();
      }
      probe.client.close(force: true);
      await server.close(force: true);
    }
  }

  final probe = _Probe(Uri.parse('http://127.0.0.1'), File('unused'));
  probe.token = 'test-private-token';
  final largeStatus = {
    'authorization': 'Bearer test-private-token',
    'nested': {'streamToken': 'other-private-token'},
    'error': 'http://host/audio?streamToken=test-private-token',
    'history': List.generate(10000, (i) => {'value': i, 'payload': 'x' * 1000}),
  };
  final encoded = jsonEncode(probe.statusForReport(largeStatus));
  check(utf8.encode(encoded).length <= 16 * 1024, 'bounded status snapshot');
  check(
      !encoded.contains('test-private-token') &&
          !encoded.contains('other-private-token'),
      'credentials removed from nested objects and URL errors');
  final gaps = _GapStatistics();
  for (var i = 0; i < 100000; i++) {
    gaps.add(i < 95000 ? 20 : 15000);
  }
  check(gaps.p95 == 20 && gaps.maximum == 15000 && gaps.over500 == 5000,
      'bounded histogram preserves percentile, maximum and stall counts');
  for (final badState in [
    {
      'ok': false,
      'state': {'playing': false}
    },
    {
      'ok': true,
      'state': {'playing': true}
    },
  ]) {
    var rejected = false;
    try {
      _requireState('pause', badState, {'playing': false});
    } on StateError {
      rejected = true;
    }
    check(rejected, 'false or unapplied control acknowledgement rejected');
  }
  probe.client.close(force: true);
  print('PASS: early EOF, stalled/healthy audio, bounded/redacted status, '
      'bounded gap statistics, failed/unapplied controls. No device playback claim.');
}

class _Probe {
  _Probe(this.base, this.credentials);
  final Uri base;
  final File credentials;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  String token = '';
  final secrets = <String>{};

  String redactText(String text) {
    var safe = text;
    for (final secret in [token, ...secrets]) {
      if (secret.isNotEmpty) safe = safe.replaceAll(secret, '[redacted]');
    }
    return safe
        .replaceAll(RegExp(r'Bearer\s+[^\s"\x27]+', caseSensitive: false),
            'Bearer [redacted]')
        .replaceAllMapped(
            RegExp(r'([?&](?:\w*token|\w*nonce)=)[^&\s)"\x27]+',
                caseSensitive: false),
            (match) => '${match[1]}[redacted]');
  }

  Object? redact(Object? value) {
    if (value is String) return redactText(value);
    if (value is List) return value.map(redact).toList();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': RegExp(r'token|nonce|authorization|password|secret',
                      caseSensitive: false)
                  .hasMatch('${entry.key}')
              ? '[redacted]'
              : redact(entry.value),
      };
    }
    return value;
  }

  /// Bound both each snapshot and the number of snapshots for long/dual soaks.
  /// History arrays are summaries; this file is not a full diagnostic archive.
  Map<String, Object?> statusForReport(Map status) {
    Object? compact(Object? value, int depth) {
      if (value is Map) {
        if (depth >= 7) return {'omittedKeys': value.length};
        return {
          for (final entry in value.entries.take(64))
            '${entry.key}': compact(entry.value, depth + 1),
          if (value.length > 64) 'omittedKeys': value.length - 64,
        };
      }
      if (value is List) {
        return {
          'count': value.length,
          'firstItems':
              value.take(2).map((v) => compact(v, depth + 1)).toList(),
        };
      }
      if (value is String && value.length > 160) {
        return '${value.substring(0, 160)}[truncated]';
      }
      return value;
    }

    final safe = Map<String, Object?>.from(redact(status) as Map);
    var result = Map<String, Object?>.from(compact(safe, 0) as Map);
    if (utf8.encode(jsonEncode(result)).length <= 16 * 1024) return result;
    // Keep compact leaf diagnostics instead of writing ever-growing histories.
    result = {'snapshotTruncated': true};
    void flatten(Object? value, String path) {
      if (result.length >= 128) return;
      if (value is Map) {
        for (final entry in value.entries) {
          flatten(entry.value,
              path.isEmpty ? '${entry.key}' : '$path.${entry.key}');
        }
      } else if (value is! List) {
        result[path.substring(0, min(path.length, 80))] =
            value is String ? value.substring(0, min(value.length, 80)) : value;
      }
    }

    flatten(safe, '');
    while (utf8.encode(jsonEncode(result)).length > 16 * 1024) {
      result.remove(result.keys.last);
    }
    return result;
  }

  Future<void> authenticate() async {
    if (await credentials.exists()) {
      final stored = jsonDecode(await credentials.readAsString()) as Map;
      token = stored['trustedClientToken'] as String;
      return;
    }
    final public = await json('/status/public', authenticated: false);
    final paired = await json('/pair/confirm', authenticated: false, body: {
      'pairingNonce': public['pairingNonce'],
      'deviceId': 'miucam-host-probe-${DateTime.now().millisecondsSinceEpoch}',
      'clientName': 'LG device validation host',
    });
    token = paired['trustedClientToken'] as String;
    await credentials.parent.create(recursive: true);
    await credentials.writeAsString(jsonEncode(paired));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', credentials.path]);
    }
  }

  Future<(int, String)> request(
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final request = await client
        .openUrl(body == null ? 'GET' : 'POST', base.resolve(path))
        .timeout(const Duration(seconds: 10));
    if (authenticated) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await _readBoundedResponse(response);
    return (response.statusCode, text);
  }

  Future<Map<String, dynamic>> json(
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final response =
        await request(path, body: body, authenticated: authenticated);
    if (response.$1 != 200) {
      throw HttpException('$path returned ${response.$1}');
    }
    return jsonDecode(response.$2) as Map<String, dynamic>;
  }

  Future<Map<String, Object?>> media(
      String kind, String streamToken, int seconds) async {
    final mediaClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final clock = Stopwatch()..start();
    final mjpeg = MjpegStreamParser();
    final wav = WavPcmStreamParser();
    final gaps = _GapStatistics();
    int? firstMs;
    int? lastMs;
    var bytes = 0;
    var frames = 0;
    var invalidJpegs = 0;
    var clipped = 0;
    var count = 0;
    var squareSum = 0.0;
    var peak = 0;
    var sampleRate = 0;
    var channels = 0;
    List<int>? dimensions;
    var timedOut = false;
    var earlyEof = false;
    String? transportError;
    final timer = Timer(Duration(seconds: seconds), () {
      timedOut = true;
      mediaClient.close(force: true);
    });
    try {
      final request = await mediaClient.getUrl(base
          .resolve('/$kind')
          .replace(queryParameters: {'streamToken': streamToken}));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('$kind returned ${response.statusCode}');
      }
      await for (final chunk in response) {
        final data = Uint8List.fromList(chunk);
        var produced = false;
        if (kind == 'video') {
          for (final frame in mjpeg.addFrames(data)) {
            produced = true;
            frames++;
            bytes += frame.jpeg.length;
            if (frames == 1 || frames % 100 == 0) {
              final decoded = image.decodeJpg(frame.jpeg);
              if (decoded == null) {
                invalidJpegs++;
              } else {
                dimensions = [decoded.width, decoded.height];
              }
            }
          }
        } else {
          final pcm = wav.add(data);
          sampleRate = pcm.sampleRate;
          channels = pcm.channels;
          produced = pcm.pcm16le.isNotEmpty;
          bytes += pcm.pcm16le.length;
          final view = ByteData.sublistView(pcm.pcm16le);
          for (var i = 0; i + 1 < view.lengthInBytes; i += 2) {
            final value = view.getInt16(i, Endian.little);
            count++;
            squareSum += value * value;
            peak = max(peak, value.abs());
            if (value.abs() >= 32760) clipped++;
          }
        }
        if (produced) {
          final now = clock.elapsedMilliseconds;
          firstMs ??= now;
          if (lastMs != null) gaps.add(now - lastMs);
          lastMs = now;
        }
      }
      earlyEof = !timedOut;
    } catch (error) {
      if (!timedOut) transportError = redactText(error.toString());
    } finally {
      timer.cancel();
      mediaClient.close(force: true);
    }
    final requestedMs = seconds * 1000;
    final tailGapMs =
        lastMs == null ? requestedMs : max(0, requestedMs - lastMs);
    final allowedGapMs = min(requestedMs ~/ 3, kind == 'audio' ? 1000 : 5000);
    final audioDurationMs = sampleRate == 0 || channels == 0
        ? 0.0
        : count * 1000 / (sampleRate * channels);
    final payloadWindowMs = max(1, requestedMs - (firstMs ?? requestedMs));
    final audioCoverage = audioDurationMs / payloadWindowMs;
    final failures = <String>[
      if (!timedOut || earlyEof) 'stream_ended_before_deadline',
      if (transportError != null) 'transport_error',
      if (bytes == 0) 'no_payload',
      if (firstMs == null || firstMs > min(10000, requestedMs ~/ 2))
        'startup_too_slow',
      if (tailGapMs > allowedGapMs) 'payload_stopped_before_deadline',
      if (gaps.maximum > allowedGapMs) 'receive_gap_exceeded_limit',
      if (kind == 'video' &&
          (invalidJpegs > 0 || mjpeg.metrics.invalidParts > 0))
        'invalid_video_frames',
      if (kind == 'video' && frames < max(1, payloadWindowMs ~/ 2000))
        'insufficient_video_frames',
      if (kind == 'audio' && audioCoverage < .90) 'insufficient_audio_coverage',
      if (kind == 'audio' && audioCoverage > 1.15) 'excess_audio_coverage',
    ];
    return {
      'kind': kind,
      'result': failures.isEmpty ? 'pass' : 'fail',
      'failures': failures,
      'requestedDurationMs': requestedMs,
      'durationMs': clock.elapsedMilliseconds,
      'deadlineReached': timedOut,
      'earlyEof': earlyEof,
      if (transportError != null) 'transportError': transportError,
      'bytes': bytes,
      'firstPayloadMs': firstMs,
      'lastPayloadMs': lastMs,
      'receiveGapP95Ms': gaps.p95,
      'receiveGapMaxMs': gaps.maximum,
      'receiveGapP95Method': 'bounded 1 ms histogram; overflow uses maximum',
      'tailGapMs': tailGapMs,
      'maxAllowedReceiveGapMs': allowedGapMs,
      'gapsOver500Ms': gaps.over500,
      if (kind == 'video') ...{
        'frames': frames,
        'dimensions': dimensions,
        'invalidJpegs': invalidJpegs,
        'parserInvalidParts': mjpeg.metrics.invalidParts,
      },
      if (kind == 'audio') ...{
        'sampleRate': sampleRate,
        'channels': channels,
        'samples': count,
        'audioDurationMs': audioDurationMs,
        'audioCoverageRatio': audioCoverage,
        'peak': peak,
        'rms': count == 0 ? 0 : sqrt(squareSum / count),
        'clippedSamples': clipped,
      },
    };
  }

  Future<List<Object?>> controls({List<Object?>? results}) async {
    results ??= <Object?>[];
    try {
      final state = await json('/comfort/state');
      final tracks = state['tracks'];
      if (state['ok'] != true ||
          tracks is! List ||
          tracks.isEmpty ||
          tracks.length > 32) {
        throw StateError('Comfort catalog is missing or outside probe bounds.');
      }
      for (final track in tracks) {
        final played = await json('/comfort/command', body: {
          'action': 'play',
          'trackId': track['id'],
          'volume': .08,
        });
        final expected = {
          'playing': true,
          'trackId': track['id'],
          'volume': .08
        };
        _requireState('comfort play', played, expected);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        final readback = await json('/comfort/state');
        _requireState('comfort play readback', readback, expected);
        results.add({
          'track': track['id'],
          'result': 'pass',
          'state': readback['state']
        });
      }
      final paused = await json('/comfort/command', body: {'action': 'pause'});
      _requireState('comfort pause', paused, {'playing': false});
      _requireState('comfort pause readback', await json('/comfort/state'),
          {'playing': false});
      results
          .add({'action': 'pause', 'result': 'pass', 'state': paused['state']});
      final volume = await json('/comfort/command',
          body: {'action': 'setVolume', 'volume': .12});
      _requireState('comfort volume', volume, {'volume': .12});
      _requireState('comfort volume readback', await json('/comfort/state'),
          {'volume': .12});
      results.add(
          {'action': 'setVolume', 'result': 'pass', 'state': volume['state']});
      for (final mode in ['screenGlow', 'torch']) {
        final enabled = await json('/night-light/command', body: {
          'action': 'on',
          'mode': mode,
          'brightness': .1,
        });
        final expected = {'enabled': true, 'mode': mode, 'brightness': .1};
        // A screen-glow fallback is useful app behavior, but does not prove
        // that the requested physical torch was exercised on this device.
        _requireState('night light $mode', enabled, expected);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _requireState('night light $mode readback',
            await json('/night-light/state'), expected);
        final disabled =
            await json('/night-light/command', body: {'action': 'off'});
        _requireState(
            'night light off', disabled, {'enabled': false, 'mode': 'off'});
        _requireState(
            'night light off readback',
            await json('/night-light/state'),
            {'enabled': false, 'mode': 'off'});
        results.add(
            {'nightLight': mode, 'result': 'pass', 'state': enabled['state']});
      }
      final attempt = 'probe-talk-${DateTime.now().microsecondsSinceEpoch}';
      final talk = await json('/talk/start', body: {
        'talkAttemptId': attempt,
        'sampleRate': 16000,
        'channels': 1,
      });
      if (talk['ok'] != true || talk['session'] is! Map) {
        throw StateError('Talk session did not start.');
      }
      final talkToken = talk['session']['talkToken'] as String;
      secrets.add(talkToken);
      try {
        final request = await client
            .postUrl(base
                .resolve('/talk/audio')
                .replace(queryParameters: {'talkToken': talkToken}))
            .timeout(const Duration(seconds: 10));
        request.headers.contentType = ContentType.binary;
        for (var frame = 0; frame < 25; frame++) {
          final pcm = ByteData(640);
          for (var i = 0; i < 320; i++) {
            pcm.setInt16(
                i * 2,
                (sin(2 * pi * 440 * (frame * 320 + i) / 16000) * 1000).round(),
                Endian.little);
          }
          request.add(pcm.buffer.asUint8List());
          await request.flush().timeout(const Duration(seconds: 5));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final response =
            await request.close().timeout(const Duration(seconds: 10));
        final result = jsonDecode(await _readBoundedResponse(response)) as Map;
        if (response.statusCode != 200 ||
            result['ok'] != true ||
            result['audioChunksPlayed'] != 25 ||
            result['audioBytesReceived'] != 16000) {
          throw StateError(
              'Talk upload/playback acknowledgement did not match sent PCM.');
        }
        results.add({
          'talkAudioBytes': result['audioBytesReceived'],
          'talkChunksPlayed': result['audioChunksPlayed']
        });
      } finally {
        final stopped = await json('/talk/stop',
            body: {'talkAttemptId': attempt, 'talkToken': talkToken});
        if (stopped['ok'] != true || stopped['talk']?['active'] != false) {
          throw StateError('Talk session did not stop.');
        }
      }
    } finally {
      try {
        _requireState(
            'comfort cleanup',
            await json('/comfort/command', body: {'action': 'stop'}),
            {'playing': false, 'trackId': null});
      } finally {
        _requireState(
            'night light cleanup',
            await json('/night-light/command', body: {'action': 'off'}),
            {'enabled': false, 'mode': 'off'});
      }
    }
    return results;
  }
}
