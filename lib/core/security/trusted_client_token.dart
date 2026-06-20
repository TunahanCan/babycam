class TrustedClientToken {
  const TrustedClientToken(
      {required this.clientId, required this.token, required this.expiresAtMs});
  final String clientId;
  final String token;
  final int expiresAtMs;

  static const lifetime = Duration(days: 60);
  static const renewWindow = Duration(days: 7);

  bool isExpired(DateTime now) => now.millisecondsSinceEpoch >= expiresAtMs;
  bool shouldRenew(DateTime now) =>
      expiresAtMs - now.millisecondsSinceEpoch <= renewWindow.inMilliseconds;
}
