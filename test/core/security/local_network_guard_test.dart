import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/network/local_network_guard.dart';

void main() {
  test('private IPv4 blokları ve loopback kabul edilir', () {
    const guard = LocalNetworkGuard();

    expect(
        guard.isAllowedRemoteAddress(InternetAddress('192.168.1.20')), isTrue);
    expect(guard.isAllowedRemoteAddress(InternetAddress('10.0.0.42')), isTrue);
    expect(guard.isAllowedRemoteAddress(InternetAddress('172.16.0.7')), isTrue);
    expect(
        guard.isAllowedRemoteAddress(InternetAddress('172.31.255.9')), isTrue);
    expect(guard.isAllowedRemoteAddress(InternetAddress.loopbackIPv4), isTrue);
  });

  test('public ve private olmayan adresler reddedilir', () {
    const guard = LocalNetworkGuard();

    expect(guard.isAllowedRemoteAddress(InternetAddress('8.8.8.8')), isFalse);
    expect(
        guard.isAllowedRemoteAddress(InternetAddress('172.32.0.1')), isFalse);
  });

  test('ULA ve link-local kabul edilir; bağlamsız global IPv6 reddedilir', () {
    const guard = LocalNetworkGuard();

    expect(guard.isAllowedRemoteAddress(InternetAddress('fd00::20')), isTrue);
    expect(guard.isAllowedRemoteAddress(InternetAddress('fe80::20')), isTrue);
    expect(
      guard.isAllowedRemoteAddress(InternetAddress('2001:db8:42::20')),
      isFalse,
    );
    expect(guard.isAllowedRemoteAddress(InternetAddress('ff02::fb')), isFalse);
    expect(guard.isAllowedRemoteAddress(InternetAddress('::')), isFalse);
  });

  test('global IPv6 için eski uyumluluk davranışı açıkça seçilebilir', () {
    const guard = LocalNetworkGuard(
      allowGlobalIpv6WithoutPrefixContext: true,
    );

    expect(
      guard.isAllowedRemoteAddress(InternetAddress('2001:db8:42::20')),
      isTrue,
    );
  });

  test('known IPv6 interface prefix rejects a different global subnet', () {
    final guard = LocalNetworkGuard(localPrefixes: [
      LocalNetworkPrefix(
        address: InternetAddress('2001:db8:42::1'),
        prefixLength: 64,
      ),
    ]);

    expect(
      guard.isAllowedRemoteAddress(InternetAddress('2001:db8:42::99')),
      isTrue,
    );
    expect(
      guard.isAllowedRemoteAddress(InternetAddress('2001:db8:43::99')),
      isFalse,
    );
  });

  test('IPv4-mapped IPv6 follows the private IPv4 decision', () {
    const guard = LocalNetworkGuard();

    expect(
      guard.isAllowedRemoteAddress(InternetAddress('::ffff:192.168.1.20')),
      isTrue,
    );
    expect(
      guard.isAllowedRemoteAddress(InternetAddress('::ffff:8.8.8.8')),
      isFalse,
    );
  });
}
