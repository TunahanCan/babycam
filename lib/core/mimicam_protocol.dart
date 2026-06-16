import 'dart:convert';

class MimiCamProtocol {
  static const httpPort = 8080;

  static const packetMetadata = 0;
  static const packetAudioPcm16Le = 1;
  static const packetVideoMjpeg = 2;
  static const packetAlertText = 3;

  static List<int> alertFrame(String message) => [
        packetAlertText,
        ...utf8.encode(message),
      ];
}
