import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    for (final scenario in [
      (name: 'compact large text', size: const Size(320, 568), scale: 2.0),
      (name: 'landscape', size: const Size(640, 360), scale: 1.3),
    ]) {
      testWidgets('client screens ${locale.toLanguageTag()} ${scenario.name}',
          (tester) async {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.binding.setSurfaceSize(scenario.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var failStart = true;
        var starts = 0;
        final runtime = ClientRuntime(
          pair: (payload) async =>
              PairingSession(payload: payload, sessionToken: 'token'),
          startStream: (_, {bool audioEnabled = false}) async {
            starts++;
            if (failStart) throw StateError('Disconnected room');
            // Returning no media handle keeps the fixture free of network and
            // native media while exercising actual runtime error recovery.
            return null;
          },
          stopStream: (_) async {},
          roomControls: _RoomControls(),
        );
        Widget app(Widget screen) => MaterialApp(
              locale: locale,
              theme: MiuCamTheme.clientTheme(),
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
          await tester.pumpWidget(app(ClientHomeScreen(
            runtime: runtime,
            activeRole: AppRole.client,
            onRoleSelected: (_) {},
          )));
          await _settle(tester);
          final strings = AppStrings(locale);
          for (final tab in [
            (label: 'navWatch', key: 'client-watch'),
            (label: 'navFind', key: 'client-find'),
            (label: 'navNotifications', key: 'client-history'),
            (label: 'navSettings', key: 'client-settings'),
          ]) {
            await tester.tap(find.descendant(
              of: find.byType(MiuCamBottomNav),
              matching: find.text(strings.ui(tab.label)),
            ));
            await _settle(tester);
            expect(find.byKey(ValueKey(tab.key)), findsOneWidget);
            await _scrollToBottom(tester, scenario.size.height);
          }

          await runtime.pairWithServer(_payload);
          for (final event in ['cryDetected', 'motionDetected', 'batteryLow']) {
            await runtime.recordAlert(AlertEventDto(
              id: event,
              type: event,
              severity: 'warning',
              messageKey: event,
              message: event,
              score: .8,
              timestampMs: 1770000000000,
              sourceDeviceId: 'room',
            ));
          }
          await tester.pumpWidget(app(WatchScreen(
            runtime: runtime,
            keepScreenAwake: false,
          )));
          await _settle(tester);
          expect(runtime.currentState.error, isA<StateError>());

          for (final recovering in [false, true]) {
            if (recovering) {
              await _selectWatchTab(tester, strings, 'navWatch');
              final retry = find.byKey(const ValueKey('watch-stream-retry'));
              await tester.scrollUntilVisible(retry, -250,
                  scrollable: find.byType(Scrollable).first);
              await Scrollable.ensureVisible(tester.element(retry),
                  alignment: .5);
              await _settle(tester);
              failStart = false;
              await tester.tap(retry);
              await _settle(tester);
              expect(starts, 2);
              expect(runtime.currentState.error, isNull);
            }
            for (final label in ['navWatch', 'navHistory', 'navSettings']) {
              await _selectWatchTab(tester, strings, label);
              await _scrollToBottom(tester, scenario.size.height);
            }
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settle(tester);
          await runtime.dispose();
        }
      });
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
  expect(tester.takeException(), isNull);
}

Future<void> _selectWatchTab(
    WidgetTester tester, AppStrings strings, String label) async {
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  await tester.tap(find.descendant(
    of: find.byWidget(scaffold.bottomNavigationBar!),
    matching: find.text(strings.ui(label)),
  ));
  await _settle(tester);
}

Future<void> _scrollToBottom(WidgetTester tester, double height) async {
  final scrollable = find.byType(Scrollable).first;
  final position = tester.state<ScrollableState>(scrollable).position;
  for (var step = 0;
      step < 50 && position.pixels < position.maxScrollExtent - 1;
      step++) {
    await tester.drag(scrollable, Offset(0, -height * .65));
    await _settle(tester);
  }
  expect(position.pixels, closeTo(position.maxScrollExtent, 1));
}

const _payload = PairingPayload(
  schemaVersion: 2,
  host: '127.0.0.1',
  port: 8080,
  deviceId: 'room',
  deviceName: 'Room',
  pairingNonce: 'nonce',
  expiresAtMs: 9999999999999,
  capabilities: {},
);

class _RoomControls extends ClientRoomControls {
  @override
  ClientRoomControlSnapshot get currentState =>
      const ClientRoomControlSnapshot(audioDetectionPaused: true);

  @override
  Stream<ClientRoomControlSnapshot> get states => const Stream.empty();

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      null;

  @override
  Future<void> stopTalking() async {}

  @override
  Future<void> dispose() async {}
}
