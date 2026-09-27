import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/presentation/server_pairing_section.dart';
import 'package:miucam/features/server/presentation/server_services_section.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets('platform status polling stops in background and resumes once',
      (tester) async {
    const channel = MethodChannel('miucam/platform_runtime');
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'snapshot') reads++;
      return {'platform': 'android', 'foregroundServiceActive': true};
    });
    _foreground(tester);
    try {
      await tester.pumpWidget(_app(const ServerServicesSection(
          state: ServerRuntimeState(phase: ServerRuntimePhase.stopped))));
      await tester.pump();
      expect(reads, 1);
      _background(tester);
      await tester.pump(const Duration(seconds: 20));
      expect(reads, 1,
          reason: 'A hidden diagnostics card must not poll native state.');
      _foreground(tester);
      await tester.pump();
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 3, reason: 'Resume must create only one polling timer.');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
      expect(reads, 3);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      _foreground(tester);
    }
  });

  testWidgets('an expired QR mounted in background refreshes only on resume',
      (tester) async {
    final runtime = _PairingRuntime();
    final state = ServerRuntimeState(
        phase: ServerRuntimePhase.pairingActive,
        qrPayload: _ticket(expiresIn: const Duration(seconds: -1)));
    _background(tester);
    try {
      await tester.pumpWidget(
          _app(ServerPairingSection(runtime: runtime, state: state)));
      await tester.pump();
      expect(runtime.refreshes, 0);
      _foreground(tester);
      await tester.pump();
      await tester.pump();
      expect(runtime.refreshes, 1);
      await tester.pump(const Duration(seconds: 20));
      expect(runtime.refreshes, 1,
          reason: 'The same expired ticket is not retried in a loop.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
      _foreground(tester);
    }
  });

  testWidgets(
      'a native response from before background cannot replace resumed status',
      (tester) async {
    const channel = MethodChannel('miucam/platform_runtime');
    final oldResponse = Completer<Map<String, Object?>>();
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      reads++;
      if (reads == 1) return oldResponse.future;
      return {'platform': 'android', 'foregroundServiceActive': false};
    });
    _foreground(tester);
    final strings = AppStrings(const Locale('tr'));
    try {
      await tester.pumpWidget(_app(const ServerServicesSection(
          state: ServerRuntimeState(phase: ServerRuntimePhase.stopped))));
      await tester.pump();
      _background(tester);
      _foreground(tester);
      await tester.pump();
      expect(reads, 1,
          reason: 'Lifecycle changes do not overlap native requests.');
      oldResponse
          .complete({'platform': 'android', 'foregroundServiceActive': true});
      await tester.pump();
      expect(
          find.text(strings.ui('androidServiceActiveContract')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(reads, 2);
      expect(find.text(strings.ui('androidServiceInactiveContract')),
          findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      _foreground(tester);
    }
  });

  testWidgets('QR expiry timer is canceled while the app is backgrounded',
      (tester) async {
    final runtime = _PairingRuntime();
    final state = ServerRuntimeState(
        phase: ServerRuntimePhase.pairingActive,
        qrPayload: _ticket(expiresIn: const Duration(seconds: 2)));
    _foreground(tester);
    try {
      await tester.pumpWidget(
          _app(ServerPairingSection(runtime: runtime, state: state)));
      await tester.pump();
      _background(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(runtime.refreshes, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
      _foreground(tester);
    }
  });
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('tr'),
      theme: MiuCamTheme.serverTheme(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

class _PairingRuntime extends ServerRuntime {
  _PairingRuntime() : super(mediaRuntime: MediaRuntimeController());
  int refreshes = 0;
  @override
  bool isPairingNonceActive(String nonce) => true;
  @override
  Future<void> startPairingMode() async => refreshes++;
}

String _ticket({required Duration expiresIn}) => PairingPayload(
    schemaVersion: 2,
    host: '192.168.1.20',
    port: 8080,
    deviceId: 'room',
    deviceName: 'Bebek Odası',
    pairingNonce: 'nonce',
    expiresAtMs: DateTime.now().add(expiresIn).millisecondsSinceEpoch,
    capabilities: const {}).toUriString();

void _background(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) return;
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}
