import 'dart:io';

class LocalNetworkGuard {
  const LocalNetworkGuard({this.allowLoopback = true});

  final bool allowLoopback;

  bool isAllowedRemoteAddress(InternetAddress address) {
    if (allowLoopback && address.isLoopback) return true;
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    if (bytes.length != 4) return false;

    final first = bytes[0];
    final second = bytes[1];
    if (first == 10) return true;
    if (first == 192 && second == 168) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    return false;
  }
}
