import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/client/pairing/pairing_failure.dart';
import 'package:miucam/features/client/pairing/pairing_code_dialog.dart';
import 'package:miucam/features/client/pairing/pairing_payload_gateway.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/client_preferences_service.dart';
import 'package:miucam/services/discovery/miucam_service_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/runtime_widget_cleanup.dart';

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  for (final alertsEnabled in [false, true]) {
    testWidgets('resuming preserves alerts enabled=$alertsEnabled',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var starts = 0;
      var permissionChecks = 0;
      final runtime = ClientRuntime(
        pair: (payload) async =>
            PairingSession(payload: payload, sessionToken: 'token'),
        startAlerts: (_) async {
          starts++;
          return true;
        },
        initializeSystemNotifications: () async {
          permissionChecks++;
          return permissionChecks > 1;
        },
      );
      try {
        await runtime.restoreSession(
            PairingSession(payload: _payload(), sessionToken: 'token'));
        await runtime.startAlertListening();
        if (!alertsEnabled) await runtime.stopAlertListening();
        await tester.pumpWidget(_app(runtime));
        await tester.pumpAndSettle();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        expect(runtime.currentState.alertsActive, alertsEnabled);
        expect(starts, 1,
            reason: 'Returning to the app must not re-enable alerts that the '
                'parent explicitly turned off.');
        expect(permissionChecks, alertsEnabled ? 2 : 1);
        if (alertsEnabled) {
          expect(runtime.systemNotificationsEnabled, isTrue,
              reason: 'Armed alerts still refresh OS permissions on resume.');
        }
      } finally {
        await disposeClientRuntime(tester, runtime);
      }
    });
  }

  testWidgets('manual pairing validates six digits and submits only once',
      (tester) async {
    final gateway = _PayloadGateway()..requiresPairingCode = true;
    final codes = <String?>[];
    final runtime = ClientRuntime(pair: (payload) async {
      codes.add(payload.pairingCode);
      return PairingSession(
          payload: payload.withPairingCode(null), sessionToken: 'token');
    });
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(find.byType(PairingCodeDialog), findsOneWidget);
      expect(codes, isEmpty);
      final input = find.byKey(const ValueKey('pairing-code-input'));
      await tester.enterText(input, '123');
      tester.testTextInput.hide();
      await _tap(tester, find.text(_strings.ui('confirmPairingCode')));
      expect(
          find.text(_strings.ui('pairingCodeInvalidFormat')), findsOneWidget);
      expect(codes, isEmpty);
      await tester.enterText(input, '000042');
      tester.testTextInput.hide();
      final confirm = find.ancestor(
        of: find.text(_strings.ui('confirmPairingCode')),
        matching: find.byType(FilledButton),
      );
      final submit = tester.widget<FilledButton>(confirm).onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(codes, ['000042']);
      expect(gateway.requests, hasLength(1));
      expect(find.byType(PairingCodeDialog), findsNothing);
      expect(find.byKey(const ValueKey('client-watch')), findsOneWidget);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets('canceling code entry pairs nothing and forgets typed digits',
      (tester) async {
    final gateway = _PayloadGateway()..requiresPairingCode = true;
    var pairs = 0;
    final runtime = ClientRuntime(pair: (payload) async {
      pairs++;
      return PairingSession(payload: payload, sessionToken: 'token');
    });
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      await tester.enterText(
          find.byKey(const ValueKey('pairing-code-input')), '000042');
      tester.testTextInput.hide();
      await _tap(tester, find.text(_strings.ui('cancel')));
      expect(pairs, 0);
      expect(runtime.currentState.session, isNull);
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      final input = tester.widget<TextFormField>(
          find.byKey(const ValueKey('pairing-code-input')));
      expect(input.controller?.text, isEmpty);
      expect(pairs, 0);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets('leaving the client screen closes its pending code dialog',
      (tester) async {
    final gateway = _PayloadGateway()..requiresPairingCode = true;
    var pairs = 0;
    final runtime = ClientRuntime(pair: (payload) async {
      pairs++;
      return PairingSession(payload: payload, sessionToken: 'token');
    });
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(find.byType(PairingCodeDialog), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(find.byType(PairingCodeDialog), findsNothing);
      expect(pairs, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets(
      'manual connection validates, retries, arms alerts and opens watch',
      (tester) async {
    final gateway = _PayloadGateway();
    var alertStarts = 0;
    var streamStarts = 0;
    var streamStops = 0;
    final runtime = ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: 'token'),
      startAlerts: (_) async {
        alertStarts++;
        return true;
      },
      startStream: (_, {bool audioEnabled = false}) async {
        streamStarts++;
        return null;
      },
      stopStream: (_) async => streamStops++,
    );
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway));
      await _tap(tester, find.text(_strings.ui('findAndConnectRoom')));
      await _enterAddress(tester, '[invalid');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(gateway.requests, isEmpty);
      expect(find.text(_strings.ui('invalidIpFormat')), findsOneWidget);

      gateway.failure =
          const PairingFailure(PairingFailureCode.connectionUnavailable);
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(runtime.currentState.session, isNull);
      expect(find.text(_strings.pairingFailureMessage('connectionUnavailable')),
          findsOneWidget);

      gateway.failure = null;
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(gateway.requests, ['192.168.1.20:8080', '192.168.1.20:8080']);
      expect(runtime.currentState.session?.payload.deviceId, 'room');
      expect(alertStarts, 1);
      expect(find.byKey(const ValueKey('client-watch')), findsOneWidget);
      await _tap(tester, find.byTooltip(_strings.ui('openLiveWatch')));
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(streamStarts, 1);
      await _tap(tester, find.byType(BackButtonIcon));
      expect(find.byType(WatchScreen), findsNothing);
      expect(streamStops, 0,
          reason: 'The mocked start returns no media handle.');
      expect(runtime.currentState.phase, ClientRuntimePhase.alertOnly);
      expect(runtime.currentState.alertsActive, isTrue);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets(
      'pairing request cannot be submitted twice while LAN reply is pending',
      (tester) async {
    final reply = Completer<PairingPayload>();
    final gateway = _PayloadGateway()..reply = reply;
    var pairs = 0;
    final runtime = ClientRuntime(pair: (payload) async {
      pairs++;
      return PairingSession(payload: payload, sessionToken: 'token');
    });
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      final connect = find.text(_strings.ui('connectWithIp'));
      await _tap(tester, connect);
      await _tap(tester, connect);
      expect(gateway.requests, hasLength(1));
      reply.complete(_payload());
      await tester.pumpAndSettle();
      expect(pairs, 1);
      expect(find.byKey(const ValueKey('client-watch')), findsOneWidget);
    } finally {
      if (!reply.isCompleted) reply.complete(_payload());
      await tester.pumpAndSettle();
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets('repeated watch actions open a single route and can reopen',
      (tester) async {
    var starts = 0;
    final runtime = ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async {
        starts++;
        return null;
      },
    );
    try {
      await runtime.restoreSession(
          PairingSession(payload: _payload(), sessionToken: 'token'));
      await tester.pumpWidget(_app(runtime));
      await tester.pumpAndSettle();
      final watch = tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
          widget is IconButton &&
          widget.tooltip == _strings.ui('openLiveWatch')));
      watch.onPressed!();
      watch.onPressed!();
      await tester.pumpAndSettle();

      expect(find.byType(WatchScreen, skipOffstage: false), findsOneWidget);
      expect(starts, 1);
      await _tap(tester, find.byType(BackButtonIcon));
      expect(find.byType(WatchScreen, skipOffstage: false), findsNothing);
      await _tap(tester, find.byTooltip(_strings.ui('openLiveWatch')));
      expect(find.byType(WatchScreen, skipOffstage: false), findsOneWidget);
      expect(starts, 2);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets('closing the pairing screen ignores a late LAN reply',
      (tester) async {
    final reply = Completer<PairingPayload>();
    final gateway = _PayloadGateway()..reply = reply;
    var pairs = 0;
    final runtime = ClientRuntime(pair: (payload) async {
      pairs++;
      return PairingSession(payload: payload, sessionToken: 'token');
    });
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      await tester.pumpWidget(const SizedBox.shrink());
      reply.complete(_payload());
      await tester.pumpAndSettle();
      expect(pairs, 0);
      expect(runtime.currentState.session, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      if (!reply.isCompleted) reply.complete(_payload());
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets(
      'unexpected pairing failures remain actionable without technical details',
      (tester) async {
    final gateway = _PayloadGateway()
      ..failure = StateError('INTERNAL_PAIRING_SECRET');
    final runtime = ClientRuntime(
        pair: (payload) async =>
            PairingSession(payload: payload, sessionToken: 'token'));
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await _enterAddress(tester, '192.168.1.20:8080');
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(find.textContaining('INTERNAL_PAIRING_SECRET'), findsNothing);
      expect(find.text(_strings.pairingFailureMessage('connectionUnavailable')),
          findsOneWidget);
      gateway.failure = null;
      await _tap(tester, find.text(_strings.ui('connectWithIp')));
      expect(runtime.currentState.session, isNotNull);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets(
      'discovered room refresh and selection use the advertised endpoint',
      (tester) async {
    final browser = _DiscoveryBrowser();
    final gateway = _PayloadGateway()..requiresPairingCode = true;
    String? submittedCode;
    final runtime = ClientRuntime(
      pair: (payload) async {
        submittedCode = payload.pairingCode;
        return PairingSession(
            payload: payload.withPairingCode(null), sessionToken: 'token');
      },
      serviceBrowser: browser,
    );
    try {
      await tester.pumpWidget(_app(runtime, gateway: gateway, initialTab: 1));
      await tester.pumpAndSettle();
      final initialStarts = browser.starts;
      await _tap(tester, find.byTooltip(_strings.ui('refreshDiscovery')));
      expect(browser.starts, initialStarts + 1);
      browser.publish(const MiuCamDiscoveredService(
        name: 'Room discovered',
        host: '192.168.1.45',
        port: 8123,
        addresses: [],
        metadata: {'id': 'room'},
      ));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(_strings.ui('connectDiscoveredRoom')));
      expect(gateway.requests, ['192.168.1.45:8123']);
      expect(find.byType(PairingCodeDialog), findsOneWidget);
      expect(submittedCode, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('pairing-code-input')), '482610');
      tester.testTextInput.hide();
      await _tap(tester, find.text(_strings.ui('confirmPairingCode')));
      expect(submittedCode, '482610');
      expect(find.byKey(const ValueKey('client-watch')), findsOneWidget);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });

  testWidgets(
      'notification history and phone notification settings have distinct actions',
      (tester) async {
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    var systemSettingsOpens = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'openAppSettings') {
        systemSettingsOpens++;
        return true;
      }
      return null;
    });
    final runtime = ClientRuntime(
        pair: (payload) async =>
            PairingSession(payload: payload, sessionToken: 'token'));
    try {
      await tester.pumpWidget(_app(runtime, initialTab: 3));
      await _tap(tester, find.text(_strings.ui('openAppSettings')));
      expect(find.text(_strings.ui('systemNotificationSettingsTitle')),
          findsOneWidget);
      expect(systemSettingsOpens, 1);
      expect(find.byKey(const ValueKey('client-settings')), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await _tap(tester, find.text(_strings.ui('notificationsManageText')));
      expect(find.byKey(const ValueKey('client-history')), findsOneWidget);
      expect(systemSettingsOpens, 1);
    } finally {
      await disposeClientRuntime(tester, runtime);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets(
      'preferences survive reopening and dismissing language picker changes nothing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences =
        ClientPreferencesService(await SharedPreferences.getInstance());
    final localeChanges = <Locale?>[];
    final runtime = ClientRuntime(
        pair: (payload) async =>
            PairingSession(payload: payload, sessionToken: 'token'));
    try {
      await tester.pumpWidget(_app(runtime,
          initialTab: 3,
          preferences: preferences,
          onLocaleChanged: localeChanges.add));
      await _tap(tester, find.byType(Switch));
      expect(preferences.keepScreenAwake, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await _tap(tester, find.text(_strings.ui('language')));
      await _tap(tester, find.text('Deutsch'));
      expect(preferences.locale, const Locale('de'));
      expect(localeChanges, [const Locale('de')]);

      await _tap(tester, find.text(_strings.ui('language')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(preferences.locale, const Locale('de'));
      expect(localeChanges, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester
          .pumpWidget(_app(runtime, initialTab: 3, preferences: preferences));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('Deutsch'), findsOneWidget);
      await _tap(
          tester,
          find
              .ancestor(
                  of: find.text(_strings.ui('notificationsManageText')),
                  matching: find.byType(InkWell))
              .first);
      expect(find.byKey(const ValueKey('client-history')), findsOneWidget);
    } finally {
      await disposeClientRuntime(tester, runtime);
    }
  });
}

final _strings = AppStrings(const Locale('tr'));

Widget _app(ClientRuntime runtime,
        {PairingPayloadGateway? gateway,
        int initialTab = 0,
        ClientPreferencesService? preferences,
        ValueChanged<Locale?>? onLocaleChanged}) =>
    MaterialApp(
      locale: const Locale('tr'),
      theme: MiuCamTheme.clientTheme(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          initialTab: initialTab,
          pairingPayloadGateway: gateway ?? _PayloadGateway(),
          preferences: preferences,
          onLocaleChanged: onLocaleChanged),
    );

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 250,
        scrollable: find
            .byWidgetPredicate((widget) =>
                widget is Scrollable &&
                (widget.axisDirection == AxisDirection.down ||
                    widget.axisDirection == AxisDirection.up))
            .last);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _enterAddress(WidgetTester tester, String value) async {
  final input = find.byType(TextField);
  await tester.ensureVisible(input);
  await tester.enterText(input, value);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

PairingPayload _payload({bool requiresPairingCode = false}) => PairingPayload(
    schemaVersion: 2,
    host: '192.168.1.20',
    port: 8080,
    deviceId: 'room',
    deviceName: 'Test room',
    pairingNonce: 'nonce',
    requiresPairingCode: requiresPairingCode,
    expiresAtMs:
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    capabilities: const {});

class _PayloadGateway implements PairingPayloadGateway {
  final requests = <String>[];
  Object? failure;
  Completer<PairingPayload>? reply;
  bool requiresPairingCode = false;
  @override
  Future<PairingPayload> fetch(
      {required String host, required int port}) async {
    requests.add('$host:$port');
    if (failure case final error?) throw error;
    return reply == null
        ? _payload(requiresPairingCode: requiresPairingCode)
        : reply!.future;
  }
}

class _DiscoveryBrowser extends MiuCamServiceBrowser {
  final _events = StreamController<List<MiuCamDiscoveredService>>.broadcast();
  List<MiuCamDiscoveredService> _current = [];
  int starts = 0;
  @override
  List<MiuCamDiscoveredService> get services => _current;
  @override
  Stream<List<MiuCamDiscoveredService>> get updates => _events.stream;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => _events.close();
  void publish(MiuCamDiscoveredService service) {
    _current = [service];
    _events.add(_current);
  }
}
