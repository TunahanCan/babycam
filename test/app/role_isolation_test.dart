import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:miucam/app/app_bootstrap.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/app/install_integrity_guard.dart';
import 'package:miucam/app/role_repository.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_app_shell.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/server_app_shell.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('miucam/platform_runtime');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  setUpAll(() {
    final previous = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchasePlatform.instance = _UnavailableStore();
      final _ = InAppPurchase.instance;
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
  setUp(() {
    InAppPurchasePlatform.instance = _UnavailableStore();
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async => 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            native, (call) async => {'platform': 'android'});
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });

  for (final role in AppRole.values) {
    testWidgets('bootstrap creates only the selected ${role.name} runtime',
        (tester) async {
      final runtimes = _Runtimes();
      await _start(tester, role, runtimes);
      expect(runtimes.created, [role]);
      expect(
          find.byType(role == AppRole.server ? ServerAppShell : ClientAppShell),
          findsOneWidget);
      await _close(tester);
    });
  }

  for (final from in AppRole.values) {
    final to = from == AppRole.server ? AppRole.client : AppRole.server;
    testWidgets('$from waits for disposal before creating $to', (tester) async {
      final runtimes = _Runtimes()..stopGate = Completer<void>();
      await _start(tester, from, runtimes);
      await _requestSwitch(tester, from, to);
      expect(runtimes.stops, 1);
      expect(runtimes.created, [from]);
      expect(find.byType(ClientAppShell), findsNothing);
      expect(find.byType(ServerAppShell), findsNothing);
      expect(find.text('Switching role...'), findsOneWidget);
      runtimes.stopGate!.complete();
      await _frames(tester);
      expect(runtimes.created, [from, to]);
      expect(
          runtimes.preferences
              .getString(SharedPreferencesRoleRepository.storageKey),
          to.name);
      await _close(tester);
    });
  }

  testWidgets('native foreground work blocks creation after Dart dispose',
      (tester) async {
    final runtimes = _Runtimes();
    await _start(tester, AppRole.client, runtimes);
    var nativeBusy = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            native,
            (call) async => {
                  'platform': 'android',
                  'alertDemand': nativeBusy,
                  'foregroundServiceActive': nativeBusy,
                });
    await _requestSwitch(tester, AppRole.client, AppRole.server);
    await tester.pump(const Duration(milliseconds: 500));
    expect(runtimes.stops, 1);
    expect(runtimes.created, [AppRole.client]);
    expect(
        runtimes.preferences
            .getString(SharedPreferencesRoleRepository.storageKey),
        'client');
    nativeBusy = false;
    await tester.pump(const Duration(milliseconds: 100));
    await _frames(tester);
    expect(runtimes.created, [AppRole.client, AppRole.server]);
    await _close(tester);
  });

  testWidgets('failed shutdown never reconstructs either mode', (tester) async {
    final runtimes = _Runtimes()
      ..stopFailure = StateError('Native stop failed');
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (error) {
      if (error.library == 'MiuCam bootstrap') {
        errors.add(error);
      } else {
        previousHandler?.call(error);
      }
    };
    addTearDown(() => FlutterError.onError = previousHandler);
    await _start(tester, AppRole.client, runtimes);
    await _requestSwitch(tester, AppRole.client, AppRole.server);
    await _frames(tester);
    expect(runtimes.created, [AppRole.client]);
    expect(find.byType(ClientAppShell), findsNothing);
    expect(find.byType(ServerAppShell), findsNothing);
    expect(find.text('The previous mode could not stop'), findsOneWidget);
    expect(errors, isNotEmpty);
    expect(
        runtimes.preferences
            .getString(SharedPreferencesRoleRepository.storageKey),
        'client');
    await _close(tester);
  });

  testWidgets('closing the app during a switch retains the teardown owner',
      (tester) async {
    final runtimes = _Runtimes()..stopGate = Completer<void>();
    await _start(tester, AppRole.client, runtimes);
    await _requestSwitch(tester, AppRole.client, AppRole.server);
    await tester.pumpWidget(const SizedBox.shrink());
    runtimes.stopGate!.complete();
    await _frames(tester);
    expect(runtimes.stops, 1);
    expect(runtimes.created, [AppRole.client]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late permission response cannot restart the newly selected role',
      (tester) async {
    final runtimes = _Runtimes();
    await _start(tester, AppRole.client, runtimes);
    final permission = Completer<int>();
    var permissionChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async {
      permissionChecks++;
      return permissionChecks == 1 ? permission.future : 1;
    });
    final select = tester
        .widget<ClientAppShell>(find.byType(ClientAppShell))
        .onRoleSelected;
    select(AppRole.server);
    await _frames(tester);
    expect(runtimes.created, [AppRole.client]);
    select(AppRole.server);
    await _frames(tester);
    expect(runtimes.created, [AppRole.client, AppRole.server]);
    permission.complete(1);
    await _frames(tester);
    expect(runtimes.created, [AppRole.client, AppRole.server]);
    expect(runtimes.stops, 1);
    await _close(tester);
  });

  for (final locale in AppStrings.supportedLocales) {
    testWidgets('shutdown error remains usable at large text in $locale',
        (tester) async {
      final runtimes = _Runtimes()..stopFailure = StateError('Stop failed');
      final previousHandler = FlutterError.onError;
      FlutterError.onError = (error) {
        if (error.library != 'MiuCam bootstrap') previousHandler?.call(error);
      };
      addTearDown(() => FlutterError.onError = previousHandler);
      await _start(tester, AppRole.client, runtimes, locale: locale);
      await _requestSwitch(tester, AppRole.client, AppRole.server);
      tester.view.physicalSize = const Size.square(320);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _frames(tester);
      final strings = AppStrings.of(tester.element(find.byType(FilledButton)));
      expect(find.text(strings.ui('roleShutdownFailedTitle')), findsOneWidget);
      final retry = find.text(strings.ui('tryAgain'));
      await tester.scrollUntilVisible(retry, 120,
          scrollable: find.byType(Scrollable));
      await _frames(tester);
      expect(retry.hitTestable(), findsOneWidget);
      expect(runtimes.created, [AppRole.client]);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }
}

class _Runtimes {
  final created = <AppRole>[];
  int stops = 0;
  Completer<void>? stopGate;
  Object? stopFailure;
  late SharedPreferences preferences;

  Future<void> stop() async {
    stops++;
    await stopGate?.future;
    if (stopFailure case final failure?) throw failure;
  }
}

Future<void> _start(WidgetTester tester, AppRole role, _Runtimes runtimes,
    {Locale locale = const Locale('en')}) async {
  SharedPreferences.setMockInitialValues({
    InstallIntegrityGuard.markerKey: true,
    SharedPreferencesRoleRepository.storageKey: role.name,
  });
  runtimes.preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AppBootstrap(
      preferencesLoader: () async => runtimes.preferences,
      clientRuntimeFactory: (preferences, strings, purchases) {
        runtimes.created.add(AppRole.client);
        return ClientRuntime(
          pair: (payload) async =>
              PairingSession(payload: payload, sessionToken: 'test'),
          disposeTransports: runtimes.stop,
        );
      },
      serverRuntimeFactory: (config, strings, purchases) {
        runtimes.created.add(AppRole.server);
        return ServerRuntime(
            mediaRuntime: MediaRuntimeController(), onStop: runtimes.stop);
      },
    ),
  ));
  await _frames(tester);
}

Future<void> _requestSwitch(
    WidgetTester tester, AppRole from, AppRole to) async {
  if (from == AppRole.client) {
    tester
        .widget<ClientAppShell>(find.byType(ClientAppShell))
        .onRoleSelected(to);
  } else {
    tester
        .widget<ServerAppShell>(find.byType(ServerAppShell))
        .onRoleSelected(to);
    await tester.pumpAndSettle();
    final strings = AppStrings.of(tester.element(find.byType(BottomSheet)));
    tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, strings.ui('switchToClient')))
        .onPressed!();
  }
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _frames(tester);
  expect(tester.takeException(), isNull);
}

class _UnavailableStore extends InAppPurchasePlatform {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> isAvailable() async => false;
}
