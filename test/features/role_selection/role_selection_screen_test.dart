import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/features/role_selection/role_selection_screen.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  Future<void> pumpRoleSelection(
    WidgetTester tester, {
    required ValueChanged<AppRole> onRoleSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: RoleSelectionScreen(onRoleSelected: onRoleSelected),
      ),
    );
  }

  testWidgets('son kullanıcıya uygun iki kurulum seçeneği gösterir',
      (tester) async {
    final semantics = tester.ensureSemantics();
    AppRole? selected;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpRoleSelection(
      tester,
      onRoleSelected: (role) => selected = role,
    );

    expect(find.text('MiuCam’i nasıl kullanacaksınız?'), findsOneWidget);
    expect(find.text('Bebek odasına kur'), findsOneWidget);
    expect(find.text('Yanımda kullan'), findsOneWidget);
    expect(find.text('BEBEK ODASI'), findsOneWidget);
    expect(find.text('İZLEME CİHAZI'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
    expect(find.byIcon(Icons.smartphone_rounded), findsWidgets);
    expect(find.byIcon(Icons.nightlight_round_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.child_care), findsNothing);
    expect(find.byIcon(Icons.monitor_heart), findsNothing);
    expect(
      find.byKey(const ValueKey('role-choice-illustration-server')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('role-choice-illustration-client')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('role-choice-illustration-server')),
        matching: find.byIcon(Icons.videocam_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('role-choice-illustration-server')),
        matching: find.byIcon(Icons.nightlight_round_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('role-choice-illustration-client')),
        matching: find.byIcon(Icons.smartphone_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('role-choice-illustration-client')),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.wifi_rounded), findsWidgets);

    final roomSemantics = tester
        .getSemantics(
          find.byKey(const ValueKey('role-choice-card-server')),
        )
        .getSemanticsData();
    expect(
      roomSemantics.label,
      'Bebek odasına kur. Bu telefon bebeğinizi görüntüler, sesi dinler '
      've uyarı gönderir.',
    );
    expect(roomSemantics.flagsCollection.isButton, isTrue);
    expect(roomSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
    semantics.dispose();

    final wordmark = tester.widget<Image>(
      find.byKey(const ValueKey('role-wordmark')),
    );
    expect(
      (wordmark.image as AssetImage).assetName,
      'assets/branding/miucam_wordmark_v3.png',
    );

    for (final asset in [
      'assets/branding/miucam_wordmark.png',
      'assets/branding/miucam_bear_mascot.png',
      'assets/branding/miucam_wordmark_v2.png',
      'assets/branding/miucam_wordmark_v3.png',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0));
    }

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Yanımda kullan'));
    expect(selected, AppRole.client);

    await tester.scrollUntilVisible(
      find.text('İnternet gerekmez'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('İnternet gerekmez'), findsOneWidget);
  });

  testWidgets('küçük ekranda tüm seçeneklere kaydırarak erişilir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpRoleSelection(tester, onRoleSelected: (_) {});
    await tester.scrollUntilVisible(
      find.text('İnternet gerekmez'),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('İnternet gerekmez'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('geniş ekranda kurulum seçeneklerini yan yana gösterir',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpRoleSelection(tester, onRoleSelected: (_) {});

    final roomTop = tester.getTopLeft(find.text('Bebek odasına kur')).dy;
    final parentTop = tester.getTopLeft(find.text('Yanımda kullan')).dy;
    expect(roomTop, parentTop);
    expect(tester.takeException(), isNull);
  });
}
