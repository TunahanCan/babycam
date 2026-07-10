// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultPlanPath = 'tool/device_matrix_plan.json';
const _resultSchemaPath = 'docs/device_matrix_result.schema.json';
const _tokenEnvironmentKey = 'MIMICAM_MATRIX_TOKEN';
const _maxStoredCommandChars = 24000;
const _maxHttpBodyBytes = 1024 * 1024;

Future<void> main(List<String> arguments) async {
  final options = _CliOptions.parse(arguments);
  if (options == null) {
    print(_CliOptions.usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    print(_CliOptions.usage);
    return;
  }

  try {
    if (options.selfTest) {
      await _runSelfTest(options.planPath);
      return;
    }
    if (options.evaluatePath != null) {
      final evaluation = await _evaluateFile(options.evaluatePath!);
      print(const JsonEncoder.withIndent('  ').convert(evaluation.json));
      exitCode = evaluation.exitCode;
      return;
    }
    if (options.recordPath != null) {
      final updated = await _recordResult(options);
      print(const JsonEncoder.withIndent('  ').convert(updated['summary']));
      return;
    }

    final plan = await _MatrixPlan.load(options.planPath);
    final result = await _MatrixRunner(plan, options).run();
    await _writeResult(
      result,
      outputPath: options.outputPath,
      force: options.force,
    );
    final automationStatus =
        ((result['automation'] as Map)['status'] ?? 'planned').toString();
    if (!options.dryRun && automationStatus == 'fail') exitCode = 1;
    if (!options.dryRun && automationStatus == 'blocked') exitCode = 2;
  } on _UsageException catch (error) {
    stderr.writeln('device-matrix: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('device-matrix: $error');
    exitCode = 66;
  } catch (error, stackTrace) {
    stderr.writeln('device-matrix: $error');
    if (options.verbose) stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

class _MatrixRunner {
  _MatrixRunner(this.plan, this.options);

  final _MatrixPlan plan;
  final _CliOptions options;

  Future<Map<String, Object?>> run() async {
    final selectedCases = plan.selectCases(
      ids: options.caseIds,
      mediaLane: options.mediaLane,
    );
    final createdAt = DateTime.now().toUtc();
    final plannedCommands = _plannedCommands();
    final cases = [
      for (final definition in selectedCases)
        _caseTemplate(
          definition,
          serverDeviceId: options.serverDeviceId,
          clientDeviceId: options.clientDeviceId,
        ),
    ];
    final result = <String, Object?>{
      r'$schema': _resultSchemaPath,
      'schemaVersion': 1,
      'suiteId': plan.suiteId,
      'runId': _runId(plan.suiteId, createdAt),
      'createdAt': createdAt.toIso8601String(),
      'completedAt': null,
      'git': <String, Object?>{'commit': null, 'dirty': null},
      'invocation': <String, Object?>{
        'dryRun': options.dryRun,
        'flutterBinary': options.flutterBinary,
        'buildMode': options.buildMode,
        'mediaLane': options.mediaLane,
        'selectedCaseIds': [
          for (final definition in selectedCases) definition.id,
        ],
        'plannedCommands': [
          for (final command in plannedCommands) command.json
        ],
      },
      'environment': <String, Object?>{
        'hostPlatform': Platform.operatingSystem,
        'workingDirectory': Directory.current.absolute.path,
        'networkLabel': options.networkLabel,
      },
      'devices': <Object?>[],
      'automation': <String, Object?>{
        'status': options.dryRun ? 'planned' : 'running',
        'deviceDiscovery': null,
        'preflightTests': null,
        'launches': <Object?>[],
        'probe': null,
        'messages': <String>[],
      },
      'cases': cases,
      'summary': _summary(cases, automationStatus: 'planned'),
    };

    if (options.dryRun) {
      final automation = result['automation'] as Map<String, Object?>;
      (automation['messages'] as List<String>).add(
        'Dry-run: no process, device, network or application state was changed.',
      );
      return result;
    }

    result['git'] = await _gitMetadata();
    final automation = result['automation'] as Map<String, Object?>;
    final messages = automation['messages'] as List<String>;
    var automationStatus = 'pass';

    final discovery = await _runCommand(
      options.flutterBinary,
      const ['devices', '--machine'],
      timeout: const Duration(minutes: 1),
    );
    automation['deviceDiscovery'] = discovery.json;
    List<_FlutterDevice> devices = const [];
    if (discovery.status == 'pass') {
      try {
        devices = _FlutterDevice.parseInventory(discovery.stdoutText ?? '');
        result['devices'] = [for (final device in devices) device.json];
        messages.add(
          '${devices.where((device) => device.physical).length} physical '
          'iOS/Android device(s) detected.',
        );
      } catch (error) {
        automationStatus = 'fail';
        messages.add('Could not parse flutter devices --machine: $error');
      }
    } else {
      automationStatus = discovery.status == 'timeout' ? 'fail' : 'blocked';
      messages.add('Flutter device discovery did not complete successfully.');
    }

    final deviceProblems = _validateSelectedDevices(devices);
    if (deviceProblems.isNotEmpty) {
      messages.addAll(deviceProblems);
      automationStatus = automationStatus == 'fail' ? 'fail' : 'blocked';
    }

    if (options.runTests) {
      final command = await _runCommand(
        options.flutterBinary,
        ['test', ...plan.preflightTests],
        timeout: const Duration(minutes: 15),
      );
      automation['preflightTests'] = command.json;
      if (command.status != 'pass') automationStatus = 'fail';
    }

    if (options.launch) {
      if (automationStatus == 'fail' || automationStatus == 'blocked') {
        messages.add(
          'Launch skipped because device discovery, selection or preflight failed.',
        );
        automation['launches'] = [
          for (final command in _launchCommands())
            command.copyWith(status: 'skipped').json,
        ];
      } else {
        final launches = <Object?>[];
        for (final planned in _launchCommands()) {
          final command = await _runCommand(
            planned.executable,
            planned.arguments,
            timeout: const Duration(minutes: 10),
          );
          launches.add(command.json);
          if (command.status != 'pass') {
            automationStatus = 'fail';
            break;
          }
        }
        automation['launches'] = launches;
      }
    }

    if (options.probe) {
      if (automationStatus == 'fail' || automationStatus == 'blocked') {
        messages.add('HTTP probe skipped because automation preflight failed.');
      } else {
        try {
          automation['probe'] = await _runServerProbe(options);
        } catch (error) {
          automationStatus = 'fail';
          automation['probe'] = <String, Object?>{
            'ok': false,
            'sampledAt': DateTime.now().toUtc().toIso8601String(),
            'error': error.toString(),
          };
        }
      }
    }

    automation['status'] = automationStatus;
    result['completedAt'] = DateTime.now().toUtc().toIso8601String();
    result['summary'] = _summary(
      cases,
      automationStatus: automationStatus,
    );
    return result;
  }

  List<_CommandResult> _plannedCommands() {
    final commands = <_CommandResult>[
      _CommandResult.planned(options.flutterBinary, const [
        'devices',
        '--machine',
      ]),
    ];
    if (options.runTests) {
      commands.add(_CommandResult.planned(
        options.flutterBinary,
        ['test', ...plan.preflightTests],
      ));
    }
    if (options.launch) commands.addAll(_launchCommands());
    return commands;
  }

  List<_CommandResult> _launchCommands() {
    final webRtc = options.mediaLane == 'webrtc';
    final modeFlag = '--${options.buildMode}';
    List<String> arguments(String deviceId) => [
          'run',
          '-d',
          deviceId,
          '--no-resident',
          modeFlag,
          '--dart-define=MIMICAM_WEBRTC_PILOT=$webRtc',
        ];
    return [
      _CommandResult.planned(
        options.flutterBinary,
        arguments(options.serverDeviceId!),
      ),
      _CommandResult.planned(
        options.flutterBinary,
        arguments(options.clientDeviceId!),
      ),
    ];
  }

  List<String> _validateSelectedDevices(List<_FlutterDevice> devices) {
    final problems = <String>[];
    for (final selection in <String, String?>{
      'server': options.serverDeviceId,
      'client': options.clientDeviceId,
    }.entries) {
      final id = selection.value;
      if (id == null) continue;
      final matches = devices.where((device) => device.id == id).toList();
      if (matches.isEmpty) {
        problems
            .add('${selection.key} device "$id" is not in flutter inventory.');
        continue;
      }
      final device = matches.single;
      if (!device.physical) {
        problems.add(
          '${selection.key} device "$id" is not a physical iOS/Android device.',
        );
      }
      if (!device.supported) {
        problems
            .add('${selection.key} device "$id" is not supported by Flutter.');
      }
    }
    if (options.serverDeviceId != null &&
        options.serverDeviceId == options.clientDeviceId) {
      problems.add('Server and client must be different physical devices.');
    }
    return problems;
  }
}

class _MatrixPlan {
  _MatrixPlan({
    required this.suiteId,
    required this.preflightTests,
    required this.cases,
  });

  final String suiteId;
  final List<String> preflightTests;
  final List<_MatrixCaseDefinition> cases;

  static Future<_MatrixPlan> load(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map) throw const FormatException('Plan must be an object.');
    final json = Map<String, Object?>.from(decoded);
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported plan schemaVersion.');
    }
    final suiteId = _nonEmptyString(json['suiteId'], 'suiteId');
    final preflight = _stringList(json['preflightTests'], 'preflightTests');
    final rawCases = json['cases'];
    if (rawCases is! List || rawCases.isEmpty) {
      throw const FormatException('Plan cases must be a non-empty list.');
    }
    final cases = <_MatrixCaseDefinition>[];
    final caseIds = <String>{};
    for (final raw in rawCases) {
      if (raw is! Map) {
        throw const FormatException('Every case must be an object.');
      }
      final definition = _MatrixCaseDefinition.fromJson(
        Map<String, Object?>.from(raw),
      );
      if (!caseIds.add(definition.id)) {
        throw FormatException('Duplicate case id: ${definition.id}');
      }
      cases.add(definition);
    }
    return _MatrixPlan(
      suiteId: suiteId,
      preflightTests: List.unmodifiable(preflight),
      cases: List.unmodifiable(cases),
    );
  }

  List<_MatrixCaseDefinition> selectCases({
    required List<String> ids,
    required String mediaLane,
  }) {
    final unknown = ids.where((id) => cases.every((item) => item.id != id));
    if (unknown.isNotEmpty) {
      throw _UsageException('Unknown case id(s): ${unknown.join(', ')}');
    }
    final selected = cases.where((definition) {
      if (ids.isNotEmpty && !ids.contains(definition.id)) {
        return false;
      }
      return mediaLane == 'mixed' ||
          definition.mediaLane == mediaLane ||
          definition.mediaLane == 'both';
    }).toList(growable: false);
    if (selected.isEmpty) {
      throw const _UsageException(
          'No matrix cases match the selected filters.');
    }
    return selected;
  }
}

class _MatrixCaseDefinition {
  _MatrixCaseDefinition({
    required this.id,
    required this.title,
    required this.platforms,
    required this.mediaLane,
    required this.networkLane,
    required this.estimatedMinutes,
    required this.setup,
    required this.steps,
    required this.checks,
    required this.measurements,
    required this.requiredArtifacts,
  });

  final String id;
  final String title;
  final List<String> platforms;
  final String mediaLane;
  final String networkLane;
  final int estimatedMinutes;
  final List<String> setup;
  final List<String> steps;
  final List<Map<String, Object?>> checks;
  final List<Map<String, Object?>> measurements;
  final List<String> requiredArtifacts;

  factory _MatrixCaseDefinition.fromJson(Map<String, Object?> json) {
    final id = _nonEmptyString(json['id'], 'case.id');
    final mediaLane = _nonEmptyString(json['mediaLane'], '$id.mediaLane');
    if (!const {'legacy', 'webrtc', 'both'}.contains(mediaLane)) {
      throw FormatException('$id.mediaLane must be legacy, webrtc or both.');
    }
    final platforms = _stringList(json['platforms'], '$id.platforms');
    if (platforms.isEmpty ||
        platforms.any((value) => value != 'ios' && value != 'android')) {
      throw FormatException('$id.platforms must contain iOS/Android lanes.');
    }
    final estimated = json['estimatedMinutes'];
    if (estimated is! int || estimated <= 0) {
      throw FormatException('$id.estimatedMinutes must be positive.');
    }
    final checks = _objectList(json['checks'], '$id.checks');
    if (checks.isEmpty) throw FormatException('$id.checks must not be empty.');
    final checkIds = <String>{};
    for (final check in checks) {
      final checkId = _nonEmptyString(check['id'], '$id.check.id');
      _nonEmptyString(check['description'], '$id.$checkId.description');
      if (!checkIds.add(checkId)) {
        throw FormatException('$id has duplicate check id $checkId.');
      }
    }
    final measurements = _objectList(
      json['measurements'] ?? const [],
      '$id.measurements',
    );
    final measurementIds = <String>{};
    for (final measurement in measurements) {
      final measurementId =
          _nonEmptyString(measurement['id'], '$id.measurement.id');
      if (!measurementIds.add(measurementId)) {
        throw FormatException(
          '$id has duplicate measurement id $measurementId.',
        );
      }
      final required = measurement['required'];
      if (required is! bool) {
        throw FormatException('$id.$measurementId.required must be boolean.');
      }
      final operator = measurement['operator'];
      final threshold = measurement['threshold'];
      if (operator != null || threshold != null) {
        if (!const {'<', '<=', '>', '>=', '=='}.contains(operator) ||
            threshold is! num) {
          throw FormatException('$id.$measurementId has an invalid gate.');
        }
      }
    }
    return _MatrixCaseDefinition(
      id: id,
      title: _nonEmptyString(json['title'], '$id.title'),
      platforms: List.unmodifiable(platforms),
      mediaLane: mediaLane,
      networkLane: _nonEmptyString(json['networkLane'], '$id.networkLane'),
      estimatedMinutes: estimated,
      setup: List.unmodifiable(_stringList(json['setup'], '$id.setup')),
      steps: List.unmodifiable(_stringList(json['steps'], '$id.steps')),
      checks: List.unmodifiable(checks),
      measurements: List.unmodifiable(measurements),
      requiredArtifacts: List.unmodifiable(
        _stringList(json['requiredArtifacts'], '$id.requiredArtifacts'),
      ),
    );
  }
}

class _FlutterDevice {
  _FlutterDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.targetPlatform,
    required this.emulator,
    required this.supported,
    required this.sdk,
  });

  final String id;
  final String name;
  final String platform;
  final String targetPlatform;
  final bool emulator;
  final bool supported;
  final String? sdk;
  bool get physical =>
      !emulator && (platform == 'ios' || platform == 'android');

  Map<String, Object?> get json => {
        'id': id,
        'name': name,
        'platform': platform,
        'targetPlatform': targetPlatform,
        'emulator': emulator,
        'physical': physical,
        'supported': supported,
        'sdk': sdk,
      };

  static List<_FlutterDevice> parseInventory(String value) {
    final first = value.indexOf('[');
    final last = value.lastIndexOf(']');
    if (first < 0 || last < first) {
      throw const FormatException(
          'Device inventory did not contain a JSON list.');
    }
    final decoded = jsonDecode(value.substring(first, last + 1));
    if (decoded is! List) throw const FormatException('Expected device list.');
    return List.unmodifiable([
      for (final raw in decoded)
        if (raw is Map) _FlutterDevice.fromJson(Map<String, Object?>.from(raw)),
    ]);
  }

  factory _FlutterDevice.fromJson(Map<String, Object?> json) {
    final targetPlatform = json['targetPlatform']?.toString() ?? '';
    final platform = targetPlatform.startsWith('ios')
        ? 'ios'
        : targetPlatform.startsWith('android')
            ? 'android'
            : 'other';
    return _FlutterDevice(
      id: _nonEmptyString(json['id'], 'device.id'),
      name: _nonEmptyString(json['name'], 'device.name'),
      platform: platform,
      targetPlatform: targetPlatform,
      emulator: json['emulator'] == true,
      supported: json['isSupported'] != false,
      sdk: json['sdk']?.toString(),
    );
  }
}

class _CommandResult {
  _CommandResult({
    required this.executable,
    required this.arguments,
    required this.status,
    required this.exitCode,
    required this.durationMs,
    required this.stdoutText,
    required this.stderrText,
  });

  factory _CommandResult.planned(String executable, List<String> arguments) =>
      _CommandResult(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        status: 'planned',
        exitCode: null,
        durationMs: null,
        stdoutText: null,
        stderrText: null,
      );

  final String executable;
  final List<String> arguments;
  final String status;
  final int? exitCode;
  final int? durationMs;
  final String? stdoutText;
  final String? stderrText;

  _CommandResult copyWith({String? status}) => _CommandResult(
        executable: executable,
        arguments: arguments,
        status: status ?? this.status,
        exitCode: exitCode,
        durationMs: durationMs,
        stdoutText: stdoutText,
        stderrText: stderrText,
      );

  Map<String, Object?> get json => {
        'executable': executable,
        'arguments': arguments,
        'status': status,
        'exitCode': exitCode,
        'durationMs': durationMs,
        'stdout': stdoutText,
        'stderr': stderrText,
      };
}

Future<_CommandResult> _runCommand(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: Directory.current.path,
      runInShell: false,
    );
    final stdoutFuture = _readBounded(process.stdout);
    final stderrFuture = _readBounded(process.stderr);
    int? code;
    var timedOut = false;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      try {
        code = await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    final output = await stdoutFuture;
    final errors = await stderrFuture;
    stopwatch.stop();
    return _CommandResult(
      executable: executable,
      arguments: List.unmodifiable(arguments),
      status: timedOut
          ? 'timeout'
          : code == 0
              ? 'pass'
              : 'fail',
      exitCode: code,
      durationMs: stopwatch.elapsedMilliseconds,
      stdoutText: output,
      stderrText: timedOut
          ? '${errors ?? ''}\nTimed out after ${timeout.inSeconds} seconds.'
              .trim()
          : errors,
    );
  } on ProcessException catch (error) {
    stopwatch.stop();
    return _CommandResult(
      executable: executable,
      arguments: List.unmodifiable(arguments),
      status: 'fail',
      exitCode: null,
      durationMs: stopwatch.elapsedMilliseconds,
      stdoutText: null,
      stderrText: error.toString(),
    );
  }
}

Future<String?> _readBounded(Stream<List<int>> input) async {
  final buffer = StringBuffer();
  var truncated = false;
  await for (final text in input.transform(utf8.decoder)) {
    final remaining = _maxStoredCommandChars - buffer.length;
    if (remaining <= 0) {
      truncated = true;
      continue;
    }
    if (text.length <= remaining) {
      buffer.write(text);
    } else {
      buffer.write(text.substring(0, remaining));
      truncated = true;
    }
  }
  if (truncated) buffer.write('\n... output truncated ...');
  final value = buffer.toString().trim();
  return value.isEmpty ? null : value;
}

Future<Map<String, Object?>> _gitMetadata() async {
  final commit = await _runCommand(
    'git',
    const ['rev-parse', 'HEAD'],
    timeout: const Duration(seconds: 10),
  );
  final status = await _runCommand(
    'git',
    const ['status', '--porcelain'],
    timeout: const Duration(seconds: 10),
  );
  return {
    'commit': commit.status == 'pass' ? commit.stdoutText : null,
    'dirty': status.status == 'pass' ? status.stdoutText != null : null,
  };
}

Future<Map<String, Object?>> _runServerProbe(_CliOptions options) async {
  final token = Platform.environment[_tokenEnvironmentKey];
  if (token == null || token.trim().isEmpty) {
    throw const _UsageException(
      '--probe requires $_tokenEnvironmentKey in the environment.',
    );
  }
  final base = options.baseUri!;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final status = await _requestJson(
      client,
      base.resolve('/test/status'),
      token: token,
    );
    final probe = await _requestJson(
      client,
      base.resolve('/test/probe'),
      token: token,
      body: {
        'startRuntime': true,
        'waitMs': 2500,
        'requireVideo': true,
        'requireAudio': true,
        'emitAlert': true,
        'requireEvents': true,
        'requireEventDelivery': false,
        'loopbackMedia': true,
        'useAudioTone': options.probeAudioTone,
      },
    );
    return {
      'ok': probe['ok'] == true,
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'baseUrl': base.replace(userInfo: '').toString(),
      'tokenSource': 'environment:$_tokenEnvironmentKey',
      'audioMode': options.probeAudioTone ? 'tone' : 'microphone',
      'status': status,
      'probe': probe,
    };
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _requestJson(
  HttpClient client,
  Uri uri, {
  required String token,
  Map<String, Object?>? body,
}) async {
  final request = body == null
      ? await client.getUrl(uri).timeout(const Duration(seconds: 5))
      : await client.postUrl(uri).timeout(const Duration(seconds: 5));
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
    ..set(HttpHeaders.acceptHeader, 'application/json');
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close().timeout(const Duration(seconds: 8));
  final bytes = <int>[];
  await for (final chunk in response.timeout(const Duration(seconds: 8))) {
    if (bytes.length + chunk.length > _maxHttpBodyBytes) {
      throw HttpException('Response exceeded $_maxHttpBodyBytes bytes.',
          uri: uri);
    }
    bytes.addAll(chunk);
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map) throw FormatException('Expected JSON object from $uri.');
  return Map<String, Object?>.from(decoded);
}

Map<String, Object?> _caseTemplate(
  _MatrixCaseDefinition definition, {
  required String? serverDeviceId,
  required String? clientDeviceId,
}) =>
    {
      'id': definition.id,
      'title': definition.title,
      'status': 'planned',
      'serverDeviceId': serverDeviceId,
      'clientDeviceId': clientDeviceId,
      'platforms': definition.platforms,
      'mediaLane': definition.mediaLane,
      'networkLane': definition.networkLane,
      'estimatedMinutes': definition.estimatedMinutes,
      'startedAt': null,
      'completedAt': null,
      'setup': definition.setup,
      'steps': definition.steps,
      'checks': [
        for (final check in definition.checks)
          {
            'id': check['id'],
            'description': check['description'],
            'status': 'planned',
            'note': null,
          },
      ],
      'measurements': <String, Object?>{
        for (final measurement in definition.measurements)
          measurement['id']!.toString(): null,
      },
      'measurementDefinitions': definition.measurements,
      'observations': <String>[],
      'artifacts': <String>[],
      'requiredArtifacts': definition.requiredArtifacts,
      'diagnostics': <String, Object?>{},
    };

Map<String, Object?> _summary(
  List<Object?> cases, {
  required String automationStatus,
  List<String> gateFailures = const [],
  List<String> validationFailures = const [],
}) {
  final counts = <String, int>{};
  for (final raw in cases) {
    if (raw is! Map) continue;
    final status = raw['status']?.toString() ?? 'planned';
    counts[status] = (counts[status] ?? 0) + 1;
  }
  String overall;
  if (automationStatus == 'fail' ||
      automationStatus == 'timeout' ||
      gateFailures.isNotEmpty ||
      validationFailures.isNotEmpty ||
      (counts['fail'] ?? 0) > 0 ||
      (counts['timeout'] ?? 0) > 0) {
    overall = 'fail';
  } else if (automationStatus == 'blocked' || (counts['blocked'] ?? 0) > 0) {
    overall = 'blocked';
  } else if (automationStatus == 'running' || (counts['running'] ?? 0) > 0) {
    overall = 'running';
  } else if (automationStatus != 'pass') {
    overall = 'planned';
  } else if (cases.isNotEmpty && (counts['pass'] ?? 0) == cases.length) {
    overall = 'pass';
  } else if (cases.isNotEmpty && (counts['skipped'] ?? 0) == cases.length) {
    overall = 'skipped';
  } else {
    overall = 'planned';
  }
  return {
    'status': overall,
    'total': cases.length,
    'counts': counts,
    'gateFailures': gateFailures,
    'validationFailures': validationFailures,
  };
}

Future<Map<String, Object?>> _recordResult(_CliOptions options) async {
  final path = options.recordPath!;
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map) throw const FormatException('Result must be an object.');
  final result = Map<String, Object?>.from(decoded);
  final cases = result['cases'];
  if (cases is! List) {
    throw const FormatException('Result cases must be a list.');
  }
  final id = options.caseIds.single;
  final matches =
      cases.whereType<Map>().where((item) => item['id'] == id).toList();
  if (matches.length != 1) {
    throw _UsageException('Result has no unique case "$id".');
  }
  final testCase = Map<String, Object?>.from(matches.single);
  final caseIndex = cases.indexOf(matches.single);
  final now = DateTime.now().toUtc().toIso8601String();
  testCase['status'] = options.recordStatus;
  testCase['startedAt'] ??= now;
  testCase['completedAt'] = now;

  final checks = (testCase['checks'] as List?) ?? <Object?>[];
  if (options.allChecksPass) {
    for (var index = 0; index < checks.length; index++) {
      final raw = checks[index];
      if (raw is! Map) continue;
      final check = Map<String, Object?>.from(raw);
      check['status'] = 'pass';
      checks[index] = check;
    }
  }
  for (final update in options.checkUpdates) {
    final parsed = _splitAssignment(update, '--check');
    if (!_recordStatuses.contains(parsed.value)) {
      throw _UsageException('Invalid check status: ${parsed.value}');
    }
    final index = checks.indexWhere(
      (raw) => raw is Map && raw['id']?.toString() == parsed.key,
    );
    if (index < 0) throw _UsageException('Unknown check id: ${parsed.key}');
    final check = Map<String, Object?>.from(checks[index] as Map);
    check['status'] = parsed.value;
    checks[index] = check;
  }
  testCase['checks'] = checks;

  final measurements = Map<String, Object?>.from(
    (testCase['measurements'] as Map?) ?? const {},
  );
  for (final update in options.measurementUpdates) {
    final parsed = _splitAssignment(update, '--measure');
    if (!measurements.containsKey(parsed.key)) {
      throw _UsageException('Unknown measurement id: ${parsed.key}');
    }
    measurements[parsed.key] = _parseScalar(parsed.value);
  }
  testCase['measurements'] = measurements;
  testCase['observations'] = [
    ...((testCase['observations'] as List?) ?? const []),
    ...options.notes,
  ];
  testCase['artifacts'] = [
    ...((testCase['artifacts'] as List?) ?? const []),
    ...options.artifacts,
  ];
  cases[caseIndex] = testCase;

  final evaluation = _evaluateResultMap(result, requireCompletedCases: true);
  final currentAutomationStatus =
      ((result['automation'] as Map?)?['status'] ?? 'planned').toString();
  result['completedAt'] = now;
  result['summary'] = _summary(
    cases,
    automationStatus:
        evaluation.exitCode == 1 ? 'fail' : currentAutomationStatus,
    gateFailures: evaluation.gateFailures,
    validationFailures: [
      ...((evaluation.json['failures'] as List).cast<String>()),
      ...((evaluation.json['incomplete'] as List).cast<String>()),
    ],
  );
  await File(path).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    flush: true,
  );
  return result;
}

Future<_Evaluation> _evaluateFile(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map) throw const FormatException('Result must be an object.');
  return _evaluateResultMap(
    Map<String, Object?>.from(decoded),
    requireCompletedCases: true,
  );
}

_Evaluation _evaluateResultMap(
  Map<String, Object?> result, {
  required bool requireCompletedCases,
}) {
  if (result['schemaVersion'] != 1) {
    throw const FormatException('Unsupported result schemaVersion.');
  }
  final cases = result['cases'];
  if (cases is! List || cases.isEmpty) {
    throw const FormatException('Result cases must be non-empty.');
  }
  final failures = <String>[];
  final incomplete = <String>[];
  final gateFailures = <String>[];
  final deviceInventory = <String, Map<String, Object?>>{};
  final rawDevices = result['devices'];
  if (rawDevices is List) {
    for (final raw in rawDevices) {
      if (raw is! Map) continue;
      final device = Map<String, Object?>.from(raw);
      final id = device['id']?.toString();
      if (id != null && id.isNotEmpty) deviceInventory[id] = device;
    }
  }
  for (final raw in cases) {
    if (raw is! Map) throw const FormatException('Invalid result case.');
    final testCase = Map<String, Object?>.from(raw);
    final id = _nonEmptyString(testCase['id'], 'case.id');
    final status = testCase['status']?.toString() ?? 'planned';
    if (status == 'fail' || status == 'timeout') {
      failures.add('$id status=$status');
    } else if (requireCompletedCases && status != 'pass') {
      incomplete.add('$id status=$status');
    }
    if (requireCompletedCases && status == 'pass') {
      final serverId = testCase['serverDeviceId']?.toString().trim() ?? '';
      final clientId = testCase['clientDeviceId']?.toString().trim() ?? '';
      if (serverId.isEmpty || clientId.isEmpty || serverId == clientId) {
        failures.add('$id requires two different physical device IDs');
      } else {
        for (final selectedId in [serverId, clientId]) {
          final device = deviceInventory[selectedId];
          if (device == null ||
              device['physical'] != true ||
              device['supported'] != true) {
            failures
                .add('$id device $selectedId lacks physical inventory proof');
          }
        }
        final platforms = (testCase['platforms'] as List?)
                ?.map((value) => value.toString())
                .toSet() ??
            const <String>{};
        final selectedPlatforms = {
          deviceInventory[serverId]?['platform']?.toString(),
          deviceInventory[clientId]?['platform']?.toString(),
        }..remove(null);
        if (selectedPlatforms.intersection(platforms).isEmpty) {
          failures.add(
            '$id selected platforms ${selectedPlatforms.join(',')} are '
            'outside ${platforms.join(',')}',
          );
        }
      }
      final artifacts = (testCase['artifacts'] as List?) ?? const [];
      final requiredArtifacts =
          (testCase['requiredArtifacts'] as List?) ?? const [];
      if (artifacts.length < requiredArtifacts.length) {
        failures.add(
          '$id has ${artifacts.length}/${requiredArtifacts.length} required '
          'evidence artifacts',
        );
      }
      if (testCase['completedAt'] == null) {
        failures.add('$id completedAt is missing');
      }
    }
    final checks = testCase['checks'];
    if (checks is! List || checks.isEmpty) {
      failures.add('$id has no checks');
    } else {
      for (final rawCheck in checks) {
        if (rawCheck is! Map) {
          failures.add('$id has an invalid check');
          continue;
        }
        final checkId = rawCheck['id']?.toString() ?? 'unknown';
        final checkStatus = rawCheck['status']?.toString() ?? 'planned';
        if (status == 'pass' && checkStatus != 'pass') {
          failures.add('$id.$checkId check=$checkStatus');
        }
      }
    }
    final values = Map<String, Object?>.from(
      (testCase['measurements'] as Map?) ?? const {},
    );
    final definitions = testCase['measurementDefinitions'];
    if (definitions is! List) {
      failures.add('$id has invalid measurement definitions');
      continue;
    }
    for (final rawDefinition in definitions) {
      if (rawDefinition is! Map) continue;
      final definition = Map<String, Object?>.from(rawDefinition);
      final metricId = definition['id']?.toString() ?? 'unknown';
      final value = values[metricId];
      if (definition['required'] == true && value == null && status == 'pass') {
        failures.add('$id.$metricId is required');
        continue;
      }
      final operator = definition['operator'];
      final threshold = definition['threshold'];
      if (value == null || operator == null || threshold == null) continue;
      if (value is! num || threshold is! num) {
        failures.add('$id.$metricId must be numeric');
        continue;
      }
      if (!_gatePasses(value, operator.toString(), threshold)) {
        final message = '$id.$metricId=$value must be $operator $threshold';
        failures.add(message);
        gateFailures.add(message);
      }
    }
  }
  final automation = (result['automation'] as Map?) ?? const {};
  final automationStatus = (automation['status'] ?? 'planned').toString();
  if (automationStatus == 'fail') failures.add('automation status=fail');
  if (requireCompletedCases && automationStatus != 'pass') {
    incomplete.add('automation status=$automationStatus');
  }
  if (requireCompletedCases) {
    final discovery = automation['deviceDiscovery'];
    if (discovery is! Map || discovery['status'] != 'pass') {
      incomplete.add('flutter devices preflight is not passed');
    }
    final preflight = automation['preflightTests'];
    if (preflight is! Map || preflight['status'] != 'pass') {
      incomplete.add('focused flutter test preflight is not passed');
    }
  }
  final status = failures.isNotEmpty
      ? 'fail'
      : incomplete.isNotEmpty
          ? 'incomplete'
          : 'pass';
  return _Evaluation(
    exitCode: failures.isNotEmpty
        ? 1
        : incomplete.isNotEmpty
            ? 2
            : 0,
    gateFailures: gateFailures,
    json: {
      'status': status,
      'suiteId': result['suiteId'],
      'runId': result['runId'],
      'caseCount': cases.length,
      'failures': failures,
      'incomplete': incomplete,
      'gateFailures': gateFailures,
    },
  );
}

class _Evaluation {
  const _Evaluation({
    required this.exitCode,
    required this.gateFailures,
    required this.json,
  });

  final int exitCode;
  final List<String> gateFailures;
  final Map<String, Object?> json;
}

bool _gatePasses(num value, String operator, num threshold) =>
    switch (operator) {
      '<' => value < threshold,
      '<=' => value <= threshold,
      '>' => value > threshold,
      '>=' => value >= threshold,
      '==' => value == threshold,
      _ => false,
    };

Future<void> _runSelfTest(String planPath) async {
  final plan = await _MatrixPlan.load(planPath);
  final schema = jsonDecode(await File(_resultSchemaPath).readAsString());
  _expect(schema is Map, 'result schema parses');
  _expect(plan.cases.length >= 10, 'plan contains the physical matrix');
  _expect(
      plan.cases.any((item) => item.id == 'NET-IPv6-01'), 'IPv6 case exists');
  _expect(plan.cases.any((item) => item.id == 'WEBRTC-Codec-01'),
      'codec case exists');
  final devices = _FlutterDevice.parseInventory(jsonEncode([
    {
      'id': 'ios-device',
      'name': 'iPhone',
      'targetPlatform': 'ios',
      'emulator': false,
      'isSupported': true,
      'sdk': 'iOS 18',
    },
    {
      'id': 'android-device',
      'name': 'Pixel',
      'targetPlatform': 'android-arm64',
      'emulator': false,
      'isSupported': true,
      'sdk': 'Android 15',
    },
  ]));
  _expect(devices.length == 2 && devices.every((item) => item.physical),
      'physical device inventory parsing');
  _expect(_gatePasses(399, '<', 400), 'passing gate');
  _expect(!_gatePasses(400, '<', 400), 'strict gate failure');

  final definition = plan.cases.first;
  final resultCase = _caseTemplate(
    definition,
    serverDeviceId: 'ios-device',
    clientDeviceId: 'android-device',
  );
  resultCase['status'] = 'pass';
  resultCase['completedAt'] = DateTime.now().toUtc().toIso8601String();
  final selfTestArtifacts = resultCase['artifacts'] as List<String>;
  final requiredArtifacts = resultCase['requiredArtifacts'] as List<String>;
  for (var index = 0; index < requiredArtifacts.length; index++) {
    selfTestArtifacts.add('self-test-evidence-$index.json');
  }
  for (final raw in resultCase['checks'] as List) {
    (raw as Map)['status'] = 'pass';
  }
  final values = resultCase['measurements'] as Map<String, Object?>;
  for (final raw in resultCase['measurementDefinitions'] as List) {
    final measurement = raw as Map;
    final threshold = measurement['threshold'];
    if (threshold is! num) continue;
    values[measurement['id'].toString()] = switch (measurement['operator']) {
      '<' => threshold - 1,
      '>' => threshold + 1,
      _ => threshold,
    };
  }
  final evaluation = _evaluateResultMap({
    'schemaVersion': 1,
    'suiteId': plan.suiteId,
    'runId': 'self-test',
    'automation': {
      'status': 'pass',
      'deviceDiscovery': {'status': 'pass'},
      'preflightTests': {'status': 'pass'},
    },
    'devices': [for (final device in devices) device.json],
    'cases': [resultCase],
  }, requireCompletedCases: true);
  _expect(evaluation.exitCode == 0, 'completed result evaluates as pass');
  print(jsonEncode({
    'result': 'pass',
    'planCases': plan.cases.length,
    'devicesParsed': devices.length,
    'schema': _resultSchemaPath,
  }));
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError('Self-test failed: $label');
}

Future<void> _writeResult(
  Map<String, Object?> result, {
  required String? outputPath,
  required bool force,
}) async {
  final value = '${const JsonEncoder.withIndent('  ').convert(result)}\n';
  if (outputPath == null) {
    stdout.write(value);
    return;
  }
  final file = File(outputPath);
  if (await file.exists() && !force) {
    throw _UsageException(
      'Output already exists: $outputPath (use --force to replace it).',
    );
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(value, flush: true);
  print(jsonEncode({'result': 'written', 'output': file.absolute.path}));
}

String _runId(String suiteId, DateTime now) =>
    '${suiteId}_${now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}';

String _nonEmptyString(Object? value, String field) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) throw FormatException('$field must be non-empty.');
  return text;
}

List<String> _stringList(Object? value, String field) {
  if (value is! List) throw FormatException('$field must be a list.');
  return [
    for (final item in value) _nonEmptyString(item, field),
  ];
}

List<Map<String, Object?>> _objectList(Object? value, String field) {
  if (value is! List) throw FormatException('$field must be a list.');
  return [
    for (final item in value)
      if (item is Map)
        Map<String, Object?>.from(item)
      else
        throw FormatException('$field contains a non-object value.'),
  ];
}

({String key, String value}) _splitAssignment(String value, String flag) {
  final separator = value.indexOf('=');
  if (separator <= 0 || separator == value.length - 1) {
    throw _UsageException('$flag requires KEY=VALUE.');
  }
  return (
    key: value.substring(0, separator).trim(),
    value: value.substring(separator + 1).trim(),
  );
}

Object _parseScalar(String value) {
  if (value == 'true') return true;
  if (value == 'false') return false;
  return int.tryParse(value) ?? double.tryParse(value) ?? value;
}

const _recordStatuses = {'pass', 'fail', 'blocked', 'skipped'};

class _CliOptions {
  _CliOptions({
    required this.help,
    required this.selfTest,
    required this.dryRun,
    required this.runTests,
    required this.launch,
    required this.probe,
    required this.probeAudioTone,
    required this.force,
    required this.verbose,
    required this.allChecksPass,
    required this.planPath,
    required this.outputPath,
    required this.evaluatePath,
    required this.recordPath,
    required this.flutterBinary,
    required this.serverDeviceId,
    required this.clientDeviceId,
    required this.baseUri,
    required this.buildMode,
    required this.mediaLane,
    required this.networkLabel,
    required this.recordStatus,
    required this.caseIds,
    required this.checkUpdates,
    required this.measurementUpdates,
    required this.notes,
    required this.artifacts,
  });

  static const usage = '''
MimiCam physical-device matrix runner

Generate a no-side-effect result template:
  dart run tool/device_matrix_runner.dart --dry-run --output /tmp/matrix.json

Discover and validate two physical devices, then run safe preflight tests:
  dart run tool/device_matrix_runner.dart \\
    --server-device IOS_ID --client-device ANDROID_ID --run-tests \\
    --output artifacts/device-matrix/preflight.json

Launch a profile build on both devices (explicit opt-in):
  dart run tool/device_matrix_runner.dart \\
    --server-device IOS_ID --client-device ANDROID_ID \\
    --media-lane webrtc --launch --output artifacts/device-matrix/run.json

Authenticated server probe (token is read only from the environment):
  MIMICAM_MATRIX_TOKEN=... dart run tool/device_matrix_runner.dart \\
    --base-url http://192.168.1.42:8080 --probe --output /tmp/probe.json

Record and evaluate operator evidence:
  dart run tool/device_matrix_runner.dart --record RESULT.json \\
    --case NET-IPv4-01 --status pass --all-checks-pass \\
    --measure legacyVideoLatencyP95Ms=420 --measure audioStartupP95Ms=310 \\
    --artifact artifacts/soak/run.jsonl --note "cross-platform direction A"
  dart run tool/device_matrix_runner.dart --evaluate RESULT.json

Options:
  --plan PATH              Plan JSON; default tool/device_matrix_plan.json
  --output PATH            New result JSON; stdout when omitted
  --force                  Replace an existing --output file
  --dry-run                Execute no commands, HTTP calls or device actions
  --self-test              Validate parser, plan, schema and gate evaluator
  --flutter PATH           Flutter executable; defaults to FLUTTER_BIN or flutter
  --server-device ID       Physical device used as room/server
  --client-device ID       Different physical watching device
  --case ID                Include case; may be repeated
  --media-lane LANE        legacy, webrtc or mixed; default mixed
  --network LABEL          Result metadata; default unspecified
  --build-mode MODE        debug, profile or release; default profile
  --run-tests              Run the focused flutter test list from the plan
  --launch                 Run flutter run --no-resident on both devices
  --base-url URL           Paired server URL for --probe
  --probe                  GET /test/status and POST /test/probe
  --probe-audio-tone       Probe WAV path with a synthetic tone, not microphone
  --record PATH            Update an existing result JSON
  --status STATUS          pass, fail, blocked or skipped for --record
  --all-checks-pass        Mark every check in the recorded case passed
  --check ID=STATUS        Update one case check; may be repeated
  --measure ID=VALUE       Record a measurement; may be repeated
  --artifact PATH          Append evidence path; may be repeated
  --note TEXT              Append an operator observation; may be repeated
  --evaluate PATH          Evaluate completed checks and numeric gates
  --verbose                Print stack traces for runner failures
  --help                   Show this text

The runner never invokes a shell and never accepts a token on the command line.
Wi-Fi, call, route and thermal transitions remain explicit operator actions.
''';

  final bool help;
  final bool selfTest;
  final bool dryRun;
  final bool runTests;
  final bool launch;
  final bool probe;
  final bool probeAudioTone;
  final bool force;
  final bool verbose;
  final bool allChecksPass;
  final String planPath;
  final String? outputPath;
  final String? evaluatePath;
  final String? recordPath;
  final String flutterBinary;
  final String? serverDeviceId;
  final String? clientDeviceId;
  final Uri? baseUri;
  final String buildMode;
  final String mediaLane;
  final String networkLabel;
  final String? recordStatus;
  final List<String> caseIds;
  final List<String> checkUpdates;
  final List<String> measurementUpdates;
  final List<String> notes;
  final List<String> artifacts;

  static _CliOptions? parse(List<String> arguments) {
    var help = false;
    var selfTest = false;
    var dryRun = false;
    var runTests = false;
    var launch = false;
    var probe = false;
    var probeAudioTone = false;
    var force = false;
    var verbose = false;
    var allChecksPass = false;
    var planPath = _defaultPlanPath;
    String? outputPath;
    String? evaluatePath;
    String? recordPath;
    var flutterBinary = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
    String? serverDeviceId;
    String? clientDeviceId;
    Uri? baseUri;
    var buildMode = 'profile';
    var mediaLane = 'mixed';
    var networkLabel = 'unspecified';
    String? recordStatus;
    final caseIds = <String>[];
    final checkUpdates = <String>[];
    final measurementUpdates = <String>[];
    final notes = <String>[];
    final artifacts = <String>[];

    String? nextValue(int index) =>
        index + 1 < arguments.length ? arguments[index + 1] : null;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      switch (argument) {
        case '--help' || '-h':
          help = true;
        case '--self-test':
          selfTest = true;
        case '--dry-run':
          dryRun = true;
        case '--run-tests':
          runTests = true;
        case '--launch':
          launch = true;
        case '--probe':
          probe = true;
        case '--probe-audio-tone':
          probeAudioTone = true;
        case '--force':
          force = true;
        case '--verbose':
          verbose = true;
        case '--all-checks-pass':
          allChecksPass = true;
        case '--plan':
          final value = nextValue(index);
          if (value == null) return null;
          planPath = value;
          index++;
        case '--output':
          outputPath = nextValue(index);
          if (outputPath == null) return null;
          index++;
        case '--evaluate':
          evaluatePath = nextValue(index);
          if (evaluatePath == null) return null;
          index++;
        case '--record':
          recordPath = nextValue(index);
          if (recordPath == null) return null;
          index++;
        case '--flutter':
          flutterBinary = nextValue(index) ?? '';
          if (flutterBinary.isEmpty) return null;
          index++;
        case '--server-device':
          serverDeviceId = nextValue(index);
          if (serverDeviceId == null) return null;
          index++;
        case '--client-device':
          clientDeviceId = nextValue(index);
          if (clientDeviceId == null) return null;
          index++;
        case '--base-url':
          final value = nextValue(index);
          if (value == null) return null;
          baseUri = Uri.tryParse(value);
          index++;
        case '--build-mode':
          buildMode = nextValue(index) ?? '';
          index++;
        case '--media-lane':
          mediaLane = nextValue(index) ?? '';
          index++;
        case '--network':
          networkLabel = nextValue(index) ?? '';
          index++;
        case '--status':
          recordStatus = nextValue(index);
          if (recordStatus == null) return null;
          index++;
        case '--case':
          final value = nextValue(index);
          if (value == null) return null;
          caseIds.add(value);
          index++;
        case '--check':
          final value = nextValue(index);
          if (value == null) return null;
          checkUpdates.add(value);
          index++;
        case '--measure':
          final value = nextValue(index);
          if (value == null) return null;
          measurementUpdates.add(value);
          index++;
        case '--note':
          final value = nextValue(index);
          if (value == null) return null;
          notes.add(value);
          index++;
        case '--artifact':
          final value = nextValue(index);
          if (value == null) return null;
          artifacts.add(value);
          index++;
        default:
          return null;
      }
    }

    if (!const {'debug', 'profile', 'release'}.contains(buildMode) ||
        !const {'legacy', 'webrtc', 'mixed'}.contains(mediaLane) ||
        networkLabel.trim().isEmpty) {
      return null;
    }
    if (probe &&
        (baseUri == null ||
            !const {'http', 'https'}.contains(baseUri.scheme) ||
            baseUri.host.isEmpty ||
            baseUri.userInfo.isNotEmpty)) {
      return null;
    }
    if ((serverDeviceId == null) != (clientDeviceId == null)) {
      return null;
    }
    if (launch &&
        (serverDeviceId == null ||
            clientDeviceId == null ||
            mediaLane == 'mixed')) {
      return null;
    }
    if (recordPath != null &&
        (caseIds.length != 1 ||
            recordStatus == null ||
            !_recordStatuses.contains(recordStatus))) {
      return null;
    }
    final modes = [selfTest, evaluatePath != null, recordPath != null]
        .where((active) => active)
        .length;
    if (modes > 1) return null;
    return _CliOptions(
      help: help,
      selfTest: selfTest,
      dryRun: dryRun,
      runTests: runTests,
      launch: launch,
      probe: probe,
      probeAudioTone: probeAudioTone,
      force: force,
      verbose: verbose,
      allChecksPass: allChecksPass,
      planPath: planPath,
      outputPath: outputPath,
      evaluatePath: evaluatePath,
      recordPath: recordPath,
      flutterBinary: flutterBinary,
      serverDeviceId: serverDeviceId,
      clientDeviceId: clientDeviceId,
      baseUri: baseUri,
      buildMode: buildMode,
      mediaLane: mediaLane,
      networkLabel: networkLabel,
      recordStatus: recordStatus,
      caseIds: List.unmodifiable(caseIds),
      checkUpdates: List.unmodifiable(checkUpdates),
      measurementUpdates: List.unmodifiable(measurementUpdates),
      notes: List.unmodifiable(notes),
      artifacts: List.unmodifiable(artifacts),
    );
  }
}

class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
  @override
  String toString() => message;
}
