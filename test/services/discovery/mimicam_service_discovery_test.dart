import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mimicam/core/network/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/discovery/mimicam_service_discovery.dart';
import 'package:nsd/nsd.dart' as nsd;

void main() {
  test('advertiser registers protocol and transport metadata', () async {
    nsd.Service? registered;
    nsd.Registration? unregistered;
    final advertiser = MimiCamServiceAdvertiser(
      registerService: (service) async {
        registered = service;
        return nsd.Registration('registration', service);
      },
      unregisterService: (registration) async {
        unregistered = registration;
      },
    );

    await advertiser.start(
      name: 'Bebek Odası',
      deviceId: 'server-1',
      port: 8080,
      protocolVersion: 2,
      webRtcAvailable: true,
    );

    expect(registered?.type, MimiCamDiscoveryConfig.serviceType);
    expect(registered?.port, 8080);
    expect(String.fromCharCodes(registered!.txt!['v']!), '2');
    expect(String.fromCharCodes(registered!.txt!['webrtc']!), '1');

    await advertiser.stop();
    expect(unregistered, isNotNull);
  });

  test('advertiser keeps an injected ID and refreshes same-port metadata',
      () async {
    final registered = <nsd.Service>[];
    var unregistered = 0;
    final advertiser = MimiCamServiceAdvertiser(
      deviceIdProvider: () async => 'stable-device-id',
      registerService: (service) async {
        registered.add(service);
        return nsd.Registration('registration-${registered.length}', service);
      },
      unregisterService: (_) async => unregistered++,
      retryPolicy: _noDelayRetry,
    );
    addTearDown(advertiser.dispose);

    Future<void> start({required bool webRtc}) => advertiser.start(
          name: 'Room',
          deviceId: 'temporary-id',
          port: 8080,
          protocolVersion: 2,
          webRtcAvailable: webRtc,
        );

    await start(webRtc: true);
    await start(webRtc: true);
    await start(webRtc: false);

    expect(registered, hasLength(2));
    expect(unregistered, 1);
    expect(
        String.fromCharCodes(registered.last.txt!['id']!), 'stable-device-id');
    expect(String.fromCharCodes(registered.last.txt!['webrtc']!), '0');
    expect(advertiser.activeDeviceId, 'stable-device-id');
  });

  test('advertiser retries transient registration failures', () async {
    var attempts = 0;
    final advertiser = MimiCamServiceAdvertiser(
      registerService: (service) async {
        attempts++;
        if (attempts == 1) throw StateError('transient');
        return nsd.Registration('registration', service);
      },
      unregisterService: (_) async {},
      retryPolicy: _noDelayRetry,
      maxAttempts: 2,
    );
    addTearDown(advertiser.dispose);

    await advertiser.start(
      name: 'Room',
      deviceId: 'server-1',
      port: 8080,
      protocolVersion: 2,
      webRtcAvailable: true,
    );

    expect(attempts, 2);
    expect(advertiser.isAdvertising, isTrue);
  });

  test('browser emits resolved IPv4 and IPv6 services and removes lost ones',
      () async {
    final discovery = nsd.Discovery('discovery');
    final browser = MimiCamServiceBrowser(
      startDiscovery: (_) async => discovery,
      stopDiscovery: (_) async {},
    );
    addTearDown(browser.dispose);
    final updates = <List<MimiCamDiscoveredService>>[];
    final subscription = browser.updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await browser.start();
    final service = nsd.Service(
      name: 'Room',
      type: MimiCamDiscoveryConfig.serviceType,
      port: 8080,
      addresses: [
        InternetAddress('fd00::12'),
        InternetAddress('192.168.1.12'),
      ],
      txt: {
        'id': Uint8List.fromList('room-1'.codeUnits),
        'webrtc': Uint8List.fromList('1'.codeUnits),
      },
    );
    discovery.add(service);
    await Future<void>.delayed(Duration.zero);

    expect(browser.services.single.host, '192.168.1.12');
    expect(browser.services.single.webRtcAvailable, isTrue);
    expect(browser.services.single.authority, '192.168.1.12:8080');

    discovery.remove(service);
    await Future<void>.delayed(Duration.zero);
    expect(browser.services, isEmpty);
    expect(updates, isNotEmpty);
  });

  test('unscoped link-local IPv6 keeps the resolvable mDNS hostname', () async {
    final discovery = nsd.Discovery('discovery');
    final browser = MimiCamServiceBrowser(
      startDiscovery: (_) async => discovery,
      stopDiscovery: (_) async {},
    );
    addTearDown(browser.dispose);
    await browser.start();
    discovery.add(nsd.Service(
      name: 'Room',
      type: MimiCamDiscoveryConfig.serviceType,
      host: 'room.local',
      port: 8080,
      addresses: [InternetAddress('fe80::12')],
      txt: {'id': Uint8List.fromList('room-link-local'.codeUnits)},
    ));
    await Future<void>.delayed(Duration.zero);

    expect(browser.services.single.host, 'room.local');
    expect(
      browser.services.single.endpoints.map((endpoint) => endpoint.host),
      ['room.local'],
    );
  });

  test('browser serializes concurrent start and stop operations', () async {
    final discoveryCompleter = Completer<nsd.Discovery>();
    var starts = 0;
    var stops = 0;
    final browser = MimiCamServiceBrowser(
      startDiscovery: (_) {
        starts++;
        return discoveryCompleter.future;
      },
      stopDiscovery: (_) async => stops++,
      retryPolicy: _noDelayRetry,
    );
    addTearDown(browser.dispose);

    final first = browser.start();
    final second = browser.start();
    await Future<void>.delayed(Duration.zero);

    expect(starts, 1);
    discoveryCompleter.complete(nsd.Discovery('discovery'));
    await Future.wait([first, second]);
    await Future.wait([browser.stop(), browser.stop()]);

    expect(starts, 1);
    expect(stops, 1);
  });

  test('browser retries discovery and keys metadata refresh by stable ID',
      () async {
    final discovery = nsd.Discovery('discovery');
    var attempts = 0;
    final browser = MimiCamServiceBrowser(
      startDiscovery: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('transient');
        return discovery;
      },
      stopDiscovery: (_) async {},
      retryPolicy: _noDelayRetry,
      maxAttempts: 2,
    );
    addTearDown(browser.dispose);
    await browser.start();

    final previous = _service(
      name: 'Room',
      port: 8080,
      host: '192.168.1.12',
      id: 'stable-room-id',
      webRtc: true,
    );
    final refreshed = _service(
      name: 'Room Renamed',
      port: 9090,
      host: 'fd00::12',
      id: 'stable-room-id',
      webRtc: false,
    );
    discovery.add(previous);
    await Future<void>.delayed(Duration.zero);
    expect(browser.services.single.name, 'Room');

    discovery.remove(previous);
    discovery.add(refreshed);
    await Future<void>.delayed(Duration.zero);

    expect(attempts, 2);
    expect(browser.services, hasLength(1));
    expect(browser.services.single.name, 'Room Renamed');
    expect(browser.services.single.port, 9090);
    expect(browser.services.single.host, 'fd00::12');
    expect(browser.services.single.webRtcAvailable, isFalse);
  });

  test('browser preserves duplicate IDs so trusted matching stays ambiguous',
      () async {
    final discovery = nsd.Discovery('discovery');
    final browser = MimiCamServiceBrowser(
      startDiscovery: (_) async => discovery,
      stopDiscovery: (_) async {},
      retryPolicy: _noDelayRetry,
    );
    addTearDown(browser.dispose);
    await browser.start();

    final first = _service(
      name: 'First room',
      port: 8080,
      host: '192.168.1.12',
      id: 'legacy-shared-id',
      webRtc: true,
    );
    final second = _service(
      name: 'Second room',
      port: 8080,
      host: '192.168.1.13',
      id: 'legacy-shared-id',
      webRtc: true,
    );
    discovery.add(first);
    discovery.add(second);
    await Future<void>.delayed(Duration.zero);

    expect(browser.services, hasLength(2));

    discovery.remove(first);
    await Future<void>.delayed(Duration.zero);
    expect(browser.services.single.name, 'Second room');
  });
}

final RetryPolicy _noDelayRetry = ExponentialBackoffPolicy(
  initialDelay: Duration.zero,
  maxDelay: Duration.zero,
);

nsd.Service _service({
  required String name,
  required int port,
  required String host,
  required String id,
  required bool webRtc,
}) =>
    nsd.Service(
      name: name,
      type: MimiCamDiscoveryConfig.serviceType,
      port: port,
      addresses: [InternetAddress(host)],
      txt: {
        'id': Uint8List.fromList(id.codeUnits),
        'webrtc': Uint8List.fromList((webRtc ? '1' : '0').codeUnits),
      },
    );
