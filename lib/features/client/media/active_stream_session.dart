class ActiveStreamSession {
  const ActiveStreamSession({
    required this.streamToken,
    this.expiresAtMs,
  });

  final String streamToken;
  final int? expiresAtMs;
}
