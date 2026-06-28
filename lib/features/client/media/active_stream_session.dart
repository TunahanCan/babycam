class ActiveStreamSession {
  const ActiveStreamSession({
    required this.streamToken,
    this.expiresAtMs,
    this.audioEnabled = false,
  });

  final String streamToken;
  final int? expiresAtMs;
  final bool audioEnabled;

  ActiveStreamSession copyWith({
    String? streamToken,
    int? expiresAtMs,
    bool? audioEnabled,
  }) =>
      ActiveStreamSession(
        streamToken: streamToken ?? this.streamToken,
        expiresAtMs: expiresAtMs ?? this.expiresAtMs,
        audioEnabled: audioEnabled ?? this.audioEnabled,
      );
}
