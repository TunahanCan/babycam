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

  testWidgets('başlatma sürerken panel kapanırsa konuşmayı sırayla durdurur',
      (tester) async {
    final controls = _DelayedRoomControls();
    addTearDown(controls.close);

    await tester.pumpWidget(
      _app(
        RoomControlsPanel(
          controls: controls,
          session: _session(),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Konuşmak için basılı tut')),
    );
    await tester.pump();
    expect(controls.startCalls, 1);

    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump();

    expect(
      controls.stopCalls,
      1,
      reason: 'Panel teardown must request stop even before talking=true.',
    );
    expect(
      controls.events,
      const ['start-requested', 'stop-requested'],
    );

    controls.completeStart();
    await tester.pump();
    await tester.pump();
    expect(
      controls.events,
      const [
        'start-requested',
        'stop-requested',
        'start-completed',
        'stop-completed',
      ],
    );
    await gesture.cancel();
  });

  testWidgets('panel kapandıktan sonra gelen start hatasını yüzeye taşımaz',
      (tester) async {
    final controls = _DelayedRoomControls(
      startError: const RoomMicrophonePermissionException(),
    );
    addTearDown(controls.close);
    var errorCallbacks = 0;

    await tester.pumpWidget(
      _app(
        RoomControlsPanel(
          controls: controls,
          session: _session(),
          onError: (_) => errorCallbacks++,
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Konuşmak için basılı tut')),
    );
    await tester.pump();
    await tester.pumpWidget(_app(const SizedBox.shrink()));
    await tester.pump();

    controls.completeStart();
    await tester.pump();
    await tester.pump();

    expect(errorCallbacks, 0);
    expect(tester.takeException(), isNull);
    await gesture.cancel();
  });

  testWidgets(
      'pointer up takılan startı UI sahipliğinden çıkarır ve successorı açar',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controls = _RestartableDelayedRoomControls();
    addTearDown(controls.close);
    var errorCallbacks = 0;

    await tester.pumpWidget(
      _app(
        RoomControlsPanel(
          controls: controls,
          session: _session(),
          onError: (_) => errorCallbacks++,
        ),
      ),
    );
    await tester.pump();

    final label = find.text('Konuşmak için basılı tut');
    final first = await tester.startGesture(tester.getCenter(label));
    await tester.pump();

    expect(controls.startCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    var node = tester.getSemantics(
      find.bySemanticsLabel('Konuşmak için basılı tut'),
    );
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
      reason: 'Screen readers must be able to cancel a pending start.',
    );

    await first.up();
    await tester.pump();

    expect(controls.stopCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    node = tester.getSemantics(
      find.bySemanticsLabel('Konuşmak için basılı tut'),
    );
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);

    final second = await tester.startGesture(tester.getCenter(label));
    await tester.pump();

    expect(controls.startCalls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controls.failStart(
      0,
      const RoomMicrophonePermissionException(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'A late first start must not clear successor busy ownership.',
    );
    expect(errorCallbacks, 0);

    await second.up();
    await tester.pump();
    expect(controls.stopCalls, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    controls.completeStart(1);
    await tester.pump();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('uygulama arka plana gidince kilitli konuşmayı durdurur',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controls = _AccessibleRoomControls();
    addTearDown(controls.close);

    await tester.pumpWidget(
      _app(
        RoomControlsPanel(
          controls: controls,
          session: _session(),
        ),
      ),
    );
    await tester.pump();

    final node = tester.getSemantics(
      find.bySemanticsLabel('Konuşmak için basılı tut'),
    );
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
    expect(controls.startCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();

    expect(controls.stopCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    semantics.dispose();
  });
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

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

class _DelayedRoomControls extends ClientRoomControls {
  _DelayedRoomControls({this.startError});

  final Object? startError;
  final _updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  final _startRelease = Completer<void>();
  final events = <String>[];
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
    events.add('start-requested');
    await _startRelease.future;
    final error = startError;
    if (error != null) throw error;
    events.add('start-completed');
    _snapshot = const ClientRoomControlSnapshot(talking: true);
    if (!_updates.isClosed) _updates.add(_snapshot);
  }

  @override
  Future<void> stopTalking() async {
    stopCalls++;
    events.add('stop-requested');
    await _startRelease.future;
    events.add('stop-completed');
    _snapshot = const ClientRoomControlSnapshot(talking: false);
    if (!_updates.isClosed) _updates.add(_snapshot);
  }

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      null;

  void completeStart() {
    if (!_startRelease.isCompleted) _startRelease.complete();
  }

  Future<void> close() async {
    completeStart();
    await _updates.close();
  }
}

class _RestartableDelayedRoomControls extends ClientRoomControls {
  final _updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  final _starts = <Completer<void>>[];
  int startCalls = 0;
  int stopCalls = 0;

  @override
  ClientRoomControlSnapshot get currentState =>
      const ClientRoomControlSnapshot();

  @override
  Stream<ClientRoomControlSnapshot> get states => _updates.stream;

  @override
  Future<void> startTalking(PairingSession session) {
    startCalls++;
    final operation = Completer<void>();
    _starts.add(operation);
    return operation.future;
  }

  @override
  Future<void> stopTalking() async {
    stopCalls++;
  }

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      null;

  void completeStart(int index) {
    final operation = _starts[index];
    if (!operation.isCompleted) operation.complete();
  }

  void failStart(int index, Object error) {
    final operation = _starts[index];
    if (!operation.isCompleted) operation.completeError(error);
  }

  Future<void> close() async {
    for (final operation in _starts) {
      if (!operation.isCompleted) operation.complete();
    }
    await _updates.close();
  }
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
