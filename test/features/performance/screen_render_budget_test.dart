import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/features/client/client_home_screen.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_home_screen.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/features/shared/presentation/mimicam_shells.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('client tab geçişleri kompakt ekranda overflow üretmez',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final runtime = ClientRuntime(
      pair: (_) => throw UnimplementedError(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    for (final label in ['Bul', 'Bildirim', 'Ayarlar', 'İzle']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('server tab geçişleri kompakt ekranda overflow üretmez',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => 'mimicam://pair?payload=x',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(preferences),
          activeRole: AppRole.server,
          onRoleSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    for (final label in ['QR/IP', 'Servis', 'Ayarlar', 'Yayın']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('pahalı ortak yüzeyler repaint boundary ile izole edilir',
      (tester) async {
    final runtime = ClientRuntime(
      pair: (_) => throw UnimplementedError(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      ),
    );

    expect(find.byType(MimiCamBottomNav), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(3));
  });
}

void _expectNoFlutterException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}
