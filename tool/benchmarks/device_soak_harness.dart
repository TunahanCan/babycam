// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    print(_Options.usage);
    exitCode = 64;
    return;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  IOSink? output;
  try {
    if (options.outputPath != null) {
      final file = File(options.outputPath!);
      await file.parent.create(recursive: true);
      output = file.openWrite(mode: FileMode.writeOnly);
    }
    final deadline = DateTime.now().add(options.duration);
    var samples = 0;
    var failures = 0;
    while (DateTime.now().isBefore(deadline)) {
      final sampledAt = DateTime.now().toUtc();
      try {
        final status = await _readStatus(client, options);
        final record = <String, Object?>{
          'sampledAt': sampledAt.toIso8601String(),
          'deviceLabel': options.deviceLabel,
          'networkLane': options.networkLane,
          'status': status,
        };
        final line = jsonEncode(record);
        output?.writeln(line);
        if (output == null) print(line);
        samples++;
      } catch (error) {
        failures++;
        final line = jsonEncode({
          'sampledAt': sampledAt.toIso8601String(),
          'error': error.toString(),
        });
        output?.writeln(line);
        if (output == null) print(line);
      }
      if (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(options.pollInterval);
      }
    }
    await output?.flush();
    print(jsonEncode({
      'result': failures == 0 ? 'pass' : 'completed_with_failures',
      'samples': samples,
      'failures': failures,
      'durationMinutes': options.duration.inMinutes,
      'output': options.outputPath,
    }));
    if (failures > 0) exitCode = 1;
  } finally {
    client.close(force: true);
    await output?.close();
  }
}

Future<Map<String, Object?>> _readStatus(
  HttpClient client,
  _Options options,
) async {
  final uri = options.baseUri.resolve('/test/status');
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 5));
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer ${options.token}')
    ..set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close().timeout(const Duration(seconds: 5));
  final body = await utf8.decoder.bind(response).join().timeout(
        const Duration(seconds: 5),
      );
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'status endpoint returned HTTP ${response.statusCode}: $body',
      uri: uri,
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map) throw const FormatException('Expected JSON object.');
  return Map<String, Object?>.from(decoded);
}

class _Options {
  const _Options({
    required this.baseUri,
    required this.token,
    required this.duration,
    required this.pollInterval,
    required this.deviceLabel,
    required this.networkLane,
    required this.outputPath,
  });

  static const usage = '''
Usage: dart run tool/benchmarks/device_soak_harness.dart
  --base-url http://DEVICE_IP:8080 --token TOKEN [options]

Options:
  --duration-min N       Soak duration; default 30
  --poll-sec N           Status interval; default 5
  --device LABEL         Device/matrix label; default unspecified
  --network LANE         Network lane; default baseline
  --output PATH          JSONL output; stdout when omitted
''';

  final Uri baseUri;
  final String token;
  final Duration duration;
  final Duration pollInterval;
  final String deviceLabel;
  final String networkLane;
  final String? outputPath;

  static _Options? parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final key = arguments[index];
      if (!key.startsWith('--') || index + 1 >= arguments.length) return null;
      values[key.substring(2)] = arguments[++index];
    }
    final baseUri = Uri.tryParse(values['base-url'] ?? '');
    final token = values['token'];
    final durationMinutes = int.tryParse(values['duration-min'] ?? '30');
    final pollSeconds = int.tryParse(values['poll-sec'] ?? '5');
    if (baseUri == null ||
        !baseUri.hasScheme ||
        baseUri.host.isEmpty ||
        token == null ||
        token.isEmpty ||
        durationMinutes == null ||
        durationMinutes <= 0 ||
        pollSeconds == null ||
        pollSeconds <= 0) {
      return null;
    }
    return _Options(
      baseUri: baseUri,
      token: token,
      duration: Duration(minutes: durationMinutes),
      pollInterval: Duration(seconds: pollSeconds),
      deviceLabel: values['device'] ?? 'unspecified',
      networkLane: values['network'] ?? 'baseline',
      outputPath: values['output'],
    );
  }
}
