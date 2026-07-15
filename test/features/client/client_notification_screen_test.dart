import 'dart:async';

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
import 'package:mimicam/services/notification_service.dart';

void main() {
  testWidgets('bildirim filtreleri ses hareket ve sistem kayitlarini ayirir',
      (tester) async {
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);
    await runtime.recordAlert(_typedAlert(
      'audio-1',
      'Ses kaydi',
      type: 'cryDetected',
      messageKey: 'testMessage',
    ));
    await runtime.recordAlert(_typedAlert(
      'motion-1',
      'Hareket kaydi',
      type: 'motionDetected',
      messageKey: 'testMessage',
    ));
    await runtime.recordAlert(_typedAlert(
      'system-1',
      'Sistem kaydi',
      type: 'batteryLow',
      messageKey: 'batteryLow',
    ));

    await tester.pumpWidget(_App(
      home: ClientHomeScreen(
        runtime: runtime,
        activeRole: AppRole.client,
        onRoleSelected: (_) {},
        initialTab: 2,
      ),
    ));

    expect(find.text('Ses kaydi'), findsOneWidget);
    expect(find.text('Hareket kaydi'), findsOneWidget);
    expect(find.text('Sistem kaydi'), findsOneWidget);
    expect(find.text('Son durum bekleniyor'), findsNothing);

    await tester.tap(find.text('Hareket').first);
    await tester.pump();
    expect(find.text('Hareket kaydi'), findsOneWidget);
    expect(find.text('Ses kaydi'), findsNothing);
    expect(find.text('Sistem kaydi'), findsNothing);

    await tester.tap(find.text('Ses').first);
    await tester.pump();
    expect(find.text('Ses kaydi'), findsOneWidget);
    expect(find.text('Hareket kaydi'), findsNothing);
    expect(find.text('Sistem kaydi'), findsNothing);

    await tester.tap(find.text('Sistem').first);
    await tester.pump();
    expect(find.text('Sistem kaydi'), findsOneWidget);
    expect(find.text('Ses kaydi'), findsNothing);
    expect(find.text('Hareket kaydi'), findsNothing);
  });

  testWidgets('watch son uyaridan geçmişe geçer ve filtreler gerçekten çalışır',
      (tester) async {
    final session = PairingSession(payload: _payload(), sessionToken: 'token');
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async => null,
      stopStream: (_) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);
    await runtime.recordAlert(_typedAlert(
      'audio-watch',
      'Watch ses kaydı',
      type: 'cryDetected',
      messageKey: 'testMessage',
    ));
    await runtime.recordAlert(_typedAlert(
      'motion-watch',
      'Watch hareket kaydı',
      type: 'motionDetected',
      messageKey: 'testMessage',
    ));

    await tester.pumpWidget(_App(home: WatchScreen(runtime: runtime)));
    await tester.pumpAndSettle();
    final latestAlert = find.text('Watch hareket kaydı', skipOffstage: false);
    expect(latestAlert, findsOneWidget);

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch hareket kaydı'));
    await tester.pumpAndSettle();
    expect(find.text('Uyarı geçmişi'), findsOneWidget);

    await tester.tap(find.text('Ses').first);
    await tester.pump();
    expect(find.text('Watch ses kaydı'), findsOneWidget);
    expect(find.text('Watch hareket kaydı'), findsNothing);

    await tester.tap(find.text('Hareket').first);
    await tester.pump();
    expect(find.text('Watch hareket kaydı'), findsOneWidget);
    expect(find.text('Watch ses kaydı'), findsNothing);
  });

  testWidgets('watch hata ekranı teknik ayrıntı sızdırmaz ve retry sunar',
      (tester) async {
    final session = PairingSession(payload: _payload(), sessionToken: 'token');
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async =>
          throw StateError('INTERNAL_SECRET_STREAM_FAILURE'),
      stopStream: (_) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);

    await tester.pumpWidget(_App(home: WatchScreen(runtime: runtime)));
    await tester.pumpAndSettle();

    expect(find.text('Görüntü kesildi'), findsOneWidget);
    expect(find.text('Yeniden bağlan'), findsWidgets);
    expect(find.textContaining('INTERNAL_SECRET_STREAM_FAILURE'), findsNothing);
    expect(find.text('CANLI'), findsNothing);
    expect(find.byKey(const ValueKey('watch-stream-retry')), findsOneWidget);
  });

  testWidgets('watch yeniden bağlan işlemini tek seferde çalıştırır',
      (tester) async {
    final session = PairingSession(payload: _payload(), sessionToken: 'token');
    final retryGate = Completer<void>();
    var starts = 0;
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async {
        starts++;
        if (starts == 1) throw StateError('first attempt failed');
        await retryGate.future;
        throw StateError('retry attempt failed');
      },
      stopStream: (_) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);

    await tester.pumpWidget(_App(home: WatchScreen(runtime: runtime)));
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('watch-stream-retry'));

    await tester.tap(retry);
    await tester.pump();
    expect(starts, 2);
    final busyRetry = find.byKey(const ValueKey('watch-placeholder-retry'));
    expect(busyRetry, findsOneWidget);
    final busyButtonFinder = find.descendant(
      of: busyRetry,
      matching: find.byType(TextButton),
    );
    final button = tester.widget<TextButton>(busyButtonFinder);
    expect(button.onPressed, isNull);

    await tester.tap(busyButtonFinder);
    await tester.pump();
    expect(starts, 2);

    retryGate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('watch-stream-retry')), findsOneWidget);
  });

  testWidgets('eşleşmiş odadaki bildirime dokunmak canlı izlemeyi açar',
      (tester) async {
    final session = PairingSession(payload: _payload(), sessionToken: 'token');
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async => null,
      stopStream: (_) async {},
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);
    await runtime.recordAlert(_alert('alert-open', 'Canlıyı aç'));

    await tester.pumpWidget(_App(
      home: ClientHomeScreen(
        runtime: runtime,
        activeRole: AppRole.client,
        onRoleSelected: (_) {},
        initialTab: 2,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Canlıyı aç'));
    await tester.pumpAndSettle();

    expect(find.byType(WatchScreen), findsOneWidget);
  });

  testWidgets('telefon bildirimine dokunmak Bildirimler sekmesini acar',
      (tester) async {
    final taps = StreamController<String>.broadcast();
    addTearDown(taps.close);
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);
    await runtime.recordAlert(_alert('alert-tap', 'Dokunulan bildirim'));

    await tester.pumpWidget(_App(
      home: ClientHomeScreen(
        runtime: runtime,
        activeRole: AppRole.client,
        onRoleSelected: (_) {},
        notificationTapStream: taps.stream,
      ),
    ));
    final navigator = Navigator.of(
      tester.element(find.byType(ClientHomeScreen)),
    );
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Canli izleme rotasi')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dokunulan bildirim'), findsNothing);
    expect(find.text('Canli izleme rotasi'), findsOneWidget);

    taps.add('${NotificationService.alertsPayload}?alertId=alert-tap');
    await tester.pumpAndSettle();

    expect(find.text('Canli izleme rotasi'), findsNothing);
    expect(find.text('Dokunulan bildirim'), findsOneWidget);
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

AlertEventDto _typedAlert(
  String id,
  String message, {
  required String type,
  required String messageKey,
}) =>
    AlertEventDto(
      id: id,
      type: type,
      severity: 'info',
      messageKey: messageKey,
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
