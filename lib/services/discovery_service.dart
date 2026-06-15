import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/babycam_protocol.dart';

class DiscoveryService {
  RawDatagramSocket? _listener;
  RawDatagramSocket? _advertiser;
  Timer? _timer;

  Stream<String> listen() async* {
    _listener = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      BabyCamProtocol.discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    await for (final event in _listener!) {
      if (event != RawSocketEvent.read) continue;
      final datagram = _listener!.receive();
      if (datagram == null) continue;
      final address = BabyCamProtocol.parseDiscoveryAddress(datagram.data);
      if (address != null) yield address;
    }
  }

  Future<void> advertise(String address) async {
    _advertiser = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _advertiser!.broadcastEnabled = true;
    final payload = utf8.encode(BabyCamProtocol.discoveryPayload(address));
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _advertiser?.send(payload, InternetAddress('255.255.255.255'), BabyCamProtocol.discoveryPort),
    );
    _advertiser?.send(payload, InternetAddress('255.255.255.255'), BabyCamProtocol.discoveryPort);
  }

  void dispose() {
    _timer?.cancel();
    _listener?.close();
    _advertiser?.close();
  }
}
