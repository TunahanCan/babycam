import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../core/media/camera_permission_gateway.dart';
import '../core/network/local_network_permission_gateway.dart';
import 'app_role.dart';

class RolePermissionCoordinator {
  const RolePermissionCoordinator({
    this.policy = const RolePermissionPolicy(),
    this.gateway = const PermissionHandlerGateway(),
    this.cameraGateway = const MethodChannelCameraPermissionGateway(),
    this.localNetworkGateway =
        const MethodChannelLocalNetworkPermissionGateway(),
    this.isAndroid = _defaultIsAndroid,
  });

  final RolePermissionPolicy policy;
  final PermissionGateway gateway;
  final CameraPermissionGateway cameraGateway;
  final LocalNetworkPermissionGateway localNetworkGateway;
  final bool Function() isAndroid;

  Future<void> requestFor(AppRole role) async {
    for (final permission
        in policy.permissionsFor(role, isAndroid: isAndroid())) {
      await _requestIfNeeded(permission);
    }
    await _requestLocalNetworkIfNeeded();
  }

  Future<void> _requestIfNeeded(Permission permission) async {
    try {
      if (permission == Permission.camera) {
        await _requestCameraIfNeeded();
        return;
      }
      final status = await gateway.status(permission);
      if (status.isGranted || status.isPermanentlyDenied) return;
      await gateway.request(permission);
    } catch (_) {
      return;
    }
  }

  Future<void> _requestCameraIfNeeded() async {
    final status = await cameraGateway.status();
    if (status.isGranted || status.isPermanentlyDenied || status.isRestricted) {
      return;
    }
    await cameraGateway.request();
  }

  Future<void> _requestLocalNetworkIfNeeded() async {
    try {
      await localNetworkGateway.requestIfNeeded();
    } catch (_) {
      return;
    }
  }

  static bool _defaultIsAndroid() => Platform.isAndroid;
}

class RolePermissionPolicy {
  const RolePermissionPolicy();

  List<Permission> permissionsFor(AppRole role, {required bool isAndroid}) {
    return [
      Permission.notification,
      Permission.camera,
      if (role == AppRole.server) Permission.microphone,
      if (isAndroid) Permission.ignoreBatteryOptimizations,
    ];
  }
}

abstract interface class PermissionGateway {
  Future<PermissionStatus> status(Permission permission);

  Future<PermissionStatus> request(Permission permission);
}

class PermissionHandlerGateway implements PermissionGateway {
  const PermissionHandlerGateway();

  @override
  Future<PermissionStatus> status(Permission permission) => permission.status;

  @override
  Future<PermissionStatus> request(Permission permission) =>
      permission.request();
}
