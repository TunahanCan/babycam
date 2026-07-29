import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/network/lan_endpoint.dart';

void main() {
  test('parses hostname and IPv4 authorities', () {
    expect(
      LanEndpoint.parse('baby-room.local'),
      const LanEndpoint(host: 'baby-room.local', port: 8080),
    );
    expect(
      LanEndpoint.parse('192.168.1.12:9090'),
      const LanEndpoint(host: '192.168.1.12', port: 9090),
    );
  });

  test('parses bracketed and scoped IPv6 without losing the zone', () {
    expect(
      LanEndpoint.parse('[fd00::12]:9090'),
      const LanEndpoint(host: 'fd00::12', port: 9090),
    );
    expect(
      LanEndpoint.parse('[fe80::12%25en0]:8081'),
      const LanEndpoint(host: 'fe80::12%en0', port: 8081),
    );
    expect(
      LanEndpoint.parse('fe80::12%en0'),
      const LanEndpoint(host: 'fe80::12%en0', port: 8080),
    );
  });

  test('raw IPv6 never interprets the last segment as a port', () {
    final endpoint = LanEndpoint.parse('2001:db8::8080');

    expect(endpoint?.host, '2001:db8::8080');
    expect(endpoint?.port, 8080);
    expect(LanEndpoint.parse('[2001:db8::1]:70000'), isNull);
  });

  test('equivalent compressed IPv6 literals compare as the same host', () {
    expect(lanHostsEqual('fd00::1', 'fd00:0:0:0:0:0:0:1'), isTrue);
    expect(lanHostsEqual('fe80::1%en0', 'fe80::1%wlan0'), isFalse);
  });

  test('rejects malformed ports, user info and host text', () {
    expect(LanEndpoint.parse('http://room.local:not-a-port'), isNull);
    expect(LanEndpoint.parse('http://user@room.local:8080'), isNull);
    expect(LanEndpoint.parse('room name.local:8080'), isNull);
    expect(LanEndpoint.parse('fe80::invalid-zone%en0'), isNull);
  });
}
