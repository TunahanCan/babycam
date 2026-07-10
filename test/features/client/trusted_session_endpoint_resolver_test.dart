import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/network/retry_policy.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/discovery/trusted_session_endpoint_resolver.dart';
import 'package:mimicam/services/discovery/mimicam_service_discovery.dart';
import 'package:nsd/nsd.dart' as nsd;

void main() {
  test('rebinds the same trusted device to a reachable IPv6 endpoint',
      () async {
    final discovery = nsd.Discovery('discovery');
    final browser = _browser(discovery);
    addTearDown(browser.dispose);
    final probedHosts = <String>[];
    final resolver = TrustedSessionEndpointResolver(
      browser: browser,
      retryPolicy: _noDelayRetry,
      maxProbeAttempts: 1,
      probe: (candidate) async {
        probedHosts.add(candidate.host);
        return candidate.host == 'fd00::44';
      },
    );

    final reboundFuture = resolver.watch(_session()).first;
    await Future<void>.delayed(Duration.zero);
    discovery.add(_service(
      id: 'stable-device-id',
      addresses: [
        InternetAddress('192.168.1.44'),
        InternetAddress('fd00::44'),
      ],
    ));
    final rebound = await reboundFuture.timeout(const Duration(seconds: 2));

    expect(probedHosts, ['192.168.1.44', 'fd00::44']);
    expect(rebound.host, 'fd00::44');
    expect(rebound.port, 9090);
    expect(rebound.deviceId, 'stable-device-id');
    expect(rebound.sessionToken, 'trusted-token');
    expect(rebound.clientId, 'client-id');
  });

  test('ignores a different device ID and retries a matching endpoint',
      () async {
    final discovery = nsd.Discovery('discovery');
    final browser = _browser(discovery);
    addTearDown(browser.dispose);
    var attempts = 0;
    final resolver = TrustedSessionEndpointResolver(
      browser: browser,
      retryPolicy: _noDelayRetry,
      maxProbeAttempts: 2,
      probe: (_) async => ++attempts == 2,
    );

    final reboundFuture = resolver.watch(_session()).first;
    await Future<void>.delayed(Duration.zero);
    discovery.add(_service(
      id: 'another-device',
      addresses: [InternetAddress('192.168.1.33')],
    ));
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 0);

    discovery.add(_service(
      id: 'stable-device-id',
      name: 'Matching room',
      addresses: [InternetAddress('192.168.1.55')],
    ));
    final rebound = await reboundFuture.timeout(const Duration(seconds: 2));

    expect(attempts, 2);
    expect(rebound.host, '192.168.1.55');
  });

  test('rebinds when DNS transition still advertises the stale address',
      () async {
    final discovery = nsd.Discovery('discovery');
    final browser = _browser(discovery);
    addTearDown(browser.dispose);
    final probedHosts = <String>[];
    final resolver = TrustedSessionEndpointResolver(
      browser: browser,
      retryPolicy: _noDelayRetry,
      maxProbeAttempts: 1,
      probe: (candidate) async {
        probedHosts.add(candidate.host);
        return candidate.host == '192.168.1.88';
      },
    );

    final reboundFuture = resolver.watch(_session()).first;
    await Future<void>.delayed(Duration.zero);
    discovery.add(_service(
      id: 'stable-device-id',
      port: 8080,
      addresses: [
        InternetAddress('192.168.1.20'),
        InternetAddress('192.168.1.88'),
      ],
    ));
    final rebound = await reboundFuture.timeout(const Duration(seconds: 2));

    expect(probedHosts, ['192.168.1.20', '192.168.1.88']);
    expect(rebound.host, '192.168.1.88');
    expect(rebound.port, 8080);
  });

  test('identical DNS-SD refresh retries after a transient probe failure',
      () async {
    final browser = _ControllableBrowser();
    addTearDown(browser.dispose);
    var attempts = 0;
    final resolver = TrustedSessionEndpointResolver(
      browser: browser,
      maxProbeAttempts: 1,
      retryPolicy: _noDelayRetry,
      probe: (_) async => ++attempts >= 2,
    );
    final service = MimiCamDiscoveredService(
      name: 'Room',
      host: '192.168.1.55',
      port: 9090,
      addresses: [InternetAddress('192.168.1.55')],
      metadata: const {'id': 'stable-device-id'},
    );

    final reboundFuture = resolver.watch(_session()).first;
    await Future<void>.delayed(Duration.zero);
    browser.emit([service]);
    while (attempts < 1) {
      await Future<void>.delayed(Duration.zero);
    }
    browser.emit([service]);
    final rebound = await reboundFuture.timeout(const Duration(seconds: 2));

    expect(attempts, 2);
    expect(rebound.host, '192.168.1.55');
  });
}

class _ControllableBrowser extends MimiCamServiceBrowser {
  _ControllableBrowser()
      : super(
          startDiscovery: (_) async => nsd.Discovery('unused'),
          stopDiscovery: (_) async {},
        );

  final _controller =
      StreamController<List<MimiCamDiscoveredService>>.broadcast();
  List<MimiCamDiscoveredService> _current = const [];

  void emit(List<MimiCamDiscoveredService> services) {
    _current = List.unmodifiable(services);
    _controller.add(_current);
  }

  @override
  Stream<List<MimiCamDiscoveredService>> get updates => _controller.stream;

  @override
  List<MimiCamDiscoveredService> get services => _current;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => _controller.close();
}

MimiCamServiceBrowser _browser(nsd.Discovery discovery) =>
    MimiCamServiceBrowser(
      startDiscovery: (_) async => discovery,
      stopDiscovery: (_) async {},
      retryPolicy: _noDelayRetry,
    );

PairingSession _session() => PairingSession(
      payload: PairingPayload(
        schemaVersion: MimiCamProtocolV2.schemaVersion,
        host: '192.168.1.20',
        port: 8080,
        deviceId: 'stable-device-id',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs:
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'trusted-token',
      clientId: 'client-id',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      pairedAtMs: 123,
    );

nsd.Service _service({
  required String id,
  required List<InternetAddress> addresses,
  String name = 'Room',
  int port = 9090,
}) =>
    nsd.Service(
      name: name,
      type: MimiCamDiscoveryConfig.serviceType,
      port: port,
      addresses: addresses,
      txt: {
        'id': Uint8List.fromList(id.codeUnits),
        'v': Uint8List.fromList('2'.codeUnits),
      },
    );

final RetryPolicy _noDelayRetry = ExponentialBackoffPolicy(
  initialDelay: Duration.zero,
  maxDelay: Duration.zero,
);
