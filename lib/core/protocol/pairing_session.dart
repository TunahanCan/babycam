import 'pairing_payload.dart';

class PairingSession {
  const PairingSession({
    required this.payload,
    required this.sessionToken,
    this.clientId = 'client_local',
    int? trustedClientTokenExpiresAtMs,
    int? pairedAtMs,
  })  : trustedClientTokenExpiresAtMs = trustedClientTokenExpiresAtMs ?? 0,
        pairedAtMs = pairedAtMs ?? 0;

  final PairingPayload payload;
  final String sessionToken;
  final String clientId;
  final int trustedClientTokenExpiresAtMs;
  final int pairedAtMs;

  String get host => payload.host;
  int get port => payload.port;
  String get deviceId => payload.deviceId;
  String get deviceName => payload.deviceName;
  String get httpScheme => payload.httpScheme;
  String get wsScheme => payload.wsScheme;

  bool shouldRenew(DateTime now) =>
      trustedClientTokenExpiresAtMs > 0 &&
      trustedClientTokenExpiresAtMs - now.millisecondsSinceEpoch <=
          const Duration(days: 7).inMilliseconds;

  PairingSession copyWith({
    PairingPayload? payload,
    String? sessionToken,
    String? clientId,
    int? trustedClientTokenExpiresAtMs,
    int? pairedAtMs,
  }) =>
      PairingSession(
        payload: payload ?? this.payload,
        sessionToken: sessionToken ?? this.sessionToken,
        clientId: clientId ?? this.clientId,
        trustedClientTokenExpiresAtMs:
            trustedClientTokenExpiresAtMs ?? this.trustedClientTokenExpiresAtMs,
        pairedAtMs: pairedAtMs ?? this.pairedAtMs,
      );
}
