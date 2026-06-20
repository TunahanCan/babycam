import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/core/protocol/server_endpoint_builder.dart';

void main() {
  test('http path normalize eder ve query parametrelerini korur', () {
    final builder = ServerEndpointBuilder(_session());

    final uri = builder.http('status', query: {'streamToken': 'abc'});

    expect(uri.scheme, 'http');
    expect(uri.host, '192.168.1.20');
    expect(uri.port, 8080);
    expect(uri.path, '/status');
    expect(uri.queryParameters['streamToken'], 'abc');
  });

  test('ws path slash ile gelse de aynı endpointi üretir', () {
    final builder = ServerEndpointBuilder(_session());

    final uri = builder.ws('/events');

    expect(uri.toString(), 'ws://192.168.1.20:8080/events');
  });
}

PairingSession _session() => PairingSession(
      payload: PairingPayload(
        schemaVersion: 1,
        host: '192.168.1.20',
        port: 8080,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'token',
    );
