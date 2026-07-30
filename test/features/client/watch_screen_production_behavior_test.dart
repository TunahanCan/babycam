import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/l10n/app_strings.dart';

const _wakelockChannel = 'dev.flutter.pigeon.wakelock_plus_platform_interface.'
    'WakelockPlusApi.toggle';

void main() {
  for (final backgroundState in const [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets(
      'watch ${backgroundState.name} iken stream ve wakelock durur',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wakelockMessages = <List<int>>[];
        messenger.setMockMessageHandler(_wakelockChannel, (message) async {
          if (message != null) {
            wakelockMessages.add(_bytes(message));
          }
          return const StandardMessageCodec().encodeMessage(<Object?>[null]);
        });

        var starts = 0;
        var stops = 0;
        final session = PairingSession(
          payload: _payload(),
          sessionToken: 'token',
        );
        final runtime = ClientRuntime(
          pair: (_) async => session,
          startStream: (_, {bool audioEnabled = false}) async {
            starts++;
            return const ActiveStreamSession(streamToken: 'stream');
          },
          stopStream: (_) async => stops++,
        );
        var disposed = false;
        addTearDown(() async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          messenger.setMockMessageHandler(_wakelockChannel, null);
          if (!disposed) await runtime.dispose();
        });
        await runtime.pairWithServer(session.payload);

        await tester.pumpWidget(
          _App(
            home: WatchScreen(
              runtime: runtime,
              initialTab: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(starts, 1);
        expect(wakelockMessages, isNotEmpty);
        final enabledMessage = List<int>.of(wakelockMessages.last);

        tester.binding.handleAppLifecycleStateChanged(backgroundState);
        await tester.pumpAndSettle();

        expect(stops, 1);
        expect(wakelockMessages.last, isNot(equals(enabledMessage)));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(starts, 2);
        expect(wakelockMessages.last, equals(enabledMessage));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await runtime.dispose();
        disposed = true;
        messenger.setMockMessageHandler(_wakelockChannel, null);
      },
    );
  }

  testWidgets('arka planda açılan watch resumed olmadan stream başlatmaz',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wakelockMessages = <List<int>>[];
    messenger.setMockMessageHandler(_wakelockChannel, (message) async {
      if (message != null) {
        wakelockMessages.add(_bytes(message));
      }
      return const StandardMessageCodec().encodeMessage(<Object?>[null]);
    });

    var starts = 0;
    final session = PairingSession(
      payload: _payload(),
      sessionToken: 'token',
    );
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async {
        starts++;
        return const ActiveStreamSession(streamToken: 'stream');
      },
      stopStream: (_) async {},
    );
    var disposed = false;
    addTearDown(() async {
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      messenger.setMockMessageHandler(_wakelockChannel, null);
      if (!disposed) await runtime.dispose();
    });
    await runtime.pairWithServer(session.payload);

    await tester.pumpWidget(
      _App(home: WatchScreen(runtime: runtime, initialTab: 1)),
    );
    await tester.pumpAndSettle();

    expect(starts, 0);
    final messagesBeforeResume = wakelockMessages
        .map<List<int>>((message) => List<int>.of(message))
        .toList();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(starts, 1);
    expect(wakelockMessages, isNotEmpty);
    final enabledMessage = wakelockMessages.last;
    for (final message in messagesBeforeResume) {
      expect(message, isNot(equals(enabledMessage)));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await runtime.dispose();
    disposed = true;
    messenger.setMockMessageHandler(_wakelockChannel, null);
  });

  testWidgets('kalıcı mikrofon reddi ayarları aç CTA sunar', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final semantics = tester.ensureSemantics();
    final controls = _PermissionDeniedRoomControls();
    final session = PairingSession(
      payload: _payload(),
      sessionToken: 'token',
    );
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startStream: (_, {bool audioEnabled = false}) async => null,
      stopStream: (_) async {},
      roomControls: controls,
    );
    var settingsCalls = 0;
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(session.payload);

    await tester.pumpWidget(
      _App(
        home: WatchScreen(
          runtime: runtime,
          keepScreenAwake: false,
          openSettings: () async {
            settingsCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final talkButton = find.bySemanticsLabel('Konuşmak için basılı tut');
    await tester.scrollUntilVisible(
      talkButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final node = tester.getSemantics(talkButton);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(controls.startCalls, 1);
    expect(
      find.text(
        'Konuşmak için mikrofon izni gerekli. '
        'İzni cihaz ayarlarından açabilirsin.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ayarları aç'), findsOneWidget);

    await tester.tap(find.text('Ayarları aç'));
    await tester.pump();

    expect(settingsCalls, 1);
    semantics.dispose();
  });
}

Uint8List _bytes(ByteData data) => Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );

class _App extends StatelessWidget {
  const _App({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      );
}

class _PermissionDeniedRoomControls extends ClientRoomControls {
  int startCalls = 0;

  @override
  ClientRoomControlSnapshot get currentState =>
      const ClientRoomControlSnapshot();

  @override
  Stream<ClientRoomControlSnapshot> get states => const Stream.empty();

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      null;

  @override
  Future<void> startTalking(PairingSession session) async {
    startCalls++;
    throw const RoomMicrophonePermissionException();
  }

  @override
  Future<void> stopTalking() async {}
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: 2,
      host: '127.0.0.1',
      port: 8080,
      deviceId: 'room',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {},
    );
