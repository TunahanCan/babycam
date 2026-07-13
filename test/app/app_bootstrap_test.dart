import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_bootstrap.dart';
import 'package:mimicam/app/install_integrity_guard.dart';
import 'package:mimicam/l10n/app_strings.dart';
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
    expect(find.text('MimiCam’i nasıl kullanacaksınız?'), findsOneWidget);
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

    expect(find.text('MimiCam başlatılamadı'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(reportedError?.exception, isA<StateError>());

    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('MimiCam’i nasıl kullanacaksınız?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
