import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/role_selection/role_selection_screen.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/presentation/server_home_components.dart';
import 'package:miucam/features/server/server_home_screen.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    for (final scenario in [
      (name: 'compact large text', size: const Size(320, 568), scale: 2.0),
      (name: 'landscape', size: const Size(640, 360), scale: 1.3),
    ]) {
      testWidgets(
          'role and server screens ${locale.toLanguageTag()} '
          '${scenario.name}', (tester) async {
        await tester.binding.setSurfaceSize(scenario.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final config =
            ConfigurationService(await SharedPreferences.getInstance());
        final payload = PairingPayload(
          schemaVersion: 2,
          host: '192.168.1.20',
          port: 8080,
          deviceId: 'review-room',
          deviceName: 'Room',
          pairingNonce: 'review-nonce',
          expiresAtMs: DateTime.now()
              .add(const Duration(minutes: 10))
              .millisecondsSinceEpoch,
          capabilities: const {},
        );
        final runtime = ServerRuntime(
          mediaRuntime: MediaRuntimeController(),
          onStartPairing: () async => payload.toUriString(),
        );

        Widget app(Widget screen) => MaterialApp(
              locale: locale,
              theme: MiuCamTheme.serverTheme(),
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: child!,
              ),
              home: screen,
            );
        try {
          AppRole? selected;
          await tester.pumpWidget(app(RoleSelectionScreen(
            onRoleSelected: (role) => selected = role,
          )));
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
          expect(tester.takeException(), isNull);
          final parentChoice =
              find.byKey(const ValueKey('role-choice-card-client'));
          await tester.scrollUntilVisible(parentChoice, 250);
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
          await tester.tap(parentChoice);
          expect(selected, AppRole.client);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(app(ServerHomeScreen(
            runtime: runtime,
            config: config,
            activeRole: AppRole.server,
            onRoleSelected: (_) {},
          )));
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
          expect(tester.takeException(), isNull);
          final strings = AppStrings(locale);
          for (final destination in ServerHomeDestination.values) {
            await tester.tap(find.descendant(
              of: find.byType(MiuCamBottomNav),
              matching: find.text(strings.ui(destination.labelKey)),
            ));
            await tester.pumpAndSettle(const Duration(milliseconds: 100),
                EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
            expect(find.byKey(ValueKey(destination.viewKey)), findsOneWidget);
            expect(tester.takeException(), isNull);
            // Exercise content below the fold, including the settings controls.
            final scrollable = find
                .descendant(
                  of: find.byKey(ValueKey(destination.viewKey)),
                  matching: find.byType(Scrollable),
                )
                .first;
            final position = tester.state<ScrollableState>(scrollable).position;
            if (destination == ServerHomeDestination.stream) {
              final toggle =
                  find.byKey(const ValueKey('server-local-preview-toggle'));
              await tester.scrollUntilVisible(toggle, 250,
                  scrollable: scrollable);
              await tester.pumpAndSettle(const Duration(milliseconds: 100),
                  EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
              await tester.tap(toggle);
              await tester.pumpAndSettle(const Duration(milliseconds: 100),
                  EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
              expect(runtime.currentState.localPreviewActive, isTrue);
              expect(tester.takeException(), isNull);
              await tester.tap(toggle);
              await tester.pumpAndSettle(const Duration(milliseconds: 100),
                  EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
              expect(runtime.currentState.localPreviewActive, isFalse);
              expect(tester.takeException(), isNull);
            }
            for (var step = 0;
                step < 30 && position.pixels < position.maxScrollExtent - 1;
                step++) {
              await tester.drag(
                  scrollable, Offset(0, -scenario.size.height * .7));
              await tester.pumpAndSettle(const Duration(milliseconds: 100),
                  EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
              expect(tester.takeException(), isNull);
            }
            expect(position.pixels, closeTo(position.maxScrollExtent, 1));
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
          await runtime.dispose();
        }
      });
    }
  }
}
