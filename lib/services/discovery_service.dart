import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/mimicam_protocol.dart';

class DiscoveryService {
  RawDatagramSocket? _listener;
  RawDatagramSocket? _advertiser;
  Timer? _timer;

  Stream<String> listen() async* {
    _listener = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      MimiCamProtocol.discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    await for (final event in _listener!) {
      if (event != RawSocketEvent.read) continue;
      final datagram = _listener!.receive();
      if (datagram == null) continue;
      final address = MimiCamProtocol.parseDiscoveryAddress(datagram.data);
      if (address != null) yield address;
    }
  }

  Future<void> advertise(String address) async {
    _advertiser = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _advertiser!.broadcastEnabled = true;
    final payload = utf8.encode(MimiCamProtocol.discoveryPayload(address));
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _advertiser?.send(payload, InternetAddress('255.255.255.255'),
          MimiCamProtocol.discoveryPort),
    );
    _advertiser?.send(payload, InternetAddress('255.255.255.255'),
        MimiCamProtocol.discoveryPort);
  }

  void dispose() {
    _timer?.cancel();
    _listener?.close();
    _advertiser?.close();
  }
}
