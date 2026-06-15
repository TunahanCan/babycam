import 'pairing_payload.dart';

class PairingSession {
  const PairingSession({required this.payload, required this.sessionToken, this.clientId = 'client_local', int? trustedClientTokenExpiresAtMs}) : trustedClientTokenExpiresAtMs = trustedClientTokenExpiresAtMs ?? 0;
  final PairingPayload payload;
  final String sessionToken;
  final String clientId;
  final int trustedClientTokenExpiresAtMs;

  bool shouldRenew(DateTime now) => trustedClientTokenExpiresAtMs > 0 && trustedClientTokenExpiresAtMs - now.millisecondsSinceEpoch <= const Duration(days: 7).inMilliseconds;
}
