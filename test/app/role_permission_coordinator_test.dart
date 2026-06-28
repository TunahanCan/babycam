import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/app/role_permission_coordinator.dart';
import 'package:mimicam/core/media/camera_permission_gateway.dart';
import 'package:mimicam/core/network/local_network_permission_gateway.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('RolePermissionPolicy', () {
    test('client için bildirim ve QR kamera izinlerini seçer', () {
      final permissions = const RolePermissionPolicy()
          .permissionsFor(AppRole.client, isAndroid: false);

      expect(permissions, [Permission.notification, Permission.camera]);
    });

    test('server Android için mikrofon ve pil optimizasyon izni ekler', () {
      final permissions = const RolePermissionPolicy()
          .permissionsFor(AppRole.server, isAndroid: true);

      expect(permissions, [
        Permission.notification,
        Permission.camera,
        Permission.microphone,
        Permission.ignoreBatteryOptimizations,
      ]);
    });
  });

  group('RolePermissionCoordinator', () {
    test('yalnızca gerekli izinleri gateway üzerinden ister', () async {
      final gateway = _FakePermissionGateway({
        Permission.notification: PermissionStatus.denied,
        Permission.camera: PermissionStatus.granted,
        Permission.microphone: PermissionStatus.permanentlyDenied,
        Permission.ignoreBatteryOptimizations: PermissionStatus.restricted,
      });
      final coordinator = RolePermissionCoordinator(
        gateway: gateway,
        cameraGateway: _FakeCameraPermissionGateway(),
        localNetworkGateway: _FakeLocalNetworkPermissionGateway(),
        isAndroid: () => true,
      );

      await coordinator.requestFor(AppRole.server);

      expect(gateway.statusChecks, [
        Permission.notification,
        Permission.microphone,
        Permission.ignoreBatteryOptimizations,
      ]);
      expect(gateway.requests, [
        Permission.notification,
        Permission.ignoreBatteryOptimizations,
      ]);
    });

    test('platform gateway hatası rol seçimini kırmaz', () async {
      final coordinator = RolePermissionCoordinator(
        gateway: _ThrowingPermissionGateway(),
        cameraGateway: _FakeCameraPermissionGateway(),
        localNetworkGateway: _FakeLocalNetworkPermissionGateway(),
        isAndroid: () => false,
      );

      await expectLater(coordinator.requestFor(AppRole.client), completes);
    });

    test('yerel ağ iznini rol izinlerinden sonra tetikler', () async {
      final localNetworkGateway = _FakeLocalNetworkPermissionGateway();
      final coordinator = RolePermissionCoordinator(
        gateway: _FakePermissionGateway({
          Permission.notification: PermissionStatus.granted,
        }),
        cameraGateway: _FakeCameraPermissionGateway(
          statusResult: CameraPermissionStatus.granted,
        ),
        localNetworkGateway: localNetworkGateway,
        isAndroid: () => false,
      );

      await coordinator.requestFor(AppRole.client);

      expect(localNetworkGateway.requestCount, 1);
    });

    test('kamera iznini native camera gateway üzerinden ister', () async {
      final cameraGateway = _FakeCameraPermissionGateway();
      final coordinator = RolePermissionCoordinator(
        gateway: _FakePermissionGateway({
          Permission.notification: PermissionStatus.granted,
        }),
        cameraGateway: cameraGateway,
        localNetworkGateway: _FakeLocalNetworkPermissionGateway(),
        isAndroid: () => false,
      );

      await coordinator.requestFor(AppRole.client);

      expect(cameraGateway.statusCalls, 1);
      expect(cameraGateway.requestCalls, 1);
    });
  });
}

class _FakePermissionGateway implements PermissionGateway {
  _FakePermissionGateway(this._statuses);

  final Map<Permission, PermissionStatus> _statuses;
  final statusChecks = <Permission>[];
  final requests = <Permission>[];

  @override
  Future<PermissionStatus> status(Permission permission) async {
    statusChecks.add(permission);
    return _statuses[permission] ?? PermissionStatus.denied;
  }

  @override
  Future<PermissionStatus> request(Permission permission) async {
    requests.add(permission);
    return PermissionStatus.granted;
  }
}

class _ThrowingPermissionGateway implements PermissionGateway {
  @override
  Future<PermissionStatus> status(Permission permission) async {
    throw StateError('platform unavailable');
  }

  @override
  Future<PermissionStatus> request(Permission permission) async {
    throw StateError('platform unavailable');
  }
}

class _FakeLocalNetworkPermissionGateway
    implements LocalNetworkPermissionGateway {
  var requestCount = 0;

  @override
  Future<void> requestIfNeeded() async {
    requestCount++;
  }
}

class _FakeCameraPermissionGateway implements CameraPermissionGateway {
  _FakeCameraPermissionGateway({
    this.statusResult = CameraPermissionStatus.denied,
  });

  CameraPermissionStatus statusResult;
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<CameraPermissionStatus> status() async {
    statusCalls++;
    return statusResult;
  }

  @override
  Future<CameraPermissionStatus> request() async {
    requestCalls++;
    statusResult = CameraPermissionStatus.granted;
    return statusResult;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}
