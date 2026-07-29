import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/pairing/trusted_client_repository.dart';
import 'package:miucam/features/server/presentation/server_settings_section.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'algılama profilleri ses ve bildirim politikasını birlikte kaydeder',
      (tester) async {
    final config = ConfigurationService(await SharedPreferences.getInstance());
    var analysisReloads = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onSettingsChanged: () async => analysisReloads++,
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerSettingsSection(config: config, runtime: runtime),
          ),
        ),
      ),
    );
    await tester.pump();

    await _selectPreset(tester, 'Hassas');
    _expectSettings(
      config,
      motionThreshold: .15,
      cryThreshold: .50,
      cooldownMs: 45000,
      motionDurationMs: 1000,
      cryDurationMs: 1500,
    );

    await _selectPreset(tester, 'Dengeli');
    _expectSettings(
      config,
      motionThreshold: .22,
      cryThreshold: .65,
      cooldownMs: 60000,
      motionDurationMs: 2000,
      cryDurationMs: 1500,
    );

    await _selectPreset(tester, 'Daha az uyarı');
    _expectSettings(
      config,
      motionThreshold: .35,
      cryThreshold: .78,
      cooldownMs: 90000,
      motionDurationMs: 3500,
      cryDurationMs: 2500,
    );
    expect(analysisReloads, 3);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await runtime.dispose();
  });

  testWidgets('oda cihazı güvenilen ebeveyn erişimini kaldırabilir',
      (tester) async {
    final config = ConfigurationService(await SharedPreferences.getInstance());
    var clients = [
      TrustedClientRecord(
        clientId: 'parent-1',
        clientName: 'Anne telefonu',
        tokenHash: 'a' * 64,
        createdAtMs: 1,
        lastSeenAtMs: 2,
        expiresAtMs:
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      ),
    ];
    String? revokedClientId;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      trustedClients: () => clients,
      onRevokeTrustedClient: (clientId) async {
        revokedClientId = clientId;
        clients = clients
            .where((client) => client.clientId != clientId)
            .toList(growable: false);
      },
      onRevokeAllTrustedClients: () async => clients = [],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerSettingsSection(config: config, runtime: runtime),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Güvenilen ebeveyn cihazları'));
    await tester.pumpAndSettle();
    expect(find.text('Anne telefonu'), findsOneWidget);

    await tester.tap(find.byTooltip('Erişimi kaldır'));
    await tester.pumpAndSettle();
    expect(find.text('Cihaz erişimi kaldırılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Erişimi kaldır'));
    await tester.pumpAndSettle();

    expect(revokedClientId, 'parent-1');
    expect(
        find.text('Henüz güvenilen bir ebeveyn cihazı yok.'), findsOneWidget);
    expect(find.text('Cihaz erişimi kaldırıldı.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await runtime.dispose();
  });
}

Future<void> _selectPreset(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectSettings(
  ConfigurationService config, {
  required double motionThreshold,
  required double cryThreshold,
  required int cooldownMs,
  required int motionDurationMs,
  required int cryDurationMs,
}) {
  expect(config.motionThreshold, motionThreshold);
  expect(config.cryScoreThreshold, cryThreshold);
  expect(config.notifyCooldownMs, cooldownMs);
  expect(config.motionMinDurationMs, motionDurationMs);
  expect(config.cryMinDurationMs, cryDurationMs);
}
