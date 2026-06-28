import 'dart:io';

import '../core/mimicam_protocol.dart';

class NetworkAddressCandidate {
  const NetworkAddressCandidate({
    required this.interfaceName,
    required this.address,
  });

  final String interfaceName;
  final String address;
}

class NetworkAddressProvider {
  static Future<String?> localHttpAddress(
      {int port = MimiCamProtocol.httpPort}) async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    final candidates = <NetworkAddressCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          candidates.add(NetworkAddressCandidate(
            interfaceName: interface.name,
            address: address.address,
          ));
        }
      }
    }
    final host = bestLocalHost(candidates);
    return host == null ? null : '$host:$port';
  }

  static String? bestLocalHost(Iterable<NetworkAddressCandidate> candidates) {
    final scored = candidates
        .where((candidate) => _isUsableIpv4(candidate.address))
        .map((candidate) => (
              candidate: candidate,
              score: _score(candidate),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return null;
    return scored.first.candidate.address;
  }

  static int _score(NetworkAddressCandidate candidate) {
    final interfaceName = candidate.interfaceName.toLowerCase();
    var score = 0;
    if (_isPrivateIpv4(candidate.address)) score += 100;
    if (_isPreferredInterface(interfaceName)) score += 30;
    if (_isVirtualOrPeerInterface(interfaceName)) score -= 80;
    return score;
  }

  static bool _isUsableIpv4(String address) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return false;
    }
    if (parsed.isLoopback || parsed.isMulticast) return false;
    if (address == '0.0.0.0' || address.startsWith('169.254.')) return false;
    return true;
  }

  static bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static bool _isPreferredInterface(String name) {
    return name == 'en0' ||
        name.startsWith('wlan') ||
        name.startsWith('wifi') ||
        name.startsWith('eth') ||
        name.contains('wi-fi') ||
        name.contains('wireless');
  }

  static bool _isVirtualOrPeerInterface(String name) {
    return name.startsWith('utun') ||
        name.startsWith('awdl') ||
        name.startsWith('llw') ||
        name.startsWith('bridge') ||
        name.startsWith('p2p') ||
        name.startsWith('dummy') ||
        name.startsWith('lo');
  }
}
