import 'dart:io';
import 'dart:typed_data';

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
}
