import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/server_home_screen.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
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
    expect(find.text('EBEVEYN'), findsOneWidget);
    expect(find.text('İZLEME CİHAZI'), findsOneWidget);
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

    final badgeTopRight = tester.getTopRight(find.byType(MiuCamRoleBadge));
    expect(badgeTopRight.dx, greaterThan(700));
    expect(badgeTopRight.dy, lessThan(80));

    await tester.tap(find.byType(MiuCamRoleBadge));
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

  testWidgets('erişimi iptal edilen oda bağlı gibi gösterilmez',
      (tester) async {
    final expiring = PairingSession(
      payload: PairingPayload(
        schemaVersion: 2,
        host: '192.168.1.20',
        port: 8080,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'expired-token',
      trustedClientTokenExpiresAtMs: DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    );
    final runtime = ClientRuntime(
      pair: (_) async => expiring,
      renew: (_) async => null,
    );
    addTearDown(runtime.dispose);

    await runtime.restoreSession(expiring);
    expect(runtime.currentState.phase, ClientRuntimePhase.revoked);
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

    expect(find.text('Eşleşme iptal edildi'), findsWidgets);
    expect(find.text('Bebek odasına bağlısın.'), findsNothing);
    expect(find.text('Canlı izlemeyi aç'), findsNothing);
  });

  testWidgets('Server bottom nav server alanına kilitlidir', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var pairingStarts = 0;
    var streamStops = 0;
    var restartRequests = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async {
        pairingStarts++;
        return _validPairingTicket('initial-$pairingStarts');
      },
      onStop: () async {
        streamStops++;
      },
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
          onRestartServer: () => restartRequests++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yayın'), findsOneWidget);
    expect(pairingStarts, greaterThanOrEqualTo(1));
    expect(find.text('QR/IP'), findsOneWidget);
    expect(find.text('Servis'), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(find.text('İzle'), findsNothing);
    expect(find.text('Bul'), findsNothing);
    expect(find.text('Bildirim'), findsNothing);
    expect(find.text('QR Tara'), findsNothing);

    final preview = find.byKey(const ValueKey('server-live-preview-card'));
    final status = find.byKey(const ValueKey('server-live-status-card'));
    expect(preview, findsOneWidget);
    expect(status, findsOneWidget);
    expect(
        tester.getTopLeft(status).dy, lessThan(tester.getTopLeft(preview).dy));
    final connectParent = find.text('Ebeveyn cihazını bağla');
    expect(connectParent, findsOneWidget);
    expect(
      tester.getCenter(connectParent).dy,
      lessThan(tester.getTopLeft(find.byType(MiuCamBottomNav)).dy),
    );

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Oda yayınını durdur'),
      260,
      scrollable: scrollable,
    );
    await tester.drag(scrollable, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oda yayınını durdur'));
    await tester.pumpAndSettle();

    expect(find.text('Yayın durdurulsun mu?'), findsOneWidget);
    expect(streamStops, 0);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(streamStops, 0);

    await tester.tap(find.text('Oda yayınını durdur'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Oda yayınını durdur'),
    );
    await tester.pumpAndSettle();

    expect(streamStops, 1);
    final restart = find.text('Yayını yeniden başlat');
    await tester.drag(scrollable, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Yayın durduruldu'), findsOneWidget);
    await tester.tap(restart);
    expect(restartRequests, 1);
  });

  testWidgets('Server yayın ana eylemi QR bağlantı ekranını açar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => _validPairingTicket('primary-action'),
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

    await tester.tap(find.text('Ebeveyn cihazını bağla'));
    await tester.pumpAndSettle();

    expect(find.text('QR / IP bağlantı bileti'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('Server yerel önizleme açılıp kapanır, ebeveyn yayını etkilenmez',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var mediaStarts = 0;
    var mediaStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => mediaStarts++,
        onStop: () async => mediaStops++,
      ),
      onStartPairing: () async => _validPairingTicket('preview'),
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

    expect(runtime.currentState.localPreviewActive, isFalse);
    expect(mediaStarts, 0);
    expect(find.text('Göster'), findsOneWidget);
    expect(find.byTooltip('Önizlemeyi aç'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('server-local-preview-toggle')),
          )
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(
      find.byKey(const ValueKey('server-local-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(runtime.currentState.localPreviewActive, isTrue);
    expect(mediaStarts, 1);

    await runtime.startStreamSession(
      'parent-video',
      const StreamSessionOptions(video: true, audio: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('server-local-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(runtime.currentState.localPreviewActive, isFalse);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.activeVideoClients, 1);
    expect(mediaStops, 0, reason: 'ebeveyn video yayını açık kalmalı');
    expect(find.text('Göster'), findsOneWidget);
    expect(find.byTooltip('Önizlemeyi aç'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('server-local-preview-off')), findsOneWidget);
    expect(
      find.text(
        'Bu telefondaki önizleme kapalı. Ebeveyn bağlantısı etkilenmez.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('QR/IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yayın'));
    await tester.pumpAndSettle();

    expect(runtime.currentState.localPreviewActive, isFalse);
    expect(find.text('Göster'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('server-local-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(runtime.currentState.localPreviewActive, isTrue);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(mediaStarts, 1,
        reason: 'çalışan ebeveyn kamerası yeniden açılmamalı');
    expect(find.text('Gizle'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await runtime.dispose();
  });

  testWidgets('Server eşleşmiş veya uyarıya bağlı ebeveyni bağlı gösterir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => _validPairingTicket('paired-parent'),
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

    await runtime.enableNotificationsForClient(
      'anne-uyari',
      cry: true,
      motion: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 ebeveyn bağlı. Oda bağlantısı açık.'), findsOneWidget);
    expect(find.text('Ebeveyn cihazını bağla'), findsNothing);

    await runtime.disableNotificationsForClient('anne-uyari');
    await runtime.markClientPaired();
    await tester.pumpAndSettle();

    expect(find.text('1 ebeveyn bağlı. Oda bağlantısı açık.'), findsOneWidget);
    expect(find.text('Ebeveyn cihazını bağla'), findsNothing);
  });

  testWidgets('Server teknik hatayı ana kartta kullanıcıya göstermez',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera-driver-secret'),
      ),
      onStartPairing: () async => _validPairingTicket('technical-error'),
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

    expect(
      find.text('Kamera izinlerini ve bağlantıyı kontrol edip tekrar dene.'),
      findsNothing,
    );
    expect(find.textContaining('camera-driver-secret'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('server-local-preview-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Kamera izinlerini ve bağlantıyı kontrol edip tekrar dene.'),
      findsOneWidget,
    );

    final detailsCard = find.byKey(const ValueKey('server-stream-details'));
    await tester.scrollUntilVisible(
      detailsCard,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    final details = find.descendant(
      of: detailsCard,
      matching: find.byType(ExpansionTile),
    );
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(find.textContaining('camera-driver-secret'), findsOneWidget);
  });

  testWidgets('Server QR/IP sekmesi sadece bağlantı bileti üretir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => _validPairingTicket('qr-tab'),
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

  testWidgets('Server hata kartındaki tekrar dene tüm serverı yeniden başlatır',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var restartRequests = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera unavailable'),
      ),
      onStartPairing: () async => _validPairingTicket('retry'),
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
          onRestartServer: () => restartRequests++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('server-local-preview-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Yayın başlatılamadı'), findsOneWidget);

    await tester.tap(find.text('Tekrar dene'));
    await tester.pump();

    expect(restartRequests, 1);
  });

  testWidgets('Server başarısız eşleşmede sahte QR göstermez', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => throw StateError('network unavailable'),
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

    expect(find.byType(QrImageView), findsNothing);
    expect(
      find.byKey(const ValueKey('server-qr-placeholder')),
      findsOneWidget,
    );
    expect(
      find.text('QR şu anda hazırlanamadı. Aşağıdan yeniden deneyin.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Adresi kopyala'),
          )
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('QR yenile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR yenile'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'QR yenilenemedi. Wi-Fi bağlantısını kontrol edip tekrar deneyin.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Server QR yenileme ve kopyalama eylemleri sonuç üretir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var pairingStarts = 0;
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async {
        pairingStarts++;
        return PairingPayload(
          schemaVersion: 1,
          host: '192.168.1.20',
          port: 8080,
          deviceId: 'server',
          deviceName: 'Bebek Odası',
          pairingNonce: 'nonce-$pairingStarts',
          expiresAtMs: DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          capabilities: const {},
        ).toUriString();
      },
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

    final beforeRefresh = pairingStarts;
    await tester.ensureVisible(find.text('QR yenile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR yenile'));
    await tester.pumpAndSettle();
    expect(pairingStarts, beforeRefresh + 1);
    expect(find.text('QR bağlantı bileti yenilendi.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Adresi kopyala'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adresi kopyala'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.20:8080'), findsOneWidget);
    expect(clipboardText, '192.168.1.20:8080');
    expect(find.text('Bağlantı adresi kopyalandı.'), findsOneWidget);
  });
}

String _validPairingTicket(String nonce) => PairingPayload(
      schemaVersion: 1,
      host: '192.168.1.20',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: nonce,
      expiresAtMs: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      capabilities: const {},
    ).toUriString();

const _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
