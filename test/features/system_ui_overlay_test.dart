import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/camera_permission_gateway.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/client/pairing/qr_scan_screen.dart';
import 'package:miucam/features/role_selection/role_selection_screen.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  final lightScreens = <String, Widget Function()>{
    'role selection': () => RoleSelectionScreen(onRoleSelected: (_) {}),
    for (final variant in MiuCamShellVariant.values)
      '${variant.name} home': () => Scaffold(
            body: MiuCamGradientShell(
              variant: variant,
              child: const SizedBox.expand(),
            ),
          ),
  };
  for (final entry in lightScreens.entries) {
    testWidgets('${entry.key} restores dark status icons after QR scanner',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(entry.value(), navigator: navigator));
      await tester.pumpAndSettle();
      _expectDarkStatusIcons();
      await _visitScanner(tester, navigator);
      _expectDarkStatusIcons();
    });
  }

  testWidgets('watch restores status contrast after scanner and dark modes',
      (tester) async {
    final payload = PairingPayload(
      schemaVersion: 2,
      host: '192.168.1.20',
      port: 8080,
      deviceId: 'room',
      deviceName: 'Room',
      pairingNonce: 'nonce',
      expiresAtMs: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );
    final runtime = ClientRuntime(
      pair: (_) async =>
          PairingSession(payload: payload, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async => null,
      stopStream: (_) async {},
    );
    final navigator = GlobalKey<NavigatorState>();
    final strings = AppStrings(const Locale('en', 'US'));
    try {
      await runtime.pairWithServer(payload);
      await tester.pumpWidget(_app(
        WatchScreen(runtime: runtime, keepScreenAwake: false),
        navigator: navigator,
      ));
      await tester.pumpAndSettle();
      _expectDarkStatusIcons();
      await _visitScanner(tester, navigator);
      _expectDarkStatusIcons();

      for (final mode in [
        (action: 'fullScreen', exit: 'exitFullScreen'),
        (action: 'nightClock', exit: 'exitNightClock'),
      ]) {
        final action = find.text(strings.ui(mode.action));
        await tester.scrollUntilVisible(action, 250,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(SystemChrome.latestStyle?.statusBarIconBrightness,
            Brightness.light);
        expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
        await tester.tap(find.byTooltip(strings.ui(mode.exit)));
        await tester.pumpAndSettle();
        _expectDarkStatusIcons();
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await runtime.dispose();
    }
  });
}

Widget _app(Widget home, {required GlobalKey<NavigatorState> navigator}) =>
    MaterialApp(
      navigatorKey: navigator,
      locale: const Locale('en', 'US'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

Future<void> _visitScanner(
    WidgetTester tester, GlobalKey<NavigatorState> navigator) async {
  navigator.currentState!.push<void>(MaterialPageRoute(
    builder: (_) => const QRScanScreen(permissionGateway: _DeniedCamera()),
  ));
  await tester.pumpAndSettle();
  expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
  navigator.currentState!.pop();
  await tester.pumpAndSettle();
}

void _expectDarkStatusIcons() {
  expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
  expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
}

class _DeniedCamera implements CameraPermissionGateway {
  const _DeniedCamera();

  @override
  Future<CameraPermissionStatus> status() async =>
      CameraPermissionStatus.permanentlyDenied;

  @override
  Future<CameraPermissionStatus> request() => status();

  @override
  Future<bool> openSettings() async => false;
}
