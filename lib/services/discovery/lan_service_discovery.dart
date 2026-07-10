import 'dart:io';

@Deprecated('Use MimiCamDiscoveredService from mimicam_service_discovery.dart.')
class LanServiceRecord {
  const LanServiceRecord({
    required this.name,
    required this.port,
    required this.addresses,
    this.host,
    this.attributes = const {},
  });

  final String name;
  final String? host;
  final int port;
  final List<InternetAddress> addresses;
  final Map<String, String> attributes;

  Iterable<Uri> endpoints({String scheme = 'http'}) sync* {
    for (final address in addresses) {
      yield Uri(scheme: scheme, host: address.address, port: port, path: '/');
    }
    final hostname = host?.replaceFirst(RegExp(r'\.$'), '');
    if (addresses.isEmpty && hostname != null && hostname.isNotEmpty) {
      yield Uri(scheme: scheme, host: hostname, port: port, path: '/');
    }
  }
}

@Deprecated('Use MimiCamServiceBrowser from mimicam_service_discovery.dart.')
abstract class LanDiscoverySession {
  Stream<List<LanServiceRecord>> get services;
  Future<void> stop();
}

@Deprecated(
  'Use MimiCamServiceAdvertiser and MimiCamServiceBrowser from '
  'mimicam_service_discovery.dart.',
)
abstract class LanServiceDiscovery {
  static const serviceType = '_mimicam._tcp';

  Future<void> registerServer({
    required String name,
    required int port,
    required int schemaVersion,
    required bool webRtcEnabled,
  });

  Future<void> unregisterServer();
  Future<LanDiscoverySession> discoverServers();
  Future<void> dispose();
}
