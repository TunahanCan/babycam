import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../../core/async/serialized_async_executor.dart';
import '../../core/network/lan_endpoint.dart';
import '../../core/network/retry_policy.dart';
import '../network_address_provider.dart';

class MiuCamDiscoveryConfig {
  const MiuCamDiscoveryConfig._();

  static const serviceType = '_miucam._tcp';
}

class MiuCamDiscoveredService {
  const MiuCamDiscoveredService({
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

  List<LanEndpoint> get endpoints {
    final values = <LanEndpoint>[];
    final seen = <String>{};
    void add(String candidate) {
      final normalized = normalizeLanHost(candidate);
      final endpoint = LanEndpoint(host: normalized, port: port);
      if (normalized.isNotEmpty && seen.add(endpoint.authority)) {
        values.add(endpoint);
      }
    }

    for (final address
        in NetworkAddressProvider.orderResolvedAddresses(addresses)) {
      if (address.isLinkLocal && !address.address.contains('%')) continue;
      add(address.address);
    }
    add(host);
    return List.unmodifiable(values);
  }
}

typedef NsdRegister = Future<nsd.Registration> Function(nsd.Service service);
typedef NsdUnregister = Future<void> Function(nsd.Registration registration);
typedef NsdStartDiscovery = Future<nsd.Discovery> Function(
  String serviceType,
);
typedef NsdStopDiscovery = Future<void> Function(nsd.Discovery discovery);
typedef MiuCamDiscoveryDeviceIdProvider = FutureOr<String> Function();

class MiuCamServiceAdvertiser {
  MiuCamServiceAdvertiser({
    NsdRegister? registerService,
    NsdUnregister? unregisterService,
    MiuCamDiscoveryDeviceIdProvider? deviceIdProvider,
    RetryPolicy? retryPolicy,
    this.maxAttempts = 3,
  })  : _registerService = registerService ?? nsd.register,
        _unregisterService = unregisterService ?? nsd.unregister,
        _deviceIdProvider = deviceIdProvider,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: const Duration(milliseconds: 150),
              maxDelay: const Duration(seconds: 2),
              jitterRatio: .2,
            ) {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
  }

  final NsdRegister _registerService;
  final NsdUnregister _unregisterService;
  final MiuCamDiscoveryDeviceIdProvider? _deviceIdProvider;
  final RetryPolicy _retryPolicy;
  final int maxAttempts;
  nsd.Registration? _registration;
  final _operations = SerializedAsyncExecutor();
  _AdvertisementSpec? _activeSpec;
  bool _disposed = false;

  bool get isAdvertising => _registration != null;
  String? get activeDeviceId => _activeSpec?.deviceId;

  Future<void> start({
    required String name,
    required String deviceId,
    required int port,
    required int protocolVersion,
    required bool webRtcAvailable,
  }) =>
      _serialize(() async {
        if (_disposed) throw StateError('Discovery advertiser is disposed.');
        final injectedId = await _deviceIdProvider?.call();
        final resolvedId = (injectedId?.trim().isNotEmpty ?? false)
            ? injectedId!.trim()
            : deviceId.trim();
        if (resolvedId.isEmpty) {
          throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
        }
        final spec = _AdvertisementSpec(
          name: name.trim(),
          deviceId: resolvedId,
          port: port,
          protocolVersion: protocolVersion,
          webRtcAvailable: webRtcAvailable,
        );
        if (_registration != null && _activeSpec == spec) return;
        await _stopLocked();
        final service = nsd.Service(
          name: spec.name,
          type: MiuCamDiscoveryConfig.serviceType,
          port: spec.port,
          txt: {
            'id': _bytes(spec.deviceId),
            'v': _bytes('${spec.protocolVersion}'),
            'webrtc': _bytes(spec.webRtcAvailable ? '1' : '0'),
            'transport': _bytes('http_ws'),
          },
        );
        _registration = await _retry(
          action: () => _registerService(service),
          retryPolicy: _retryPolicy,
          maxAttempts: maxAttempts,
        );
        _activeSpec = spec;
      });

  Future<void> stop() => _serialize(_stopLocked);

  Future<void> dispose() => _serialize(() async {
        if (_disposed) return;
        await _stopLocked();
        _disposed = true;
      });

  Future<void> _stopLocked() async {
    final registration = _registration;
    if (registration == null) {
      _activeSpec = null;
      return;
    }
    await _retry(
      action: () => _unregisterService(registration),
      retryPolicy: _retryPolicy,
      maxAttempts: maxAttempts,
    );
    _registration = null;
    _activeSpec = null;
  }

  Future<void> _serialize(Future<void> Function() operation) {
    return _operations.run(operation);
  }

  static Uint8List _bytes(String value) =>
      Uint8List.fromList(utf8.encode(value));
}

class _AdvertisementSpec {
  const _AdvertisementSpec({
    required this.name,
    required this.deviceId,
    required this.port,
    required this.protocolVersion,
    required this.webRtcAvailable,
  });

  final String name;
  final String deviceId;
  final int port;
  final int protocolVersion;
  final bool webRtcAvailable;

  @override
  bool operator ==(Object other) =>
      other is _AdvertisementSpec &&
      other.name == name &&
      other.deviceId == deviceId &&
      other.port == port &&
      other.protocolVersion == protocolVersion &&
      other.webRtcAvailable == webRtcAvailable;

  @override
  int get hashCode => Object.hash(
        name,
        deviceId,
        port,
        protocolVersion,
        webRtcAvailable,
      );
}

class MiuCamServiceBrowser {
  MiuCamServiceBrowser({
    NsdStartDiscovery? startDiscovery,
    NsdStopDiscovery? stopDiscovery,
    RetryPolicy? retryPolicy,
    this.maxAttempts = 3,
  })  : _startDiscovery = startDiscovery ?? _startNsdDiscovery,
        _stopDiscovery = stopDiscovery ?? nsd.stopDiscovery,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: const Duration(milliseconds: 150),
              maxDelay: const Duration(seconds: 2),
              jitterRatio: .2,
            ) {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
  }

  final NsdStartDiscovery _startDiscovery;
  final NsdStopDiscovery _stopDiscovery;
  final RetryPolicy _retryPolicy;
  final int maxAttempts;
  final _services = <String, MiuCamDiscoveredService>{};
  final _servicesByInstance = <String, MiuCamDiscoveredService>{};
  final _canonicalKeysByInstance = <String, String>{};
  final _updates = StreamController<List<MiuCamDiscoveredService>>.broadcast();
  final _operations = SerializedAsyncExecutor();
  nsd.Discovery? _discovery;
  nsd.ServiceListener? _listener;
  Object? _lastError;
  int _generation = 0;
  bool _disposed = false;

  Stream<List<MiuCamDiscoveredService>> get updates => _updates.stream;
  List<MiuCamDiscoveredService> get services =>
      List.unmodifiable(_services.values);
  Object? get lastError => _lastError;
  bool get isRunning => _discovery != null;

  Future<void> start() => _serialize(_startLocked);

  Future<void> _startLocked() async {
    if (_disposed) throw StateError('Discovery browser is disposed.');
    if (_discovery != null) return;
    try {
      final discovery = await _retry(
        action: () => _startDiscovery(MiuCamDiscoveryConfig.serviceType),
        retryPolicy: _retryPolicy,
        maxAttempts: maxAttempts,
      );
      final generation = ++_generation;
      void listener(nsd.Service service, nsd.ServiceStatus status) {
        unawaited(_onService(generation, service, status));
      }

      _discovery = discovery;
      _listener = listener;
      discovery.addServiceListener(listener);
      for (final service in discovery.services) {
        await _onService(generation, service, nsd.ServiceStatus.found);
      }
      _lastError = null;
      _emit();
    } catch (error) {
      _lastError = error;
      _emit();
      rethrow;
    }
  }

  Future<void> stop() => _serialize(_stopLocked);

  Future<void> _stopLocked() async {
    final discovery = _discovery;
    _generation++;
    final listener = _listener;
    _listener = null;
    if (discovery != null) {
      if (listener != null) discovery.removeServiceListener(listener);
      await _retry(
        action: () => _stopDiscovery(discovery),
        retryPolicy: _retryPolicy,
        maxAttempts: maxAttempts,
      );
    }
    _discovery = null;
    _services.clear();
    _servicesByInstance.clear();
    _canonicalKeysByInstance.clear();
    _emit();
  }

  Future<void> dispose() => _serialize(() async {
        if (_disposed) return;
        await _stopLocked();
        _disposed = true;
        await _updates.close();
      });

  Future<void> _onService(
    int generation,
    nsd.Service service,
    nsd.ServiceStatus status,
  ) async {
    if (_disposed || generation != _generation) return;
    final instanceKey = _instanceKey(service);
    if (status == nsd.ServiceStatus.lost) {
      _servicesByInstance.remove(instanceKey);
      _canonicalKeysByInstance.remove(instanceKey);
      _rebuildCanonicalServices();
      _emit();
      return;
    }
    final parsed = _parse(service);
    if (parsed == null) return;
    final canonical = _canonicalKey(service, metadata: parsed.metadata);
    _servicesByInstance[instanceKey] = parsed;
    _canonicalKeysByInstance[instanceKey] = canonical;
    _rebuildCanonicalServices();
    _emit();
  }

  void _rebuildCanonicalServices() {
    _services.clear();
    final grouped = <String, List<MapEntry<String, MiuCamDiscoveredService>>>{};
    for (final entry in _servicesByInstance.entries) {
      final canonical = _canonicalKeysByInstance[entry.key];
      if (canonical != null) {
        (grouped[canonical] ??= []).add(entry);
      }
    }
    for (final group in grouped.entries) {
      if (group.value.length == 1) {
        _services[group.key] = group.value.single.value;
        continue;
      }
      // A duplicate stable ID is ambiguous. Preserve every DNS-SD instance so
      // trusted endpoint resolution can refuse to guess between devices.
      for (final entry in group.value) {
        _services['${group.key}|instance:${entry.key}'] = entry.value;
      }
    }
  }

  void _emit() {
    if (_updates.isClosed) return;
    final values = _services.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    _updates.add(List.unmodifiable(values));
  }

  static MiuCamDiscoveredService? _parse(nsd.Service service) {
    final port = service.port;
    if (port == null || port <= 0 || port > 65535) return null;
    final addresses = NetworkAddressProvider.orderResolvedAddresses(
      service.addresses ?? const <InternetAddress>[],
    );
    final host =
        _preferredAddress(addresses)?.address ?? _normalizeHost(service.host);
    if (host == null || host.isEmpty) return null;
    return MiuCamDiscoveredService(
      name: service.name?.trim().isNotEmpty == true
          ? service.name!.trim()
          : 'MiuCam',
      host: host,
      port: port,
      addresses: addresses,
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
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv6 &&
          address.isLinkLocal &&
          address.address.contains('%')) {
        return address;
      }
    }
    // An unscoped fe80:: literal is not a routable endpoint. Let _parse keep
    // the resolved .local hostname instead of replacing it with that literal.
    return null;
  }

  static String? _normalizeHost(String? value) {
    final host = normalizeLanHost(value ?? '');
    if (host.isEmpty) return null;
    return host;
  }

  static String _decode(Uint8List? value) =>
      value == null ? '' : utf8.decode(value, allowMalformed: true);

  static Future<nsd.Discovery> _startNsdDiscovery(String serviceType) =>
      nsd.startDiscovery(
        serviceType,
        autoResolve: true,
        ipLookupType: nsd.IpLookupType.any,
      );

  Future<void> _serialize(Future<void> Function() operation) {
    return _operations.run(operation);
  }

  static String _instanceKey(nsd.Service service) =>
      '${service.name ?? ''}|${service.type ?? ''}';

  static String _canonicalKey(
    nsd.Service service, {
    Map<String, String>? metadata,
  }) {
    final resolvedMetadata = metadata ??
        {
          for (final entry in (service.txt ?? const {}).entries)
            entry.key: _decode(entry.value),
        };
    final id = resolvedMetadata['id']?.trim();
    return id != null && id.isNotEmpty ? 'id:$id' : _instanceKey(service);
  }
}

Future<T> _retry<T>({
  required Future<T> Function() action,
  required RetryPolicy retryPolicy,
  required int maxAttempts,
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await action();
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      if (attempt + 1 < maxAttempts) {
        await Future<void>.delayed(retryPolicy.delayForAttempt(attempt));
      }
    }
  }
  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}
