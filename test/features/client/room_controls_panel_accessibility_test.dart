import 'dart:async';
import 'dart:ui' as ui;

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
  testWidgets('ekran okuyucu konuşmayı başlatıp durdurabilir', (tester) async {
    final semantics = tester.ensureSemantics();
    final controls = _AccessibleRoomControls();
    addTearDown(controls.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: RoomControlsPanel(
            controls: controls,
            session: _session(),
          ),
        ),
      ),
    );
    await tester.pump();

    var node = tester.getSemantics(
      find.bySemanticsLabel('Konuşmak için basılı tut'),
    );
    var data = node.getSemanticsData();
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isToggled, ui.Tristate.isFalse);

    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
    await tester.pump();

    expect(controls.startCalls, 1);
    node = tester.getSemantics(
      find.bySemanticsLabel('Ses odaya gönderiliyor'),
    );
    data = node.getSemanticsData();
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isToggled, ui.Tristate.isTrue);

    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
    await tester.pump();

    expect(controls.stopCalls, 1);
    semantics.dispose();
  });
}

class _AccessibleRoomControls extends ClientRoomControls {
  final _updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  ClientRoomControlSnapshot _snapshot = const ClientRoomControlSnapshot();
  int startCalls = 0;
  int stopCalls = 0;

  @override
  ClientRoomControlSnapshot get currentState => _snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => _updates.stream;

  @override
  Future<void> startTalking(PairingSession session) async {
    startCalls++;
    _snapshot = const ClientRoomControlSnapshot(talking: true);
    _updates.add(_snapshot);
  }

  @override
  Future<void> stopTalking() async {
    stopCalls++;
    _snapshot = const ClientRoomControlSnapshot(talking: false);
    _updates.add(_snapshot);
  }

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      null;

  Future<void> close() => _updates.close();
}

PairingSession _session() => PairingSession(
      payload: PairingPayload(
        schemaVersion: 2,
        host: '127.0.0.1',
        port: 8080,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'token',
      clientId: 'client',
    );
