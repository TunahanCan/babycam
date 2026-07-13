import 'dart:io';

class LocalNetworkGuard {
  const LocalNetworkGuard({
    this.allowLoopback = true,
    this.allowGlobalIpv6WithoutPrefixContext = false,
    this.localPrefixes = const [],
  });

  final bool allowLoopback;
  final bool allowGlobalIpv6WithoutPrefixContext;
  final List<LocalNetworkPrefix> localPrefixes;

  bool isAllowedRemoteAddress(InternetAddress address) {
    if (allowLoopback && address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      if (_matchesConfiguredPrefix(address)) return true;
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
    if (address.isMulticast || _isUnspecified(bytes)) return false;
    if (_matchesConfiguredPrefix(address)) return true;
    final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    if (uniqueLocal || linkLocal) return true;

    final globalUnicast = (bytes[0] & 0xe0) == 0x20;
    if (!globalUnicast) return false;
    final hasIpv6PrefixContext = localPrefixes.any(
      (prefix) => prefix.address.type == InternetAddressType.IPv6,
    );
    return !hasIpv6PrefixContext && allowGlobalIpv6WithoutPrefixContext;
  }

  bool _matchesConfiguredPrefix(InternetAddress address) =>
      localPrefixes.any((prefix) => prefix.contains(address));

  bool _isUnspecified(List<int> bytes) => bytes.every((byte) => byte == 0);

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

/// A local interface prefix used to constrain globally routable LAN addresses.
///
/// Callers that know the active interface should provide its prefixes. Global
/// unicast IPv6 is rejected when interface-prefix discovery is unavailable;
/// callers may explicitly opt into the legacy compatibility behavior only
/// when another boundary authenticates the remote peer.
class LocalNetworkPrefix {
  const LocalNetworkPrefix({
    required this.address,
    required this.prefixLength,
  }) : assert(prefixLength >= 0 && prefixLength <= 128);

  final InternetAddress address;
  final int prefixLength;

  bool contains(InternetAddress candidate) {
    if (candidate.type != address.type) return false;
    final left = address.rawAddress;
    final right = candidate.rawAddress;
    if (left.length != right.length) return false;
    final maximumBits = left.length * 8;
    if (prefixLength > maximumBits) return false;
    final wholeBytes = prefixLength ~/ 8;
    for (var index = 0; index < wholeBytes; index++) {
      if (left[index] != right[index]) return false;
    }
    final remainingBits = prefixLength % 8;
    if (remainingBits == 0) return true;
    final mask = (0xff << (8 - remainingBits)) & 0xff;
    return (left[wholeBytes] & mask) == (right[wholeBytes] & mask);
  }
}
