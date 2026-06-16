import 'dart:io';

import '../core/mimicam_protocol.dart';

class NetworkAddressProvider {
  static Future<String?> localHttpAddress(
      {int port = MimiCamProtocol.httpPort}) async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return '${address.address}:$port';
      }
    }
    return null;
  }
}
