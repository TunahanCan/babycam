import 'pairing_payload.dart';

class PairingSession {
  const PairingSession({required this.payload, required this.sessionToken});
  final PairingPayload payload;
  final String sessionToken;
}
