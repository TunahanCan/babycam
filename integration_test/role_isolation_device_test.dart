// Run only through the existing-app workflow in role_isolation_device.md.
// Default `flutter drive` uninstalls the application after the test; in-memory
// storage below does not protect data from that external runner cleanup.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:miucam/app/install_integrity_guard.dart';
import 'package:miucam/app/miucam_app.dart';
import 'package:miucam/app/role_repository.dart';
import 'package:miucam/core/feature_flags.dart';
import 'package:miucam/features/client/client_app_shell.dart';
import 'package:miucam/features/client/client_composition_root.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/features/server/server_app_shell.dart';
import 'package:miucam/features/server/server_composition_root.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/features/shared/presentation/miucam_shells.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/platform/platform_runtime_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final cycles = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'validation': 'role_isolation_real_android_capture',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'operatingSystemVersion': Platform.operatingSystemVersion,
    'storage': 'isolated in-memory preferences and secure tokens',
    'media': 'live native capture, no recording or media export',
    'cycles': cycles,
    'passed': false,
  };
  binding.reportData = report;

  testWidgets('client and server remain exclusive through two native cycles',
      (tester) async {
    expect(Platform.isAndroid, isTrue);
    expect(MiuCamFeatureFlags.broadcastPaywallEnabled, isFalse,
        reason: 'Use --dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=false.');
    // Isolate Dart-side writes from persisted preferences and pairing tokens.
    // Camera, microphone, service, discovery and runtime channels remain real.
    SharedPreferences.setMockInitialValues({
      InstallIntegrityGuard.markerKey: true,
      SharedPreferencesRoleRepository.storageKey: 'client',
    });
    FlutterSecureStorage.setMockInitialValues({});
    const platform = PlatformRuntimeContract();
    final initialServerCount = ServerCompositionRoot.createCount;
    final initialClientCount = ClientCompositionRoot.createCount;
    ServerRuntime? activeServer;

    try {
      await tester.pumpWidget(const MiuCamApp());
      await _waitFor(
          tester,
          () => find.byType(ClientAppShell).evaluate().isNotEmpty,
          'initial client screen');
      expect(ServerCompositionRoot.createCount, initialServerCount);
      expect(ClientCompositionRoot.createCount, initialClientCount + 1);
      report['initialNative'] = _flags(await platform.snapshot());

      for (var index = 0; index < 2; index++) {
        final cycle = <String, Object?>{'cycle': index + 1, 'passed': false};
        cycles.add(cycle);
        await tester.tap(find.byType(MiuCamRoleBadge).hitTestable().first);
        await _waitFor(
            tester,
            () => find.byType(ServerAppShell).evaluate().isNotEmpty,
            'server screen');
        expect(find.byType(ClientAppShell), findsNothing);
        expect(
            ServerCompositionRoot.createCount, initialServerCount + index + 1);
        expect(
            ClientCompositionRoot.createCount, initialClientCount + index + 1);

        activeServer =
            tester.widget<ServerAppShell>(find.byType(ServerAppShell)).runtime;
        final server = activeServer;
        await server.startLocalPreview();
        await server.startStreamSession('device-role-isolation-$index',
            const StreamSessionOptions(video: true, audio: true));
        final started = await _waitForNative(
            tester,
            platform,
            (state) =>
                state.nativeCameraActive &&
                state.nativeMicrophoneActive &&
                state.foregroundServiceActive &&
                state.serverDemand,
            'native camera and microphone acquisition');
        cycle['nativeDuringServer'] = _flags(started);
        final source = server.previewSource;
        if (source is ServerMediaSource) {
          await _waitFor(
              tester,
              () =>
                  source.snapshot.videoFrames > 0 &&
                  source.snapshot.audioChunks > 0,
              'native video frames and microphone chunks');
          cycle['capturedVideoFrames'] = source.snapshot.videoFrames;
          cycle['capturedAudioChunks'] = source.snapshot.audioChunks;
        }
        expect(server.currentState.cameraActive, isTrue);
        expect(server.currentState.microphoneActive, isTrue);

        final switching = Stopwatch()..start();
        await tester.tap(find.byType(MiuCamRoleBadge).hitTestable().first);
        await _waitFor(
            tester,
            () => find.byType(BottomSheet).evaluate().isNotEmpty,
            'leave-server confirmation');
        final strings = AppStrings.of(tester.element(find.byType(BottomSheet)));
        final confirm =
            find.widgetWithText(FilledButton, strings.ui('switchToClient'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(confirm);
        await tester.pump(const Duration(milliseconds: 100));
        await _waitFor(
            tester,
            () => confirm.hitTestable().evaluate().isNotEmpty,
            'visible leave-server confirmation action');
        await tester.tap(confirm.hitTestable());
        await _waitFor(
            tester,
            () => find.byType(ClientAppShell).evaluate().isNotEmpty,
            'client screen after native shutdown');
        final stopped = await _waitForNative(
            tester,
            platform,
            (state) => !state.hasActiveRoleResources,
            'complete native shutdown');
        cycle['switchDurationMs'] = switching.elapsedMilliseconds;
        cycle['nativeAfterClient'] = _flags(stopped);
        expect(find.byType(ServerAppShell), findsNothing);
        expect(server.currentState.phase, ServerRuntimePhase.stopped);
        expect(server.currentState.cameraActive, isFalse);
        expect(server.currentState.microphoneActive, isFalse);
        expect(
            ServerCompositionRoot.createCount, initialServerCount + index + 1);
        expect(
            ClientCompositionRoot.createCount, initialClientCount + index + 2);
        expect(tester.takeException(), isNull);

        // A late acquisition/recovery callback must not reactivate the old role.
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect((await platform.snapshot()).hasActiveRoleResources, isFalse);
        cycle['passed'] = true;
        activeServer = null;
      }
      report['passed'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await activeServer?.dispose();
      final idle = await _waitForNative(tester, platform,
          (state) => !state.hasActiveRoleResources, 'final native cleanup');
      report['finalNative'] = _flags(idle);
      binding.reportData = report;
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _waitFor(
    WidgetTester tester, bool Function() ready, String label) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
    final error = tester.takeException();
    if (error != null) throw StateError('$label: $error');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Timed out waiting for $label.');
}

Future<PlatformRuntimeSnapshot> _waitForNative(
    WidgetTester tester,
    PlatformRuntimeContract platform,
    bool Function(PlatformRuntimeSnapshot) ready,
    String label) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  PlatformRuntimeSnapshot? snapshot;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    snapshot = await platform.snapshot();
    if (ready(snapshot)) return snapshot;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
      'Timed out waiting for $label: ${snapshot == null ? 'no native snapshot' : _flags(snapshot)}');
}

Map<String, Object?> _flags(PlatformRuntimeSnapshot state) => {
      'platform': state.platform.name,
      'applicationState': state.applicationState,
      'foregroundServiceActive': state.foregroundServiceActive,
      'serverDemand': state.serverDemand,
      'alertDemand': state.alertDemand,
      'cameraDemand': state.cameraDemand,
      'microphoneDemand': state.microphoneDemand,
      'playbackDemand': state.playbackDemand,
      'audioOutputActive': state.audioOutputActive,
      'nativeCameraRequested': state.nativeCameraRequested,
      'nativeMicrophoneRequested': state.nativeMicrophoneRequested,
      'nativeCameraActive': state.nativeCameraActive,
      'nativeMicrophoneActive': state.nativeMicrophoneActive,
      'nativeCameraError': state.nativeCameraError,
      'nativeMicrophoneError': state.nativeMicrophoneError,
      'hasActiveRoleResources': state.hasActiveRoleResources,
    };
