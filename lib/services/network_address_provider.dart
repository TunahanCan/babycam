import 'dart:io';

import '../core/mimicam_protocol.dart';
import '../core/network/lan_endpoint.dart';
import '../core/network/local_network_guard.dart';

class NetworkAddressCandidate {
  const NetworkAddressCandidate({
    required this.interfaceName,
    required this.address,
  });

  final String interfaceName;
  final String address;
}

class LocalNetworkEndpoint {
  const LocalNetworkEndpoint({
    required this.interfaceName,
    required this.address,
    required this.port,
    String? host,
  }) : _host = host;

  final String interfaceName;
  final InternetAddress address;
  final int port;
  final String? _host;

  String get host => _host ?? address.address;
  bool get isIpv6 => address.type == InternetAddressType.IPv6;
  String get authority => Uri(host: host, port: port).authority;

  Uri uri({String scheme = 'http', String path = '/'}) => Uri(
        scheme: scheme,
        host: host,
        port: port,
        path: path,
      );
}

class NetworkAddressProvider {
  static Future<List<LocalNetworkPrefix>> localIpv6Prefixes() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv6,
      includeLoopback: false,
    );
    return ipv6PrefixesForCandidates([
      for (final interface in interfaces)
        for (final address in interface.addresses)
          NetworkAddressCandidate(
            interfaceName: interface.name,
            address: address.address,
          ),
    ]);
  }

  /// SLAAC LANs use /64 subnets. Capturing each active interface's /64 keeps
  /// global IPv6 clients on-link without treating every public IPv6 address as
  /// a local peer.
  static List<LocalNetworkPrefix> ipv6PrefixesForCandidates(
    Iterable<NetworkAddressCandidate> candidates,
  ) {
    final prefixes = <String, LocalNetworkPrefix>{};
    for (final candidate in candidates) {
      final address = tryParseLanAddress(candidate.address);
      if (address == null ||
          address.type != InternetAddressType.IPv6 ||
          !_isUsable(address) ||
          address.isLinkLocal) {
        continue;
      }
      final prefix = LocalNetworkPrefix(address: address, prefixLength: 64);
      final bytes = address.rawAddress;
      final key = bytes.take(8).join(':');
      prefixes.putIfAbsent(key, () => prefix);
    }
    return List<LocalNetworkPrefix>.unmodifiable(prefixes.values);
  }

  static Future<LocalNetworkEndpoint?> localEndpoint({
    int port = MimiCamProtocol.httpPort,
    InternetAddressType type = InternetAddressType.any,
  }) async {
    final interfaces = await NetworkInterface.list(
      type: type,
      includeLoopback: false,
    );
    final candidates = <NetworkAddressCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        candidates.add(NetworkAddressCandidate(
          interfaceName: interface.name,
          address: address.address,
        ));
      }
    }
    return bestLocalEndpoint(candidates, port: port);
  }

  static Future<String?> localHttpAddress({
    int port = MimiCamProtocol.httpPort,
  }) async =>
      (await localEndpoint(port: port))?.authority;

  static LocalNetworkEndpoint? bestLocalEndpoint(
    Iterable<NetworkAddressCandidate> candidates, {
    int port = MimiCamProtocol.httpPort,
  }) =>
      rankedLocalEndpoints(candidates, port: port).firstOrNull;

  static List<LocalNetworkEndpoint> rankedLocalEndpoints(
    Iterable<NetworkAddressCandidate> candidates, {
    int port = MimiCamProtocol.httpPort,
  }) {
    final scored = candidates
        .map((candidate) => (
              candidate: candidate,
              address: tryParseLanAddress(candidate.address),
            ))
        .where((value) => value.address != null && _isUsable(value.address!))
        .map((value) => (
              candidate: value.candidate,
              address: value.address!,
              score: _score(value.candidate, value.address!),
            ))
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.candidate.address.compareTo(b.candidate.address);
      });
    return List.unmodifiable([
      for (final value in scored)
        LocalNetworkEndpoint(
          interfaceName: value.candidate.interfaceName,
          address: value.address,
          port: port,
          host: _uriHost(value.candidate, value.address),
        ),
    ]);
  }

  static String? bestLocalHost(Iterable<NetworkAddressCandidate> candidates) =>
      bestLocalEndpoint(candidates)?.host;

  static int _score(
    NetworkAddressCandidate candidate,
    InternetAddress address,
  ) {
    final interfaceName = candidate.interfaceName.toLowerCase();
    var score = 0;
    if (address.type == InternetAddressType.IPv4) {
      score += _isPrivateIpv4(address.rawAddress) ? 110 : 25;
    } else if (_isUniqueLocalIpv6(address.rawAddress)) {
      score += 105;
    } else if (address.isLinkLocal) {
      score += 55;
    } else {
      score += 70;
    }
    if (_isPreferredInterface(interfaceName)) score += 30;
    if (_isVirtualOrPeerInterface(interfaceName)) score -= 100;
    return score;
  }

  static bool _isUsable(InternetAddress address) {
    if (address.isLoopback || address.isMulticast) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes.length == 4 &&
          !bytes.every((value) => value == 0) &&
          !(bytes[0] == 169 && bytes[1] == 254);
    }
    if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
      return false;
    }
    final unspecified = bytes.every((value) => value == 0);
    return !unspecified;
  }

  static bool _isPrivateIpv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static bool _isUniqueLocalIpv6(List<int> bytes) =>
      bytes.length == 16 && (bytes[0] & 0xfe) == 0xfc;

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

  /// Orders resolved DNS-SD addresses by LAN reachability and removes aliases.
  static List<InternetAddress> orderResolvedAddresses(
    Iterable<InternetAddress> addresses,
  ) {
    final unique = <String, InternetAddress>{};
    for (final address in addresses) {
      if (!_isUsable(address)) continue;
      unique.putIfAbsent(normalizeLanHost(address.address), () => address);
    }
    final result = unique.values.toList(growable: false)
      ..sort((left, right) {
        final leftScore = _score(
          NetworkAddressCandidate(interfaceName: '', address: left.address),
          left,
        );
        final rightScore = _score(
          NetworkAddressCandidate(interfaceName: '', address: right.address),
          right,
        );
        final byScore = rightScore.compareTo(leftScore);
        if (byScore != 0) return byScore;
        return left.address.compareTo(right.address);
      });
    return List.unmodifiable(result);
  }

  static String _uriHost(
    NetworkAddressCandidate candidate,
    InternetAddress address,
  ) {
    final original = normalizeLanHost(candidate.address);
    if (!address.isLinkLocal || original.contains('%')) return original;
    final interfaceName = candidate.interfaceName.trim();
    return interfaceName.isEmpty ? original : '$original%$interfaceName';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
