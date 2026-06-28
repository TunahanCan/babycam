import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

enum CameraPermissionStatus {
  denied,
  granted,
  restricted,
  permanentlyDenied,
  limited;

  bool get isGranted => this == granted || this == limited;
  bool get isDenied => this == denied;
  bool get isRestricted => this == restricted;
  bool get isPermanentlyDenied => this == permanentlyDenied;
}

abstract interface class CameraPermissionGateway {
  Future<CameraPermissionStatus> status();

  Future<CameraPermissionStatus> request();

  Future<bool> openSettings();
}

class MethodChannelCameraPermissionGateway implements CameraPermissionGateway {
  const MethodChannelCameraPermissionGateway({
    MethodChannel channel = const MethodChannel(_channelName),
    CameraPermissionGateway fallback =
        const PermissionHandlerCameraPermissionGateway(),
    bool Function() isIOS = _defaultIsIOS,
  })  : _channel = channel,
        _fallback = fallback,
        _isIOS = isIOS;

  static const _channelName = 'mimicam/camera_permission';

  final MethodChannel _channel;
  final CameraPermissionGateway _fallback;
  final bool Function() _isIOS;

  @override
  Future<CameraPermissionStatus> status() async {
    if (!_isIOS()) return _fallback.status();
    try {
      return _nativeStatus(await _channel.invokeMethod<Object?>('status'));
    } on MissingPluginException {
      return _fallback.status();
    } on PlatformException {
      return CameraPermissionStatus.denied;
    }
  }

  @override
  Future<CameraPermissionStatus> request() async {
    if (!_isIOS()) return _fallback.request();
    try {
      return _nativeStatus(await _channel.invokeMethod<Object?>('request'));
    } on MissingPluginException {
      return _fallback.request();
    } on PlatformException {
      return CameraPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!_isIOS()) return _fallback.openSettings();
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return _fallback.openSettings();
    } on PlatformException {
      return false;
    }
  }

  static CameraPermissionStatus _nativeStatus(Object? value) {
    return switch (value?.toString()) {
      'authorized' || 'granted' => CameraPermissionStatus.granted,
      'restricted' => CameraPermissionStatus.restricted,
      'denied' => CameraPermissionStatus.permanentlyDenied,
      'notDetermined' => CameraPermissionStatus.denied,
      _ => CameraPermissionStatus.denied,
    };
  }

  static bool _defaultIsIOS() => Platform.isIOS;
}

class PermissionHandlerCameraPermissionGateway
    implements CameraPermissionGateway {
  const PermissionHandlerCameraPermissionGateway();

  @override
  Future<CameraPermissionStatus> status() async {
    return _fromPermissionHandlerStatus(
      await permissions.Permission.camera.status,
    );
  }

  @override
  Future<CameraPermissionStatus> request() async {
    return _fromPermissionHandlerStatus(
      await permissions.Permission.camera.request(),
    );
  }

  @override
  Future<bool> openSettings() => permissions.openAppSettings();

  static CameraPermissionStatus _fromPermissionHandlerStatus(
    permissions.PermissionStatus status,
  ) {
    if (status.isGranted) return CameraPermissionStatus.granted;
    if (status.isLimited) return CameraPermissionStatus.limited;
    if (status.isRestricted) return CameraPermissionStatus.restricted;
    if (status.isPermanentlyDenied) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }
}
