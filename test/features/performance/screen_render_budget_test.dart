import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/client_home_screen.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/media/watch_screen.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_home_screen.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/features/shared/presentation/mimicam_shells.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/client_preferences_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('client tab geçişleri kompakt ekranda overflow üretmez',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 844));
    final runtime = ClientRuntime(
      pair: (_) => throw UnimplementedError(),
    );
    addTearDown(runtime.dispose);

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
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    for (final label in ['Bul', 'Bildirim', 'Ayarlar', 'İzle']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('client filtre state alt navigasyonu yeniden oluşturmaz',
      (tester) async {
    final runtime = ClientRuntime(
      pair: (_) => throw UnimplementedError(),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigationBefore = tester.widget<MimiCamBottomNav>(
      find.byType(MimiCamBottomNav),
    );
    await tester.tap(find.text('Ses'));
    await tester.pump();
    final navigationAfter = tester.widget<MimiCamBottomNav>(
      find.byType(MimiCamBottomNav),
    );

    expect(
      identical(navigationBefore, navigationAfter),
      isTrue,
      reason: 'Notification filter state must stay inside its section.',
    );
    _expectNoFlutterException(tester);
  });

  testWidgets('paired client ve canlı izleme dar ekranda overflow üretmez',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 844));
    final runtime = await _pairedRuntime();
    addTearDown(runtime.dispose);

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
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: WatchScreen(runtime: runtime),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    for (final label in ['Geçmiş', 'Ayarlar', 'İzle']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('canlı izleme büyük yazı ve dar ekranda okunabilir kalır',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 844));
    final runtime = await _pairedRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: WatchScreen(runtime: runtime),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    runtime.reportStreamFailure(StateError('render budget failure'));
    await tester.pumpAndSettle();
    _expectNoFlutterException(tester);

    for (final label in ['Geçmiş', 'Ayarlar', 'İzle']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('server tab geçişleri kompakt ekranda overflow üretmez',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 844));
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
    _expectNoFlutterException(tester);
    expect(find.textContaining('300 TL'), findsNothing);
    expect(find.textContaining('ücretsiz yayın'), findsNothing);

    for (final label in ['QR/IP', 'Servis', 'Ayarlar', 'Yayın']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
  });

  testWidgets('server yayın ekranı uzun diller ve büyük metinde taşmaz',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final scenario in [
      (locale: const Locale('de'), scale: 1.3),
      (locale: const Locale('ar', 'SA'), scale: 1.3),
      (locale: const Locale('tr'), scale: 2.0),
    ]) {
      final preferences = await SharedPreferences.getInstance();
      final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        onStartPairing: () async => 'mimicam://pair?payload=x',
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: scenario.locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: _localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scenario.scale),
            ),
            child: child!,
          ),
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

      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -620),
      );
      await tester.pumpAndSettle();
      _expectNoFlutterException(tester);
    }
  });

  testWidgets('server QR uzun HTTP/WS payload ile kısa ekrana sığar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = await SharedPreferences.getInstance();
    final payload = _longHttpWsQrPayload();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => payload,
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

    await tester.tap(find.text('QR/IP').last);
    await tester.pumpAndSettle();

    _expectNoFlutterException(tester);
    final qrSize = tester.getSize(find.byType(QrImageView));
    expect(qrSize.width, lessThanOrEqualTo(212));
    expect(qrSize.height, lessThanOrEqualTo(212));
    final panelSize =
        tester.getSize(find.byKey(const ValueKey('server-qr-panel')));
    expect(panelSize.width, lessThanOrEqualTo(228));
    expect(panelSize.height, lessThanOrEqualTo(228));
    expect(find.text(payload), findsNothing);
  });

  testWidgets('client settings metinleri locale catalogundan gelir',
      (tester) async {
    final strings = AppStrings(const Locale('es'));
    final runtime = ClientRuntime(
      pair: (_) => throw UnimplementedError(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(strings.ui('navSettings')).last);
    await tester.pumpAndSettle();

    expect(find.text(strings.ui('languageSelectText')), findsOneWidget);
    expect(find.text(strings.ui('keepAwakeClientText')), findsOneWidget);
    _expectNoFlutterException(tester);
  });

  testWidgets('client settings kontrolleri gerçek tercihleri günceller',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final clientPreferences = ClientPreferencesService(preferences);
    Locale? selectedLocale;
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          preferences: clientPreferences,
          onLocaleChanged: (locale) => selectedLocale = locale,
        ),
      ),
    );
    await tester.tap(find.text('Ayarlar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dil'));
    await tester.pumpAndSettle();
    expect(find.text('Uygulama dili'), findsOneWidget);
    await tester.tap(find.text('English (United States)'));
    await tester.pumpAndSettle();
    expect(selectedLocale, const Locale('en', 'US'));
    expect(clientPreferences.locale, const Locale('en', 'US'));

    await tester.scrollUntilVisible(
      find.byType(Switch).last,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(clientPreferences.keepScreenAwake, isFalse);
  });

  testWidgets(
      'server runtime ve ayar güncellemeleri navigation rebuild bütçesini korur',
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
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(preferences),
          activeRole: AppRole.server,
          onRoleSelected: (_) {},
          initialTab: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigationBefore = tester.widget<MimiCamBottomNav>(
      find.byType(MimiCamBottomNav),
    );
    for (var update = 0; update < 12; update++) {
      runtime.refreshMediaProfile();
    }
    await tester.pump();
    final navigationAfterRuntimeUpdates = tester.widget<MimiCamBottomNav>(
      find.byType(MimiCamBottomNav),
    );
    expect(
      identical(navigationBefore, navigationAfterRuntimeUpdates),
      isTrue,
      reason: 'Runtime stream emissions must not rebuild bottom navigation.',
    );

    await tester.ensureVisible(find.text('İleri ayarlar'));
    await tester.tap(find.text('İleri ayarlar'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('server-settings')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    final visibleSlider = find.byType(Slider).hitTestable().first;
    expect(visibleSlider, findsOneWidget);
    await tester.drag(visibleSlider, const Offset(28, 0));
    await tester.pumpAndSettle();

    final navigationAfterSlider = tester.widget<MimiCamBottomNav>(
      find.byType(MimiCamBottomNav),
    );
    expect(
      identical(navigationBefore, navigationAfterSlider),
      isTrue,
      reason: 'Slider-local state must not rebuild bottom navigation.',
    );
    _expectNoFlutterException(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
  });
}

void _expectNoFlutterException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Future<ClientRuntime> _pairedRuntime() async {
  final session = PairingSession(payload: _payload(), sessionToken: 'token');
  final runtime = ClientRuntime(
    pair: (_) async => session,
    startStream: (_, {bool audioEnabled = false}) async => null,
    stopStream: (_) async {},
  );
  await runtime.pairWithServer(session.payload);
  return runtime;
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: 1,
      host: '192.168.1.20',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );

String _longHttpWsQrPayload() {
  final noisyPayload = List.filled(720, 'a').join();
  return 'mimicam://pair?payload=$noisyPayload';
}

const _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
