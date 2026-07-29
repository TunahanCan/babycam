import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/controls/room_controls_panel.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/role_selection/role_selection_screen.dart';
import 'package:miucam/features/shared/presentation/miucam_design_tokens.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets('seçili dil ve oda rolü küçük metinde AA kontrastı sağlar',
      (tester) async {
    await tester.pumpWidget(
      _LocalizedApp(
        home: RoleSelectionScreen(onRoleSelected: (_) {}),
      ),
    );

    final roomBadge = tester.widget<Text>(find.text('BEBEK ODASI'));
    expect(
      _contrastRatio(
        roomBadge.style!.color!,
        const Color(0xFFECF7F4),
      ),
      greaterThanOrEqualTo(4.5),
    );

    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);
    await tester.pumpWidget(
      _LocalizedApp(
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          initialTab: 3,
          selectedLocale: const Locale('tr'),
        ),
      ),
    );

    final languageLabel = tester.widget<Text>(find.text('Türkçe'));
    expect(
      _contrastRatio(
        languageLabel.style!.color!,
        MiuCamDesignTokens.mintSoft,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('uyarı zamanlarının kategori renkleri AA kontrastı sağlar',
      (tester) async {
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);
    await runtime.recordAlert(
      _alert('audio', 'cryDetected', DateTime(2026, 7, 29, 12, 10)),
    );
    await runtime.recordAlert(
      _alert('motion', 'motionDetected', DateTime(2026, 7, 29, 12, 20)),
    );
    await runtime.recordAlert(
      _alert('system', 'batteryLow', DateTime(2026, 7, 29, 12, 30)),
    );

    await tester.pumpWidget(
      _LocalizedApp(home: WatchScreen(runtime: runtime, initialTab: 1)),
    );
    await tester.pumpAndSettle();

    for (final time in ['12:10', '12:20', '12:30']) {
      final timeText = tester.widget<Text>(find.text(time));
      expect(
        _contrastRatio(timeText.style!.color!, Colors.white),
        greaterThanOrEqualTo(4.5),
        reason: '$time zaman etiketi beyaz kart üzerinde okunabilir olmalı.',
      );
    }
  });

  testWidgets('istemci ve izleme filtreleri en az 48dp dokunma hedefidir',
      (tester) async {
    final runtime = ClientRuntime(pair: (_) => throw UnimplementedError());
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _LocalizedApp(
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
          initialTab: 2,
        ),
      ),
    );
    await tester.pump();
    _expectFilterTargetsAtLeast48(tester);

    await tester.pumpWidget(
      _LocalizedApp(home: WatchScreen(runtime: runtime, initialTab: 1)),
    );
    await tester.pumpAndSettle();
    _expectFilterTargetsAtLeast48(tester);
  });

  testWidgets('konfor chipleri 48dp ve aktif bas-konuş metni AA uyumludur',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controls = _VisualRoomControls();
    addTearDown(controls.close);

    await tester.pumpWidget(
      _LocalizedApp(
        home: Scaffold(
          body: RoomControlsPanel(
            controls: controls,
            session: _session(),
          ),
        ),
      ),
    );
    await tester.pump();

    final chips = find.byType(ChoiceChip);
    expect(chips, findsWidgets);
    for (var index = 0; index < chips.evaluate().length; index++) {
      expect(
        tester.getSize(chips.at(index)).height,
        greaterThanOrEqualTo(48),
      );
    }

    final talkingText = find.text('Ses odaya gönderiliyor');
    final activeSurface = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: talkingText,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final activeColor = (activeSurface.decoration! as BoxDecoration).color!;
    expect(
      _contrastRatio(Colors.white, activeColor),
      greaterThanOrEqualTo(4.5),
    );
  });
}

void _expectFilterTargetsAtLeast48(WidgetTester tester) {
  for (final label in ['Tümü', 'Ses', 'Hareket', 'Sistem']) {
    final target = find.ancestor(
      of: find.text(label).first,
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSize(target).height,
      greaterThanOrEqualTo(48),
      reason: '$label filtresinin dokunma hedefi en az 48dp olmalı.',
    );
  }
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

AlertEventDto _alert(
  String id,
  String type,
  DateTime timestamp,
) =>
    AlertEventDto(
      id: id,
      type: type,
      severity: 'info',
      messageKey: 'testMessage',
      message: '$id alert',
      score: 0,
      timestampMs: timestamp.millisecondsSinceEpoch,
      sourceDeviceId: 'server',
    );

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

class _VisualRoomControls extends ClientRoomControls {
  final _updates = StreamController<ClientRoomControlSnapshot>.broadcast();
  final _snapshot = ClientRoomControlSnapshot(
    comfort: ComfortAudioState.initial(),
    talking: true,
  );

  @override
  ClientRoomControlSnapshot get currentState => _snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => _updates.stream;

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async =>
      _snapshot.comfort;

  Future<void> close() => _updates.close();
}

class _LocalizedApp extends StatelessWidget {
  const _LocalizedApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
}
