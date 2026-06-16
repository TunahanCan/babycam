import 'dart:convert';

class MimiCamProtocol {
  static const httpPort = 8080;
  static const discoveryPort = 45678;
  static const discoveryService = 'mimicam.v1';

  static const packetMetadata = 0;
  static const packetAudioPcm16Le = 1;
  static const packetVideoMjpeg = 2;
  static const packetAlertText = 3;

  static String discoveryPayload(String address) => jsonEncode({
        'service': discoveryService,
        'version': 2,
        'address': address,
        'video': 'mjpeg',
        'audio': 'pcm16le',
      });

  static String? parseDiscoveryAddress(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data, allowMalformed: true));
      if (decoded is! Map || decoded['service'] != discoveryService) {
        return null;
      }
      final address = decoded['address'];
      return address is String && address.isNotEmpty ? address : null;
    } on FormatException {
      return null;
    }
  }

  static List<int> alertFrame(String message) => [
        packetAlertText,
        ...utf8.encode(message),
      ];
}
