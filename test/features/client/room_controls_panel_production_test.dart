import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/controls/room_controls_panel.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets('restores confirmed track and volume on first presentation',
      (tester) async {
    final controls = _Controls();
    addTearDown(controls.close);
    await tester.pumpWidget(_app(controls));
    await tester.pump();

    expect(tester.widget<Slider>(find.byType(Slider)).value, .8);
    expect(_chip(tester, 'rainSound').selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('track commands cannot overlap and failures restore selection',
      (tester) async {
    final controls = _Controls(playing: true);
    addTearDown(controls.close);
    final errors = <Object>[];
    await tester.pumpWidget(_app(controls, onError: errors.add));
    await tester.pump();

    await tester.tap(find.text(_strings.ui('pinkNoise')));
    await tester.pump();
    expect(controls.commands, ['play']);
    expect(controls.requestedTrack, 'pink_noise');
    expect(_chip(tester, 'whiteNoise').onSelected, isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);

    controls.command.completeError(StateError('offline'));
    await tester.pump();
    expect(errors, hasLength(1));
    expect(_chip(tester, 'rainSound').selected, isTrue);
    expect(_chip(tester, 'whiteNoise').onSelected, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('polling unchanged room state preserves a draft track selection',
      (tester) async {
    final controls = _Controls();
    addTearDown(controls.close);
    await tester.pumpWidget(_app(controls));
    await tester.pump();
    await tester.tap(find.text(_strings.ui('pinkNoise')));
    await tester.pump();
    controls.emit(controls.snapshot);
    await tester.pump();

    expect(_chip(tester, 'pinkNoise').selected, isTrue);
    expect(controls.commands, isEmpty);
  });

  testWidgets('room updates do not reset a volume drag', (tester) async {
    final controls = _Controls();
    addTearDown(controls.close);
    await tester.pumpWidget(_app(controls));
    await tester.pump();
    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(.8);
    slider.onChanged!(.35);
    await tester.pump();
    controls.emit(ClientRoomControlSnapshot(
      comfort: controls.snapshot.comfort!.copyWith(volume: .9),
    ));
    await tester.pump();
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, .35);
    slider.onChangeEnd!(.35);
    await tester.pump();
    expect(controls.commands, ['setVolume']);
    expect(controls.requestedVolume, .35);
    controls.command.complete(null);
    await tester.pump();
  });

  for (final refresh in [true, false]) {
    testWidgets(
        'late ${refresh ? 'refresh' : 'command'} error is ignored after dispose',
        (tester) async {
      final controls = _Controls(delayedRefresh: refresh);
      addTearDown(controls.close);
      final errors = <Object>[];
      await tester.pumpWidget(_app(controls, onError: errors.add));
      await tester.pump();
      if (!refresh) {
        await tester.tap(find.text(_strings.ui('playComfort')));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      (refresh ? controls.refresh : controls.command)
          .completeError(StateError('offline'));
      await tester.pump();
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

final _strings = AppStrings(const Locale('tr'));

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text(_strings.ui(label)),
        matching: find.byType(ChoiceChip),
      ),
    );

Widget _app(_Controls controls, {ValueChanged<Object>? onError}) => MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomControlsPanel(
            controls: controls,
            session: _session,
            onError: onError,
          ),
        ),
      ),
    );

const _session = PairingSession(
  payload: PairingPayload(
    schemaVersion: 2,
    host: '127.0.0.1',
    port: 8080,
    deviceId: 'room',
    deviceName: 'Room',
    pairingNonce: 'nonce',
    expiresAtMs: 9999999999999,
    capabilities: {},
  ),
  sessionToken: 'token',
);

class _Controls extends ClientRoomControls {
  _Controls({bool playing = false, this.delayedRefresh = false})
      : snapshot = ClientRoomControlSnapshot(
          comfort: ComfortAudioState.initial().copyWith(
            playing: playing,
            trackId: 'rain',
            volume: .8,
          ),
        );

  final bool delayedRefresh;
  final updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  final refresh = Completer<ComfortAudioState?>();
  final command = Completer<ComfortAudioState?>();
  ClientRoomControlSnapshot snapshot;
  final commands = <String>[];
  String? requestedTrack;
  double? requestedVolume;

  @override
  ClientRoomControlSnapshot get currentState => snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => updates.stream;

  void emit(ClientRoomControlSnapshot state) {
    snapshot = state;
    updates.add(state);
  }

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      delayedRefresh ? refresh.future : snapshot.comfort;

  @override
  Future<ComfortAudioState?> setComfort(PairingSession session,
      {required String action, String? trackId, double? volume, bool? loop}) {
    commands.add(action);
    requestedTrack = trackId;
    requestedVolume = volume;
    return command.future;
  }

  @override
  Future<void> stopTalking() async {}

  Future<void> close() => updates.close();
}
