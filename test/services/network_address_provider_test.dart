import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/network_address_provider.dart';

void main() {
  test('global IPv6 interface candidates produce distinct /64 prefixes', () {
    final prefixes = NetworkAddressProvider.ipv6PrefixesForCandidates(const [
      NetworkAddressCandidate(interfaceName: 'en0', address: '2001:db8:1::5'),
      NetworkAddressCandidate(interfaceName: 'en0', address: '2001:db8:1::9'),
      NetworkAddressCandidate(interfaceName: 'en1', address: '2001:db8:2::7'),
      NetworkAddressCandidate(interfaceName: 'en0', address: 'fe80::1%en0'),
    ]);

    expect(prefixes, hasLength(2));
    expect(
      prefixes.first.contains(InternetAddress('2001:db8:1::abcd')),
      isTrue,
    );
    expect(
      prefixes.first.contains(InternetAddress('2001:db8:2::abcd')),
      isFalse,
    );
  });

  test('Wi-Fi private IPv4 adresi virtual interface adreslerine tercih edilir',
      () {
    final host = NetworkAddressProvider.bestLocalHost(const [
      NetworkAddressCandidate(interfaceName: 'utun3', address: '10.8.0.2'),
      NetworkAddressCandidate(interfaceName: 'awdl0', address: '169.254.7.9'),
      NetworkAddressCandidate(interfaceName: 'en0', address: '192.168.1.42'),
    ]);

    expect(host, '192.168.1.42');
  });

  test('Android wlan private adresi ilk sirada olmayan adresten secilir', () {
    final host = NetworkAddressProvider.bestLocalHost(const [
      NetworkAddressCandidate(interfaceName: 'rmnet0', address: '100.64.1.4'),
      NetworkAddressCandidate(interfaceName: 'wlan0', address: '192.168.0.24'),
    ]);

    expect(host, '192.168.0.24');
  });

  test('kullanilamaz IPv4 adresleri elenir', () {
    final host = NetworkAddressProvider.bestLocalHost(const [
      NetworkAddressCandidate(interfaceName: 'en0', address: '169.254.1.2'),
      NetworkAddressCandidate(interfaceName: 'lo0', address: '127.0.0.1'),
      NetworkAddressCandidate(interfaceName: 'en1', address: '0.0.0.0'),
    ]);

    expect(host, isNull);
  });

  test('IPv6-only LAN ULA adresini global adresten once secer', () {
    final endpoint = NetworkAddressProvider.bestLocalEndpoint(const [
      NetworkAddressCandidate(
        interfaceName: 'wlan0',
        address: '2001:db8:42::8',
      ),
      NetworkAddressCandidate(interfaceName: 'wlan0', address: 'fd00::8'),
    ]);

    expect(endpoint?.host, 'fd00::8');
    expect(endpoint?.isIpv6, isTrue);
    expect(endpoint?.authority, '[fd00::8]:8080');
  });

  test('link-local IPv6 hostuna interface scope ekler', () {
    final endpoint = NetworkAddressProvider.bestLocalEndpoint(const [
      NetworkAddressCandidate(interfaceName: 'en0', address: 'fe80::12'),
    ]);

    expect(endpoint?.host, 'fe80::12%en0');
    expect(endpoint?.uri().host, contains('fe80::12'));
  });

  test('resolved address sirasi duplicate ve loopback adresleri eler', () {
    final ordered = NetworkAddressProvider.orderResolvedAddresses([
      InternetAddress.loopbackIPv4,
      InternetAddress('2001:db8:42::5'),
      InternetAddress('192.168.1.5'),
      InternetAddress('192.168.1.5'),
    ]);

    expect(ordered.map((address) => address.address), [
      '192.168.1.5',
      '2001:db8:42::5',
    ]);
  });
}
