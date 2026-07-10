import 'dart:io';

/// A host/port pair accepted from local-network discovery or manual entry.
class LanEndpoint {
  const LanEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  String get authority => Uri(host: host, port: port).authority;

  Uri uri({String scheme = 'http', String path = '/'}) => Uri(
        scheme: scheme,
        host: host,
        port: port,
        path: path,
      );

  @override
  bool operator ==(Object other) =>
      other is LanEndpoint &&
      normalizeLanHost(other.host) == normalizeLanHost(host) &&
      other.port == port;

  @override
  int get hashCode => Object.hash(normalizeLanHost(host), port);

  /// Parses hostnames, IPv4, raw IPv6, and bracketed/scoped IPv6 authorities.
  ///
  /// A port on an IPv6 literal must use RFC 3986 brackets. A raw IPv6 literal
  /// therefore always receives [defaultPort], avoiding ambiguity with its last
  /// hexadecimal segment.
  static LanEndpoint? parse(
    String value, {
    int defaultPort = 8080,
  }) {
    if (!_validPort(defaultPort)) return null;
    final input = value.trim();
    if (input.isEmpty) return null;

    if (input.contains('://')) {
      try {
        final uri = Uri.tryParse(input);
        if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
          return null;
        }
        final port = uri.hasPort ? uri.port : defaultPort;
        if (!_validPort(port)) return null;
        return _validated(normalizeLanHost(uri.host), port);
      } on FormatException {
        return null;
      }
    }

    if (input.startsWith('[')) {
      final closingBracket = input.indexOf(']');
      if (closingBracket <= 1) return null;
      final host = normalizeLanHost(input.substring(1, closingBracket));
      final suffix = input.substring(closingBracket + 1);
      if (suffix.isEmpty) return _validated(host, defaultPort);
      if (!suffix.startsWith(':') || suffix.length == 1) return null;
      final port = int.tryParse(suffix.substring(1));
      if (port == null || !_validPort(port)) return null;
      return _validated(host, port);
    }

    final normalized = normalizeLanHost(input);
    if (tryParseLanAddress(normalized) != null) {
      return LanEndpoint(host: normalized, port: defaultPort);
    }

    final firstColon = input.indexOf(':');
    final lastColon = input.lastIndexOf(':');
    if (firstColon >= 0) {
      if (firstColon != lastColon) return null;
      final host = normalizeLanHost(input.substring(0, firstColon));
      final port = int.tryParse(input.substring(firstColon + 1));
      if (host.isEmpty || port == null || !_validPort(port)) return null;
      return _validated(host, port);
    }
    return _validated(normalized, defaultPort);
  }

  static LanEndpoint? _validated(String host, int port) {
    if (host.isEmpty || !_validPort(port) || _containsInvalidHostText(host)) {
      return null;
    }
    if ((host.contains(':') || host.contains('%')) &&
        tryParseLanAddress(host) == null) {
      return null;
    }
    return LanEndpoint(host: host, port: port);
  }

  static bool _validPort(int port) => port > 0 && port <= 65535;

  static bool _containsInvalidHostText(String host) =>
      RegExp(r'[\s/?#@\[\]]').hasMatch(host);
}

/// Canonicalizes URI-escaped zone identifiers and optional IPv6 brackets.
String normalizeLanHost(String value) {
  var host = value.trim();
  if (host.startsWith('[') && host.endsWith(']') && host.length > 2) {
    host = host.substring(1, host.length - 1);
  }
  host = host.replaceAll(RegExp('%25', caseSensitive: false), '%');
  return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
}

bool lanHostsEqual(String left, String right) {
  final normalizedLeft = normalizeLanHost(left).toLowerCase();
  final normalizedRight = normalizeLanHost(right).toLowerCase();
  if (normalizedLeft == normalizedRight) return true;
  if (normalizedLeft.contains('%') || normalizedRight.contains('%')) {
    return false;
  }
  final leftAddress = tryParseLanAddress(normalizedLeft);
  final rightAddress = tryParseLanAddress(normalizedRight);
  if (leftAddress == null || rightAddress == null) return false;
  if (leftAddress.type != rightAddress.type) return false;
  final leftBytes = leftAddress.rawAddress;
  final rightBytes = rightAddress.rawAddress;
  if (leftBytes.length != rightBytes.length) return false;
  for (var index = 0; index < leftBytes.length; index++) {
    if (leftBytes[index] != rightBytes[index]) return false;
  }
  return true;
}

/// Parses an IP literal while preserving a scoped IPv6 host for URI use.
InternetAddress? tryParseLanAddress(String value) {
  final normalized = normalizeLanHost(value);
  final direct = InternetAddress.tryParse(normalized);
  if (direct != null) return direct;
  final zoneIndex = normalized.lastIndexOf('%');
  if (zoneIndex <= 0) return null;
  return InternetAddress.tryParse(normalized.substring(0, zoneIndex));
}
