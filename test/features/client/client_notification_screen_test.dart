import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/core/protocol/alert_event_dto.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/client_home_screen.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/media/watch_screen.dart';
import 'package:mimicam/l10n/app_strings.dart';

void main() {
  testWidgets('gelen alert ana bildirim ekranina duser', (tester) async {
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);
    await runtime.recordAlert(_alert('alert-1', 'Gercek bildirim geldi'));

    await tester.pumpWidget(_App(
      home: ClientHomeScreen(
        runtime: runtime,
        activeRole: AppRole.client,
        onRoleSelected: (_) {},
        initialTab: 2,
      ),
    ));

    expect(find.text('Gercek bildirim geldi'), findsOneWidget);
    expect(find.text('Son durum bekleniyor'), findsNothing);
  });

  testWidgets('gelen alert watch gecmis ekranina duser', (tester) async {
    final session = PairingSession(payload: _payload(), sessionToken: 'token');
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async => null,
      stopStream: (_) async {},
      startAlerts: (_) async => true,
      stopAlerts: () async {},
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);
    await runtime.recordAlert(_alert('alert-1', 'Watch gecmis bildirimi'));

    await tester.pumpWidget(_App(
      home: WatchScreen(runtime: runtime, initialTab: 1),
    ));
    await tester.pump();

    expect(find.text('Watch gecmis bildirimi'), findsOneWidget);
    expect(find.text('Son durum bekleniyor'), findsNothing);
  });
}

class _App extends StatelessWidget {
  const _App({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        home: home,
      );
}

AlertEventDto _alert(String id, String message) => AlertEventDto(
      id: id,
      type: 'legacyAlert',
      severity: 'info',
      messageKey: 'legacyAlert',
      message: message,
      score: 0,
      timestampMs: DateTime(2026, 6, 29, 12, 30).millisecondsSinceEpoch,
      sourceDeviceId: 'server',
    );

PairingPayload _payload() => PairingPayload(
      schemaVersion: 1,
      host: '127.0.0.1',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http_ws'},
    );

const _localizationsDelegates = [
  AppStrings.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
