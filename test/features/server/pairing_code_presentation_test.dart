import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/presentation/server_pairing_section.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  for (final language in ['tr', 'en', 'de', 'fr', 'es', 'zh', 'hi', 'ar']) {
    testWidgets('pairing code remains readable and updates in $language',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final updates = StreamController<void>.broadcast();
      String? code = '012345';
      final expiresAt = DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch;
      final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        pairingCode: () => code,
        pairingCodeExpiresAtMs: () => expiresAt,
        trustedClientsChanged: updates.stream,
      );
      final state = ServerRuntimeState(
        phase: ServerRuntimePhase.pairingActive,
        qrPayload: PairingPayload(
          schemaVersion: MiuCamProtocolV2.schemaVersion,
          host: '192.168.1.20',
          port: 8080,
          deviceId: 'room',
          deviceName: 'Room',
          pairingNonce: 'private-qr-nonce',
          expiresAtMs: expiresAt,
          capabilities: const {},
        ).toUriString(),
      );
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
              body: SingleChildScrollView(
            child: ServerPairingSection(runtime: runtime, state: state),
          )),
        ),
      ));
      await tester.pump();
      final visibleCode =
          tester.widget<Text>(find.byKey(const ValueKey('room-pairing-code')));
      expect(visibleCode.data, '012345');
      expect(visibleCode.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
      code = '987654';
      updates.add(null);
      await tester.pumpAndSettle();
      expect(find.text('012345'), findsNothing);
      expect(find.text('987654'), findsOneWidget);
      code = null;
      updates.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-pairing-code')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await updates.close();
      await runtime.dispose();
    });
  }
}
