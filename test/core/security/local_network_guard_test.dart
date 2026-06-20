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
}
