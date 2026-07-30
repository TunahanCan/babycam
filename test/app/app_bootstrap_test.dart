import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_bootstrap.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/app/install_integrity_guard.dart';
import 'package:miucam/app/role_repository.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'fresh install shows welcome before secure preparation and gates actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final preparation = Completer<void>();
    var preparationCalls = 0;

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
        home: AppBootstrap(
          preferencesLoader: () async => preferences,
          secureStorageClearer: () {
            preparationCalls++;
            return preparation.future;
          },
        ),
      ),
    );
    await tester.pump();

    expect(preparationCalls, 1);
    expect(find.text('MiuCam’i nasıl kullanacaksınız?'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('app-bootstrap-install-preparation-progress'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(
              const ValueKey('app-bootstrap-install-preparation-gate'),
            ),
          )
          .absorbing,
      isTrue,
    );

    preparation.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('app-bootstrap-install-preparation-progress'),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(
              const ValueKey('app-bootstrap-install-preparation-gate'),
            ),
          )
          .absorbing,
      isFalse,
    );
    expect(
      preferences.getBool(InstallIntegrityGuard.markerKey),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap hatayı gösterir ve yeniden denenebilir',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      InstallIntegrityGuard.markerKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final originalErrorHandler = FlutterError.onError;
    FlutterErrorDetails? reportedError;
    FlutterError.onError = (details) => reportedError = details;
    addTearDown(() => FlutterError.onError = originalErrorHandler);
    var attempts = 0;

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
        home: AppBootstrap(
          preferencesLoader: () async {
            attempts++;
            if (attempts == 1) throw StateError('storage unavailable');
            return preferences;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MiuCam başlatılamadı'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(reportedError?.exception, isA<StateError>());

    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('MiuCam’i nasıl kullanacaksınız?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'server confirmation keeps its CTA reachable in short large-text layout',
      (tester) async {
    _setTestView(tester, const Size(667, 320));
    SharedPreferences.setMockInitialValues({
      InstallIntegrityGuard.markerKey: true,
      SharedPreferencesRoleRepository.storageKey: AppRole.server.name,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _responsiveTestApp(
        locale: const Locale('de'),
        home: AppBootstrap(
          preferencesLoader: () async => preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiuCamRoleBadge));
    await tester.pumpAndSettle();

    expect(find.text('Server-Modus verlassen?'), findsOneWidget);
    expect(find.text('Abbrechen'), findsOneWidget);
    final confirmCta = find.text('Zu Client wechseln');
    expect(confirmCta, findsOneWidget);
    expect(tester.takeException(), isNull);

    final sheetScrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    expect(sheetScrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      confirmCta,
      120,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    expect(confirmCta.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Abbrechen'),
        )
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    expect(find.text('Server-Modus verlassen?'), findsNothing);
    expect(find.byType(MiuCamRoleBadge), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('bootstrap error is scrollable at 320 square and 2x text',
      (tester) async {
    _setTestView(tester, const Size.square(320));
    final originalErrorHandler = FlutterError.onError;
    FlutterErrorDetails? reportedBootstrapError;
    FlutterError.onError = (details) {
      if (details.exception is StateError) {
        reportedBootstrapError = details;
      } else {
        originalErrorHandler?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalErrorHandler);

    await tester.pumpWidget(
      _responsiveTestApp(
        locale: const Locale('de'),
        home: AppBootstrap(
          preferencesLoader: () async {
            throw StateError('storage unavailable');
          },
        ),
      ),
    );
    await tester.pump();

    expect(reportedBootstrapError?.exception, isA<StateError>());
    expect(
      find.text('MiuCam konnte nicht gestartet werden'),
      findsOneWidget,
    );
    final retryCta = find.text('Erneut versuchen');
    expect(retryCta, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      retryCta,
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(retryCta.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap progress does not overflow at 320 square and 2x text',
      (tester) async {
    _setTestView(tester, const Size.square(320));
    final preferencesLoad = Completer<SharedPreferences>();

    await tester.pumpWidget(
      _responsiveTestApp(
        locale: const Locale('de'),
        home: AppBootstrap(
          preferencesLoader: () => preferencesLoad.future,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MiuCam wird vorbereitet...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _responsiveTestApp({
  required Locale locale,
  required Widget home,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2),
      ),
      child: child!,
    ),
    home: home,
  );
}

void _setTestView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
