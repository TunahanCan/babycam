// Required invocation: flutter drive --use-existing-app=<VM service URI>
// --keep-app-running --driver=test_driver/role_isolation_device_driver.dart.
// See integration_test/role_isolation_device.md before installing/running.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 4),
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        if (data == null) {
          throw StateError('Device role test returned no report.');
        }
        final output = File(Platform.environment['MIUCAM_ROLE_DEVICE_REPORT'] ??
            'build/device_validation/role_isolation_device.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(data)}\n',
          flush: true,
        );
        stdout.writeln('Device role isolation report: ${output.path}');
      },
    );
