import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/features/client/client_home_screen.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_home_screen.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/features/shared/presentation/mimicam_shells.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Client rol rozeti ve client bottom nav gösterilir',
      (tester) async {
    AppRole? selectedRole;
    final runtime = ClientRuntime(
      pair: (payload) => throw UnimplementedError(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (role) => selectedRole = role,
        ),
      ),
    );

    expect(find.text('CLIENT'), findsNothing);
    expect(find.text('EBEVEYN'), findsNWidgets(2));
    expect(find.text('ANNE İÇİN ÖNCELİK'), findsOneWidget);
    expect(find.text('Bildirim'), findsOneWidget);
    expect(find.text('SUNUCU'), findsNothing);
    expect(find.text('BEBEK ODASI'), findsNothing);
    expect(find.text('İzle'), findsOneWidget);
    expect(find.text('Bul'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(find.text('Yayın'), findsNothing);
    expect(find.text('QR/IP'), findsNothing);
    expect(find.text('Servis'), findsNothing);
    expect(find.textContaining('yayınını durdur'), findsNothing);
    expect(find.text('QR üret'), findsNothing);

    final badgeTopRight = tester.getTopRight(find.byType(MimiCamRoleBadge));
    expect(badgeTopRight.dx, greaterThan(700));
    expect(badgeTopRight.dy, lessThan(80));

    await tester.tap(find.byType(MimiCamRoleBadge));
    expect(selectedRole, AppRole.server);
  });

  testWidgets('Client Bul sekmesi QR ve manual IP fallback gösterir',
      (tester) async {
    final runtime = ClientRuntime(
      pair: (payload) => throw UnimplementedError(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Bul'));
    await tester.pumpAndSettle();

    expect(find.text('QR Tara'), findsOneWidget);
    expect(find.text('IP ile bağlan'), findsOneWidget);
    expect(find.text('QR üret'), findsNothing);
    expect(find.textContaining('yayınını durdur'), findsNothing);
  });

  testWidgets('Server bottom nav server alanına kilitlidir', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => 'mimicam://pair?payload=x',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(preferences),
          activeRole: AppRole.server,
          onRoleSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yayın'), findsOneWidget);
    expect(find.text('QR/IP'), findsOneWidget);
    expect(find.text('Servis'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(find.text('İzle'), findsNothing);
    expect(find.text('Bul'), findsNothing);
    expect(find.text('Bildirim'), findsNothing);
    expect(find.textContaining('yayınını durdur'), findsOneWidget);
    expect(find.text('QR Tara'), findsNothing);
  });

  testWidgets('Server QR/IP sekmesi sadece bağlantı bileti üretir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => 'mimicam://pair?payload=x',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(preferences),
          activeRole: AppRole.server,
          onRoleSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('QR/IP'));
    await tester.pumpAndSettle();

    expect(find.text('QR / IP bağlantı bileti'), findsOneWidget);
    expect(find.text('QR yenile'), findsOneWidget);
    expect(find.text('Adresi kopyala'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final qrSize = tester.getSize(find.byType(QrImageView));
    expect(qrSize.width, greaterThanOrEqualTo(220));
    expect(qrSize.height, greaterThanOrEqualTo(220));
    expect(find.text('QR Tara'), findsNothing);
  });
}

const _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
