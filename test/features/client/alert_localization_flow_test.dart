import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/shared/presentation/localized_time.dart';
import 'package:miucam/features/shared/presentation/localized_room_name.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  test('legacy default room names localize and custom room names survive', () {
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings(locale);
      for (final name in [
        'Bebek Odası',
        'MiuCam Bebek Odası',
        'Manual IP Server',
        ''
      ]) {
        expect(localizedRoomName(strings, name), strings.ui('babyRoomName'));
      }
      expect(localizedRoomName(strings, 'Ada / غرفة ليلى'), 'Ada / غرفة ليلى');
      expect(localizedRoomName(strings, 'Ada Bebek Odası'), 'Ada Bebek Odası');
    }
  });

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('stored alerts follow parent locale $locale on both screens',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
      addTearDown(runtime.dispose);
      final timestamp = DateTime(2026, 1, 2, 13, 5).millisecondsSinceEpoch;
      final alert = AlertEventDto.fromJson(AlertEventDto(
        id: 'stored-foreign-alert',
        type: 'motionDetected',
        severity: 'warning',
        messageKey: 'parentMotionAlert',
        message: 'SERVER_LANGUAGE_MUST_NOT_LEAK',
        score: .7,
        timestampMs: timestamp,
        sourceDeviceId: 'server',
        // Old records lack measurements. The parent must still see a usable
        // translated event, without made-up percentages.
      ).toJson())!;
      await runtime.recordAlert(alert);
      final strings = AppStrings(locale);

      await tester.pumpWidget(_app(
        locale,
        ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          initialTab: 2,
        ),
      ));
      await tester.pump();
      expect(find.text(alert.localizedTitle(strings)), findsOneWidget);
      expect(find.text(alert.localizedMessage(strings)), findsOneWidget);
      expect(
          find.textContaining('SERVER_LANGUAGE_MUST_NOT_LEAK'), findsNothing);
      final context = tester.element(find.byType(ClientHomeScreen));
      expect(
          find.text(formatAlertTimestamp(context, timestamp)), findsOneWidget);
      expect(Directionality.of(context),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_app(
        locale,
        WatchScreen(runtime: runtime, initialTab: 1, keepScreenAwake: false),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(alert.localizedTitle(strings)), findsWidgets);
      expect(
          find.textContaining('SERVER_LANGUAGE_MUST_NOT_LEAK'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('clock uses English 12h default and explicit 24h preference',
      (tester) async {
    final time = DateTime(2026, 9, 5, 13, 5);
    for (final force24Hour in [false, true]) {
      await tester.pumpWidget(_app(
        const Locale('en', 'US'),
        Builder(builder: (context) => Text(formatLocalTime(context, time))),
        force24Hour: force24Hour,
      ));
      expect(find.text(force24Hour ? '13:05' : '1:05 PM'), findsOneWidget);
    }
  });

  testWidgets('Turkish clock and historical date use local conventions',
      (tester) async {
    final now = DateTime(2026, 9, 5, 14);
    await tester.pumpWidget(_app(
      const Locale('tr'),
      Builder(
          builder: (context) => Column(children: [
                Text(formatAlertTimestamp(
                    context, DateTime(2026, 9, 5, 13, 5).millisecondsSinceEpoch,
                    now: now)),
                Text(formatAlertTimestamp(
                    context, DateTime(2026, 9, 4, 13, 5).millisecondsSinceEpoch,
                    now: now)),
              ])),
    ));
    expect(find.text('13:05'), findsOneWidget);
    expect(find.text('04.09.2026 · 13:05'), findsOneWidget);
  });
}

Widget _app(Locale locale, Widget home, {bool force24Hour = false}) =>
    MaterialApp(
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
          textScaler: const TextScaler.linear(1.5),
          alwaysUse24HourFormat: force24Hour,
        ),
        child: child!,
      ),
      home: home,
    );
