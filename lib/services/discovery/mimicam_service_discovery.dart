import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

class MimiCamDiscoveryConfig {
  const MimiCamDiscoveryConfig._();

  static const serviceType = '_mimicam._tcp';
}

class MimiCamDiscoveredService {
  const MimiCamDiscoveredService({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
    required this.metadata,
  });

  final String name;
  final String host;
  final int port;
  final List<InternetAddress> addresses;
  final Map<String, String> metadata;

  String get authority => Uri(host: host, port: port).authority;
  bool get webRtcAvailable => metadata['webrtc'] == '1';
  String? get deviceId => metadata['id'];
}

typedef NsdRegister = Future<nsd.Registration> Function(nsd.Service service);
typedef NsdUnregister = Future<void> Function(nsd.Registration registration);
typedef NsdStartDiscovery = Future<nsd.Discovery> Function(
  String serviceType,
);
typedef NsdStopDiscovery = Future<void> Function(nsd.Discovery discovery);

class MimiCamServiceAdvertiser {
  MimiCamServiceAdvertiser({
    NsdRegister? registerService,
    NsdUnregister? unregisterService,
  })  : _registerService = registerService ?? nsd.register,
        _unregisterService = unregisterService ?? nsd.unregister;

  final NsdRegister _registerService;
  final NsdUnregister _unregisterService;
  nsd.Registration? _registration;
  Future<void> _operations = Future<void>.value();
  int? _activePort;

  bool get isAdvertising => _registration != null;

  Future<void> start({
    required String name,
    required String deviceId,
    required int port,
    required int protocolVersion,
    required bool webRtcAvailable,
  }) =>
      _serialize(() async {
        if (_registration != null && _activePort == port) return;
        await _stopLocked();
        final service = nsd.Service(
          name: name,
          type: MimiCamDiscoveryConfig.serviceType,
          port: port,
          txt: {
            'id': _bytes(deviceId),
            'v': _bytes('$protocolVersion'),
            'webrtc': _bytes(webRtcAvailable ? '1' : '0'),
            'transport': _bytes('http_ws'),
          },
        );
        _registration = await _registerService(service);
        _activePort = port;
      });

  Future<void> stop() => _serialize(_stopLocked);

  Future<void> dispose() => stop();

  Future<void> _stopLocked() async {
    final registration = _registration;
    _registration = null;
    _activePort = null;
    if (registration != null) await _unregisterService(registration);
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next =
        _operations.then((_) => operation(), onError: (_) => operation());
    _operations = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static Uint8List _bytes(String value) =>
      Uint8List.fromList(utf8.encode(value));
}

class MimiCamServiceBrowser {
  MimiCamServiceBrowser({
    NsdStartDiscovery? startDiscovery,
    NsdStopDiscovery? stopDiscovery,
  })  : _startDiscovery = startDiscovery ?? _startNsdDiscovery,
        _stopDiscovery = stopDiscovery ?? nsd.stopDiscovery;

  final NsdStartDiscovery _startDiscovery;
  final NsdStopDiscovery _stopDiscovery;
  final _services = <String, MimiCamDiscoveredService>{};
  final _updates = StreamController<List<MimiCamDiscoveredService>>.broadcast();
  nsd.Discovery? _discovery;
  Object? _lastError;

  Stream<List<MimiCamDiscoveredService>> get updates => _updates.stream;
  List<MimiCamDiscoveredService> get services =>
      List.unmodifiable(_services.values);
  Object? get lastError => _lastError;
  bool get isRunning => _discovery != null;

  Future<void> start() async {
    if (_discovery != null) return;
    try {
      final discovery =
          await _startDiscovery(MimiCamDiscoveryConfig.serviceType);
      _discovery = discovery;
      discovery.addServiceListener(_onService);
      for (final service in discovery.services) {
        await _onService(service, nsd.ServiceStatus.found);
      }
      _lastError = null;
      _emit();
    } catch (error) {
      _lastError = error;
      _emit();
      rethrow;
    }
  }

  Future<void> stop() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      discovery.removeServiceListener(_onService);
      await _stopDiscovery(discovery);
    }
    _services.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _updates.close();
  }

  Future<void> _onService(
    nsd.Service service,
    nsd.ServiceStatus status,
  ) async {
    final key = '${service.name ?? ''}|${service.type ?? ''}';
    if (status == nsd.ServiceStatus.lost) {
      _services.remove(key);
      _emit();
      return;
    }
    final parsed = _parse(service);
    if (parsed == null) return;
    _services[key] = parsed;
    _emit();
  }

  void _emit() {
    if (_updates.isClosed) return;
    final values = _services.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    _updates.add(List.unmodifiable(values));
  }

  static MimiCamDiscoveredService? _parse(nsd.Service service) {
    final port = service.port;
    if (port == null || port <= 0 || port > 65535) return null;
    final addresses = service.addresses ?? const <InternetAddress>[];
    final host =
        _preferredAddress(addresses)?.address ?? _normalizeHost(service.host);
    if (host == null || host.isEmpty) return null;
    return MimiCamDiscoveredService(
      name: service.name?.trim().isNotEmpty == true
          ? service.name!.trim()
          : 'MimiCam',
      host: host,
      port: port,
      addresses: List.unmodifiable(addresses),
      metadata: {
        for (final entry in (service.txt ?? const {}).entries)
          entry.key: _decode(entry.value),
      },
    );
  }

  static InternetAddress? _preferredAddress(List<InternetAddress> addresses) {
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
        return address;
      }
    }
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv6 &&
          !address.isLoopback &&
          !address.isLinkLocal) {
        return address;
      }
    }
    return addresses.where((address) => !address.isLoopback).firstOrNull;
  }

  static String? _normalizeHost(String? value) {
    final host = value?.trim();
    if (host == null || host.isEmpty) return null;
    return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  }

  static String _decode(Uint8List? value) =>
      value == null ? '' : utf8.decode(value, allowMalformed: true);

  static Future<nsd.Discovery> _startNsdDiscovery(String serviceType) =>
      nsd.startDiscovery(
        serviceType,
        autoResolve: true,
        ipLookupType: nsd.IpLookupType.any,
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
