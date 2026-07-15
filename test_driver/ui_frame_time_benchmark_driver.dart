import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) {
          throw StateError('Device benchmark returned no response data.');
        }
        final output = File('build/performance/ui_frame_time_p95.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(data)}\n',
          flush: true,
        );
        stdout.writeln('Frame-time report: ${output.path}');
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
      },
    );
