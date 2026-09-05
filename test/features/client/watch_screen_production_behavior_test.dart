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
  for (final locale in const [Locale('tr'), Locale('ar', 'QA')]) {
    testWidgets(
        'fullscreen polls and scrolls detection pause in ${locale.languageCode}',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
          _wakelockChannel,
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]));
      final controls = _PollingDetectionRoomControls();
      final session =
          PairingSession(payload: _payload(), sessionToken: 'token');
      final runtime = ClientRuntime(
        pair: (_) async => session,
        startStream: (_, {bool audioEnabled = false}) async => null,
        stopStream: (_) async {},
        roomControls: controls,
      );
      addTearDown(() async {
        await runtime.dispose();
        messenger.setMockMessageHandler(_wakelockChannel, null);
      });
      await runtime.pairWithServer(session.payload);
      final strings = AppStrings(locale);
      final watch = WatchScreen(runtime: runtime, keepScreenAwake: false);
      await tester.pumpWidget(_App(locale: locale, home: watch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.scrollUntilVisible(
        find.text(strings.ui('fullScreen')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text(strings.ui('fullScreen'))),
        alignment: .5,
      );
      await tester.pump();
      await tester.tap(find.text(strings.ui('fullScreen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      tester.view.physicalSize = const Size(600, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_App(locale: locale, textScale: 2, home: watch));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('audio-detection-paused')), findsNothing);
      final refreshesBeforePause = controls.refreshCalls;
      controls.remotePaused = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(controls.refreshCalls, greaterThan(refreshesBeforePause));
      final notice =
          find.byKey(const ValueKey('fullscreen-audio-detection-notice'));
      expect(find.text(strings.ui('roomAudioDetectionPaused')), findsOneWidget);
      expect(tester.getSize(notice).height, lessThanOrEqualTo(112.01));
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(notice)),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      final scrollable = tester.state<ScrollableState>(find.descendant(
        of: notice,
        matching: find.byType(Scrollable),
      ));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final resumeHelp = find.text(strings.ui('roomAudioDetectionResumeHelp'));
      await Scrollable.ensureVisible(tester.element(resumeHelp), alignment: 1);
      await tester.pump();
      expect(tester.getRect(notice).contains(tester.getCenter(resumeHelp)),
          isTrue);
      expect(tester.takeException(), isNull);

      controls.remotePaused = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('audio-detection-paused')), findsNothing);
      final exit = find.byTooltip(strings.ui('exitFullScreen'));
      expect(exit.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final scenario in const [
    (
      name: 'portrait',
      locale: Locale('tr'),
      viewport: Size(800, 600),
      textScale: 1.0
    ),
    (
      name: 'landscape large text',
      locale: Locale('tr'),
      viewport: Size(600, 320),
      textScale: 2.0
    ),
    (
      name: 'RTL landscape large text',
      locale: Locale('ar', 'QA'),
      viewport: Size(600, 320),
      textScale: 2.0
    ),
  ]) {
    testWidgets(
        'night clock keeps the room detection pause visible ${scenario.name}',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
          _wakelockChannel,
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]));
      final controls = _PausedDetectionRoomControls();
      final connectionStates = StreamController<bool>.broadcast();
      final session =
          PairingSession(payload: _payload(), sessionToken: 'token');
      final runtime = ClientRuntime(
        pair: (_) async => session,
        startStream: (_, {bool audioEnabled = false}) async => null,
        stopStream: (_) async {},
        startAlerts: (_) async => true,
        stopAlerts: () async {},
        alertConnectionStates: connectionStates.stream,
        roomControls: controls,
      );
      addTearDown(() async {
        await runtime.dispose();
        await connectionStates.close();
        messenger.setMockMessageHandler(_wakelockChannel, null);
      });
      await runtime.pairWithServer(session.payload);
      await runtime.startAlertListening();
      connectionStates.add(true);
      final watch = WatchScreen(runtime: runtime, keepScreenAwake: false);
      await tester.pumpWidget(_App(locale: scenario.locale, home: watch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final strings = AppStrings(scenario.locale);
      await tester.scrollUntilVisible(
        find.text(strings.ui('nightClock')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await Scrollable.ensureVisible(
        tester.element(find.text(strings.ui('nightClock'))),
        alignment: .5,
      );
      await tester.pump();
      await tester.tap(find.text(strings.ui('nightClock')));
      await tester.pumpAndSettle();

      tester.view.physicalSize = scenario.viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_App(
        locale: scenario.locale,
        textScale: scenario.textScale,
        home: watch,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Paused detection notice must scroll without overflow.');
      if (scenario.locale.languageCode == 'ar') {
        expect(
            Directionality.of(tester.element(
              find.text(strings.ui('roomAudioDetectionPaused')),
            )),
            TextDirection.rtl);
      }
      await Scrollable.ensureVisible(
        tester.element(find.text(strings.ui('roomAudioDetectionResumeHelp'))),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text(strings.ui('roomAudioDetectionPaused')), findsOneWidget);
      expect(find.text(strings.ui('roomAudioDetectionResumeHelp')),
          findsOneWidget);
      expect(find.text('Video kapalı; ses ve uyarılar açık.'), findsNothing);
      expect(find.text(strings.ui('nightClockAudioAlertsOn')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

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
  const _App({
    required this.home,
    this.locale = const Locale('tr'),
    this.textScale = 1,
  });

  final Widget home;
  final Locale locale;
  final double textScale;

  @override
  Widget build(BuildContext context) => MaterialApp(
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
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
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

class _PausedDetectionRoomControls extends _PermissionDeniedRoomControls {
  @override
  ClientRoomControlSnapshot get currentState =>
      const ClientRoomControlSnapshot(audioDetectionPaused: true);
}

class _PollingDetectionRoomControls extends _PermissionDeniedRoomControls {
  final _updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  var _snapshot = const ClientRoomControlSnapshot();
  bool remotePaused = false;
  int refreshCalls = 0;

  @override
  ClientRoomControlSnapshot get currentState => _snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => _updates.stream;

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    refreshCalls++;
    _snapshot = ClientRoomControlSnapshot(audioDetectionPaused: remotePaused);
    _updates.add(_snapshot);
    return null;
  }

  @override
  Future<void> dispose() async {
    await _updates.close();
    await super.dispose();
  }
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
