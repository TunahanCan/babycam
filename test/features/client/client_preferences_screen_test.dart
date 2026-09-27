import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/client_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/runtime_widget_cleanup.dart';

void main() {
  for (final changeLocale in [false, true]) {
    testWidgets(
        'failed ${changeLocale ? 'language' : 'wakelock'} save preserves settings',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences =
          _FailingPreferences(await SharedPreferences.getInstance());
      final runtime = ClientRuntime(
        pair: (payload) async =>
            PairingSession(payload: payload, sessionToken: 'token'),
      );
      try {
        var localeChanges = 0;
        final strings = AppStrings(const Locale('tr'));
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ClientHomeScreen(
            runtime: runtime,
            activeRole: AppRole.client,
            onRoleSelected: (_) {},
            initialTab: 3,
            preferences: preferences,
            onLocaleChanged: (_) => localeChanges++,
          ),
        ));
        await tester.pumpAndSettle();
        if (changeLocale) {
          await tester.tap(find.text(strings.ui('language')));
          await tester.pumpAndSettle();
          final locale = find.text('Türkçe');
          await Scrollable.ensureVisible(tester.element(locale), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(locale);
        } else {
          await Scrollable.ensureVisible(tester.element(find.byType(Switch)),
              alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Switch));
        }
        await tester.pumpAndSettle();
        expect(find.text(strings.ui('settingsSaveFailed')), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
        expect(find.text(strings.ui('systemLanguageShort')), findsOneWidget);
        expect(localeChanges, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await disposeClientRuntime(tester, runtime);
      }
    });
  }
}

class _FailingPreferences extends ClientPreferencesService {
  _FailingPreferences(super.preferences);

  @override
  Future<void> setLocale(Locale? locale) async => throw StateError('Disk full');

  @override
  Future<void> setKeepScreenAwake(bool enabled) async =>
      throw StateError('Disk full');
}
