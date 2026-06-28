import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/network_address_provider.dart';

void main() {
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
}
