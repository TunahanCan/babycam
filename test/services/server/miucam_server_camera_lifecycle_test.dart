import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform originalCameraPlatform;
  late _LeaseCameraPlatform cameraPlatform;
  late MiuCamServer server;

  setUp(() async {
    originalCameraPlatform = CameraPlatform.instance;
    cameraPlatform = _LeaseCameraPlatform();
    CameraPlatform.instance = cameraPlatform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      mediaPermissions: const _GrantedMediaPermissions(),
      deviceTier: DeviceCapabilityTier.balanced,
      mediaLifecycleOperationTimeout: const Duration(milliseconds: 30),
    );
  });

  tearDown(() async {
    cameraPlatform.releaseAllInitializations();
    try {
      await server.stopVideoRuntime();
    } catch (_) {}
    await server.dispose();
    await cameraPlatform.close();
    CameraPlatform.instance = originalCameraPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test('stopped hanging start does not capture successor start lease',
      () async {
    cameraPlatform.hangInitializeCall(1);
    final firstStart = server.startVideoRuntime();
    await _waitUntil(() => cameraPlatform.initializeCalls == 1);

    final stopping = server.stopVideoRuntime();
    final successorStart = server.startVideoRuntime();
    await successorStart.timeout(const Duration(seconds: 1));

    expect(await _errorOf(firstStart), isA<TimeoutException>());
    expect(await _errorOf(stopping), isA<TimeoutException>());
    expect(server.cameraController?.value.isInitialized, isTrue);
    expect(cameraPlatform.initializeCalls, 2);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(2)));

    cameraPlatform.releaseInitializeCall(1);
    await _waitUntil(() => cameraPlatform.disposedCameraIds.contains(1));

    expect(server.cameraController?.value.isInitialized, isTrue);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(2)));
  });

  test('stop during profile initialize disposes only stale profile controller',
      () async {
    await server.startVideoRuntime();
    expect(cameraPlatform.initializeCalls, 1);

    cameraPlatform.hangInitializeCall(2);
    final profileRestart = server.restartCameraWithProfileForTesting(
      server.activeMediaProfile.copyWith(
        id: 'test_low_profile',
        cameraPresetKey: 'low',
      ),
    );
    await _waitUntil(() => cameraPlatform.initializeCalls == 2);

    final stopping = server.stopVideoRuntime();
    final successorStart = server.startVideoRuntime();
    await successorStart.timeout(const Duration(seconds: 1));

    expect(await _errorOf(profileRestart), isA<TimeoutException>());
    expect(await _errorOf(stopping), isA<TimeoutException>());
    expect(cameraPlatform.initializeCalls, 3);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(3)));

    cameraPlatform.releaseInitializeCall(2);
    await _waitUntil(() => cameraPlatform.disposedCameraIds.contains(2));

    expect(server.cameraController?.value.isInitialized, isTrue);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(3)));
  });

  test('failed native dispose is retried with the exact camera lease',
      () async {
    cameraPlatform.failDisposeCall(1);
    await server.startVideoRuntime();

    final stopping = server.stopVideoRuntime();
    expect(await _errorOf(stopping), isA<TimeoutException>());
    expect(cameraPlatform.disposeCalls, 1);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(1)));

    await _waitUntil(() => cameraPlatform.disposeCalls >= 2);
    expect(cameraPlatform.disposedCameraIds, contains(1));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cameraPlatform.disposeCalls, 2);

    await server.startVideoRuntime();
    expect(cameraPlatform.initializeCalls, 2);
    expect(server.cameraController?.value.isInitialized, isTrue);
    expect(cameraPlatform.disposedCameraIds, isNot(contains(2)));
  });
}

Future<Object?> _errorOf(Future<void> operation) async {
  try {
    await operation;
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      fail('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _GrantedMediaPermissions implements MediaPermissionGateway {
  const _GrantedMediaPermissions();

  @override
  Future<bool> requestCamera() async => true;
}

class _LeaseCameraPlatform extends CameraPlatform {
  final _initializeEvents = <int, StreamController<CameraInitializedEvent>>{};
  final _errorEvents = <int, StreamController<CameraErrorEvent>>{};
  final _frameEvents = <int, StreamController<CameraImageData>>{};
  final _initializeReleases = <int, Completer<void>>{};
  final _failingDisposeCalls = <int>{};
  final disposedCameraIds = <int>{};
  int _nextCameraId = 0;
  int initializeCalls = 0;
  int disposeCalls = 0;

  void hangInitializeCall(int call) {
    _initializeReleases[call] = Completer<void>();
  }

  void releaseInitializeCall(int call) {
    final release = _initializeReleases[call];
    if (release != null && !release.isCompleted) release.complete();
  }

  void releaseAllInitializations() {
    for (final release in _initializeReleases.values) {
      if (!release.isCompleted) release.complete();
    }
  }

  void failDisposeCall(int call) {
    _failingDisposeCalls.add(call);
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(
          name: 'test-camera',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ];

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    final cameraId = ++_nextCameraId;
    _initializeEvents[cameraId] =
        StreamController<CameraInitializedEvent>.broadcast();
    _errorEvents[cameraId] = StreamController<CameraErrorEvent>.broadcast();
    _frameEvents[cameraId] = StreamController<CameraImageData>.broadcast();
    return cameraId;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    final call = ++initializeCalls;
    final release = _initializeReleases[call];
    if (release != null) await release.future;
    _initializeEvents[cameraId]!.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initializeEvents[cameraId]!.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errorEvents[cameraId]!.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) =>
      _frameEvents[cameraId]!.stream;

  @override
  Future<void> dispose(int cameraId) async {
    final call = ++disposeCalls;
    if (_failingDisposeCalls.remove(call)) {
      throw StateError('dispose failed on call $call');
    }
    disposedCameraIds.add(cameraId);
  }

  Future<void> close() async {
    for (final controller in [
      ..._initializeEvents.values,
      ..._frameEvents.values,
    ]) {
      if (!controller.isClosed) await controller.close();
    }
  }
}
