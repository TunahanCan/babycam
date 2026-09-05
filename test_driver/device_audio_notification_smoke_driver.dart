import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 4),
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        if (data == null) {
          throw StateError(
              'Device audio/notification test returned no report.');
        }
        final output = File(
          Platform.environment['MIUCAM_DEVICE_SMOKE_REPORT'] ??
              'build/device_validation/device_audio_notification_smoke.json',
        );
        await output.parent.create(recursive: true);
        await output.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(data)}\n',
          flush: true,
        );
        stdout.writeln('Device audio/notification report: ${output.path}');
      },
    );
