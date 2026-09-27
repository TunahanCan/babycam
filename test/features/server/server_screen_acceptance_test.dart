import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/features/server/presentation/server_preview_section.dart';
import 'package:miucam/features/server/server_home_screen.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  testWidgets(
      'room preview fullscreen fit and back keep ownership until leaving preview',
      (tester) async {
    var cameraStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async {},
        onStopVideo: () async => cameraStops++,
      ),
      onStartPairing: () async => _ticket(),
      previewSource: () => _PreviewSource(),
    );
    try {
      await tester.pumpWidget(await _app(runtime));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('server-local-preview-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(runtime.currentState.cameraActive, isTrue);
      final fullscreen = find.byTooltip(_strings.ui('serverPreviewFullScreen'));
      await tester.ensureVisible(fullscreen);
      await tester.tap(fullscreen);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ServerFullscreenPreview), findsOneWidget);
      await tester.tap(find.byTooltip(_strings.ui('videoFitContain')));
      await tester.pump();
      expect(
          tester
              .widget<ServerFullscreenPreview>(
                  find.byType(ServerFullscreenPreview))
              .fit,
          BoxFit.contain);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ServerFullscreenPreview), findsNothing);
      expect(runtime.currentState.localPreviewActive, isTrue);
      await tester.tap(find.text('QR/IP'));
      await tester.pumpAndSettle();
      expect(runtime.currentState.localPreviewActive, isFalse);
      expect(runtime.currentState.cameraActive, isFalse);
      expect(cameraStops, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await runtime.dispose();
    }
  });

  testWidgets('room stream stop requires confirmation and releases both tracks',
      (tester) async {
    var cameraStops = 0;
    var microphoneStops = 0;
    var hostStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async {},
        onStopVideo: () async => cameraStops++,
        onStartAudio: () async {},
        onStopAudio: () async => microphoneStops++,
      ),
      onStartPairing: () async => _ticket(),
      onStop: () async => hostStops++,
    );
    try {
      await runtime.startStreamSession(
          'parent', const StreamSessionOptions(video: true, audio: true));
      await tester.pumpWidget(await _app(runtime));
      await tester.pumpAndSettle();
      await _openStopConfirmation(tester);
      await _tap(tester, find.text(_strings.ui('cancel')));
      expect(hostStops, 0);
      expect(runtime.currentState.cameraActive, isTrue);
      expect(runtime.currentState.microphoneActive, isTrue);
      await _openStopConfirmation(tester);
      await _tap(tester, _confirmStop());
      expect(hostStops, 1);
      expect(cameraStops, 1);
      expect(microphoneStops, 1);
      expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
      expect(runtime.currentState.activeClients, 0);
      expect(runtime.currentState.cameraActive, isFalse);
      expect(runtime.currentState.microphoneActive, isFalse);
      expect(find.text(_strings.ui('stopRoomStream')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await runtime.dispose();
    }
  });

  testWidgets('room stop cannot be confirmed again while teardown is pending',
      (tester) async {
    final stop = Completer<void>();
    var hostStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => _ticket(),
      onStop: () async {
        hostStops++;
        await stop.future;
      },
    );
    try {
      await tester.pumpWidget(await _app(runtime));
      await tester.pumpAndSettle();
      await _openStopConfirmation(tester);
      await _tap(tester, _confirmStop());
      expect(hostStops, 1);
      final stopButton = find.ancestor(
          of: find.text(_strings.ui('stopRoomStream')),
          matching: find.byType(TextButton));
      expect(tester.widget<TextButton>(stopButton).onPressed, isNull);
      await _tap(tester, stopButton);
      expect(find.byType(BottomSheet), findsNothing);
      expect(hostStops, 1);
      stop.complete();
      await tester.pumpAndSettle();
      expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
    } finally {
      if (!stop.isCompleted) stop.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await runtime.dispose();
    }
  });
  testWidgets('failed room shutdown reports a calm error and can be retried',
      (tester) async {
    var hostStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async => _ticket(),
      onStop: () async {
        hostStops++;
        if (hostStops == 1) throw StateError('INTERNAL_CLOSE_FAILURE');
      },
    );
    try {
      await tester.pumpWidget(await _app(runtime));
      await tester.pumpAndSettle();
      await _openStopConfirmation(tester);
      await _tap(tester, _confirmStop());
      expect(find.textContaining('INTERNAL_CLOSE_FAILURE'), findsNothing);
      expect(find.text(_strings.ui('stopRoomStreamFailed')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _openStopConfirmation(tester);
      await _tap(tester, _confirmStop());
      expect(hostStops, 2);
      expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
      expect(find.text(_strings.ui('stopRoomStream')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await runtime.dispose();
    }
  });
}

final _strings = AppStrings(const Locale('tr'));

Future<Widget> _app(ServerRuntime runtime) async => MaterialApp(
      locale: const Locale('tr'),
      theme: MiuCamTheme.serverTheme(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(await SharedPreferences.getInstance()),
          activeRole: AppRole.server,
          onRoleSelected: (_) {}),
    );

Future<void> _openStopConfirmation(WidgetTester tester) =>
    _tap(tester, find.text(_strings.ui('stopRoomStream')));

Finder _confirmStop() => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text(_strings.ui('stopRoomStream')));

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 250,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

String _ticket() => PairingPayload(
    schemaVersion: 2,
    host: '192.168.1.20',
    port: 8080,
    deviceId: 'room',
    deviceName: 'Room',
    pairingNonce: 'nonce',
    expiresAtMs:
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    capabilities: const {}).toUriString();

class _PreviewSource implements ServerJpegPreviewSource {
  @override
  Uint8List? get latestPreviewFrame => null;
  @override
  Stream<Uint8List> get previewFrames => const Stream.empty();
}
