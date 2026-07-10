import 'dart:io';

class LocalNetworkGuard {
  const LocalNetworkGuard({this.allowLoopback = true});

  final bool allowLoopback;

  bool isAllowedRemoteAddress(InternetAddress address) {
    if (allowLoopback && address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final first = bytes[0];
      final second = bytes[1];
      if (first == 10) return true;
      if (first == 192 && second == 168) return true;
      if (first == 172 && second >= 16 && second <= 31) return true;
      return false;
    }
    if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
      return false;
    }
    if (_isIpv4Mapped(bytes)) {
      return isAllowedRemoteAddress(InternetAddress.fromRawAddress(
        bytes.sublist(12),
        type: InternetAddressType.IPv4,
      ));
    }
    final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    return uniqueLocal || linkLocal;
  }

  bool _isIpv4Mapped(List<int> bytes) {
    if (bytes.length != 16 || bytes[10] != 0xff || bytes[11] != 0xff) {
      return false;
    }
    for (var index = 0; index < 10; index++) {
      if (bytes[index] != 0) return false;
    }
    return true;
  }
}
