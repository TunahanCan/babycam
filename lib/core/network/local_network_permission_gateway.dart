import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class LocalNetworkPermissionGateway {
  Future<void> requestIfNeeded();
}

class MethodChannelLocalNetworkPermissionGateway
    implements LocalNetworkPermissionGateway {
  const MethodChannelLocalNetworkPermissionGateway({
    MethodChannel channel = const MethodChannel(_channelName),
    bool Function() isIOS = _defaultIsIOS,
  })  : _channel = channel,
        _isIOS = isIOS;

  static const _channelName = 'mimicam/local_network_permission';

  final MethodChannel _channel;
  final bool Function() _isIOS;

  @override
  Future<void> requestIfNeeded() async {
    if (!_isIOS()) return;
    try {
      await _channel.invokeMethod<void>('request');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static bool _defaultIsIOS() => Platform.isIOS;
}
