import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../../core/network/retry_policy.dart';
import 'lan_service_discovery.dart';

class NsdLanServiceDiscovery implements LanServiceDiscovery {
  NsdLanServiceDiscovery({
    RetryPolicy? retryPolicy,
    this.maxAttempts = 3,
    this.onLog,
  }) : _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: const Duration(milliseconds: 150),
              maxDelay: const Duration(seconds: 2),
              jitterRatio: 0.2,
            );

  final RetryPolicy _retryPolicy;
  final int maxAttempts;
  final void Function(String message)? onLog;
  nsd.Registration? _registration;
  final _sessions = <_NsdDiscoverySession>{};
  bool _disposed = false;

  @override
  Future<void> registerServer({
    required String name,
    required int port,
    required int schemaVersion,
    required bool webRtcEnabled,
  }) async {
    if (_disposed) throw StateError('Discovery service is disposed.');
    await unregisterServer();
    final service = nsd.Service(
      name: name,
      type: LanServiceDiscovery.serviceType,
      port: port,
      txt: {
        'service': _txt('mimicam'),
        'schema': _txt('$schemaVersion'),
        'webrtc': _txt(webRtcEnabled ? '1' : '0'),
      },
    );
    _registration = await _retry(
      'register',
      () => nsd.register(service),
    );
  }

  @override
  Future<void> unregisterServer() async {
    final registration = _registration;
    _registration = null;
    if (registration == null) return;
    try {
      await nsd.unregister(registration);
    } catch (error) {
      onLog?.call('DNS-SD unregister failed: $error');
    }
  }

  @override
  Future<LanDiscoverySession> discoverServers() async {
    if (_disposed) throw StateError('Discovery service is disposed.');
    final discovery = await _retry(
      'discover',
      () => nsd.startDiscovery(
        LanServiceDiscovery.serviceType,
        autoResolve: true,
        ipLookupType: nsd.IpLookupType.any,
      ),
    );
    late final _NsdDiscoverySession session;
    session = _NsdDiscoverySession(
      discovery,
      onStop: () => _sessions.remove(session),
      onLog: onLog,
    );
    _sessions.add(session);
    return session;
  }

  Future<T> _retry<T>(String operation, Future<T> Function() action) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await action();
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        onLog?.call('DNS-SD $operation attempt ${attempt + 1} failed: $error');
        if (attempt + 1 < maxAttempts) {
          await Future<void>.delayed(_retryPolicy.delayForAttempt(attempt));
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sessions = _sessions.toList(growable: false);
    for (final session in sessions) {
      await session.stop();
    }
    _sessions.clear();
    await unregisterServer();
  }

  static Uint8List _txt(String value) => Uint8List.fromList(utf8.encode(value));
}

class _NsdDiscoverySession implements LanDiscoverySession {
  _NsdDiscoverySession(
    this._discovery, {
    required this.onStop,
    this.onLog,
  }) {
    _listener = (_, __) => _publish();
    _discovery.addServiceListener(_listener);
    _publish();
  }

  final nsd.Discovery _discovery;
  final void Function() onStop;
  final void Function(String message)? onLog;
  final _controller = StreamController<List<LanServiceRecord>>.broadcast();
  late final nsd.ServiceListener _listener;
  bool _stopped = false;

  @override
  Stream<List<LanServiceRecord>> get services => _controller.stream;

  void _publish() {
    if (_stopped) return;
    final records = _discovery.services
        .where((service) =>
            service.port != null &&
            service.port! > 0 &&
            service.name?.trim().isNotEmpty == true)
        .map((service) => LanServiceRecord(
              name: service.name!.trim(),
              host: service.host,
              port: service.port!,
              addresses: List.unmodifiable(service.addresses ?? const []),
              attributes: {
                for (final entry in (service.txt ?? const {}).entries)
                  entry.key: _decodeTxt(entry.value),
              },
            ))
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    _controller.add(List.unmodifiable(records));
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _discovery.removeServiceListener(_listener);
    try {
      await nsd.stopDiscovery(_discovery);
    } catch (error) {
      onLog?.call('DNS-SD discovery stop failed: $error');
    }
    await _controller.close();
    onStop();
  }

  static String _decodeTxt(Uint8List? value) =>
      value == null ? '' : utf8.decode(value, allowMalformed: true);
}
