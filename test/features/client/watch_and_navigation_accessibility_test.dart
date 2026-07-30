import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets(
    'watch gece saati landscape ve büyük metinde taşma üretmez',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final runtime = await _pairedRuntime();
      addTearDown(runtime.dispose);
      final strings = AppStrings(const Locale('tr'));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: _localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: WatchScreen(
            runtime: runtime,
            keepScreenAwake: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final nightClockAction = find.text(strings.ui('nightClock'));
      await tester.scrollUntilVisible(
        nightClockAction,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(nightClockAction);
      await tester.pumpAndSettle();

      expect(
        find.byTooltip(strings.ui('exitNightClock')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'watch navigation exposes selected buttons with 48dp tap targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final runtime = await _pairedRuntime();
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: _localizationsDelegates,
          home: WatchScreen(
            runtime: runtime,
            keepScreenAwake: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final watchNode = tester.getSemantics(find.bySemanticsLabel('İzle'));
      final historyNode = tester.getSemantics(find.bySemanticsLabel('Geçmiş'));
      final settingsNode =
          tester.getSemantics(find.bySemanticsLabel('Ayarlar'));

      for (final node in [watchNode, historyNode, settingsNode]) {
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(data.rect.height, greaterThanOrEqualTo(48));
      }
      expect(
        watchNode.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        historyNode.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );

      historyNode.owner!.performAction(
        historyNode.id,
        ui.SemanticsAction.tap,
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('İzle'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Geçmiş'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('watch back icon mirrors in RTL', (tester) async {
    final runtime = await _pairedRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: WatchScreen(
          runtime: runtime,
          keepScreenAwake: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backIcon = find.byType(BackButtonIcon);
    expect(backIcon, findsOneWidget);
    final renderedIcon = tester.widget<Icon>(
      find.descendant(of: backIcon, matching: find.byType(Icon)),
    );
    expect(renderedIcon.icon?.matchTextDirection, isTrue);

    final rtlTransform = tester.widget<Transform>(
      find.descendant(of: backIcon, matching: find.byType(Transform)),
    );
    expect(rtlTransform.transform.entry(0, 0), -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role badge keeps a 48dp minimum tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: MiuCamRoleBadge(
              activeRole: AppRole.client,
              onRoleSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = find.byType(MiuCamRoleBadge);
    expect(tester.getSize(badge).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSize(
            find.descendant(of: badge, matching: find.byType(InkWell)),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'alt navigasyon seçili durumu ve tap aksiyonunu semantiğe taşır',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var currentIndex = 1;
      int? tappedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: StatefulBuilder(
              builder: (context, setState) => MiuCamBottomNav(
                items: const [
                  MiuCamBottomNavItem(
                    icon: Icons.videocam_rounded,
                    label: 'İzle',
                  ),
                  MiuCamBottomNavItem(
                    icon: Icons.history_rounded,
                    label: 'Geçmiş',
                  ),
                  MiuCamBottomNavItem(
                    icon: Icons.settings_rounded,
                    label: 'Ayarlar',
                  ),
                ],
                currentIndex: currentIndex,
                activeColor: const Color(0xFF276A59),
                onTap: (index) {
                  tappedIndex = index;
                  setState(() => currentIndex = index);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      var selectedData = tester
          .getSemantics(find.bySemanticsLabel('Geçmiş'))
          .getSemanticsData();
      var targetNode = tester.getSemantics(
        find.bySemanticsLabel('Ayarlar'),
      );
      var targetData = targetNode.getSemanticsData();

      expect(selectedData.flagsCollection.isButton, isTrue);
      expect(
        selectedData.flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      expect(selectedData.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(targetData.flagsCollection.isButton, isTrue);
      expect(
        targetData.flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      expect(targetData.hasAction(ui.SemanticsAction.tap), isTrue);

      targetNode.owner!.performAction(
        targetNode.id,
        ui.SemanticsAction.tap,
      );
      await tester.pumpAndSettle();

      expect(tappedIndex, 2);
      selectedData = tester
          .getSemantics(find.bySemanticsLabel('Geçmiş'))
          .getSemanticsData();
      targetNode = tester.getSemantics(find.bySemanticsLabel('Ayarlar'));
      targetData = targetNode.getSemanticsData();
      expect(
        selectedData.flagsCollection.isSelected,
        ui.Tristate.isFalse,
      );
      expect(
        targetData.flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      semantics.dispose();
    },
  );
}

Future<ClientRuntime> _pairedRuntime() async {
  final session = PairingSession(
    payload: _payload(),
    sessionToken: 'token',
  );
  final runtime = ClientRuntime(
    pair: (_) async => session,
    startStream: (_, {bool audioEnabled = false}) async => null,
    stopStream: (_) async {},
  );
  await runtime.pairWithServer(session.payload);
  return runtime;
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: '192.168.1.20',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );

const _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
