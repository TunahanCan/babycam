import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/controls/room_audio_detection_notice.dart';
import 'package:miucam/features/client/controls/room_controls_panel.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('detection pause and recovery are localized for $locale',
        (tester) async {
      final controls = _ObservedRoomControls();
      addTearDown(controls.close);
      final strings = AppStrings(locale);
      await tester.pumpWidget(_app(
          locale,
          RoomAudioDetectionNotice(
            controls: controls,
            session: _session(),
            pollForChanges: false,
          )));
      expect(
          find.byKey(const ValueKey('audio-detection-paused')), findsNothing);

      // This parent is neither playing comfort nor talking itself. The room
      // reports that a different parent's output has suspended detection.
      controls.publish(const ClientRoomControlSnapshot(
        audioDetectionPaused: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text(strings.ui('roomAudioDetectionPaused')), findsOneWidget);
      expect(find.text(strings.ui('roomAudioDetectionHelp')), findsOneWidget);
      expect(find.text(strings.ui('roomAudioDetectionResumeHelp')),
          findsOneWidget);
      expect(strings.ui('roomAudioDetectionPaused'),
          isNot(contains('Nicht übersetzt')));
      expect(
          strings.ui('roomAudioDetectionPaused'), isNot(contains('غير مترجم')));

      controls.publish(const ClientRoomControlSnapshot(
        audioDetectionPaused: false,
      ));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('audio-detection-paused')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('visible parent polls remote pause and refreshes after resume',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controls = _ObservedRoomControls();
    addTearDown(controls.close);
    await tester.pumpWidget(_app(
        const Locale('tr'),
        RoomAudioDetectionNotice(
          controls: controls,
          session: _session(),
        )));
    await tester.pumpAndSettle();
    expect(controls.refreshCalls, 1);

    controls.remotePaused = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('audio-detection-paused')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final callsBeforeBackground = controls.refreshCalls;
    await tester.pump(const Duration(seconds: 6));
    expect(controls.refreshCalls, callsBeforeBackground);

    controls.remotePaused = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controls.refreshCalls, callsBeforeBackground + 1);
    expect(find.byKey(const ValueKey('audio-detection-paused')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('room controls explain the limitation before comfort playback',
      (tester) async {
    final controls = _ObservedRoomControls();
    addTearDown(controls.close);
    final strings = AppStrings(const Locale('tr'));
    await tester.pumpWidget(_app(
        const Locale('tr'),
        SingleChildScrollView(
          child: RoomControlsPanel(controls: controls, session: _session()),
        )));
    await tester.pumpAndSettle();
    expect(find.text(strings.ui('roomAudioDetectionHelp')), findsOneWidget);
    expect(find.byKey(const ValueKey('audio-detection-paused')), findsNothing);

    controls.publish(ClientRoomControlSnapshot(
      comfort: ComfortAudioState.initial(updatedAtMs: 1).copyWith(
        playing: true,
        volume: 0,
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('audio-detection-paused')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

PairingSession _session() => const PairingSession(
      payload: PairingPayload(
        schemaVersion: 1,
        host: '127.0.0.1',
        port: 8080,
        deviceId: 'room',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: 9999999999999,
        capabilities: {},
      ),
      sessionToken: 'test-token',
    );

class _ObservedRoomControls extends ClientRoomControls {
  final _changes = StreamController<ClientRoomControlSnapshot>.broadcast();
  var _snapshot = const ClientRoomControlSnapshot();
  bool remotePaused = false;
  int refreshCalls = 0;

  @override
  ClientRoomControlSnapshot get currentState => _snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => _changes.stream;

  void publish(ClientRoomControlSnapshot state) {
    _snapshot = state;
    _changes.add(state);
  }

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    refreshCalls++;
    publish(ClientRoomControlSnapshot(audioDetectionPaused: remotePaused));
    return null;
  }

  @override
  Future<void> stopTalking() async {}

  Future<void> close() => _changes.close();
}
