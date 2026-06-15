import 'dart:math';

class PairingTokenService {
  PairingTokenService({DateTime Function()? now, Duration nonceTtl = const Duration(minutes: 2)}) : _now = now ?? DateTime.now, _nonceTtl = nonceTtl;
  final DateTime Function() _now;
  final Duration _nonceTtl;
  final _random = Random.secure();
  final _nonces = <String, int>{};
  final _sessions = <String, ({String clientName, String deviceId})>{};

  String createPairingNonce() {
    final nonce = _randomToken();
    _nonces[nonce] = _now().add(_nonceTtl).millisecondsSinceEpoch;
    return nonce;
  }

  bool validateAndConsumeNonce(String nonce) {
    final expiry = _nonces.remove(nonce);
    if (expiry == null) return false;
    return _now().millisecondsSinceEpoch <= expiry;
  }

  String issueSessionToken({required String clientName, required String deviceId}) {
    final token = _randomToken(byteCount: 32);
    _sessions[token] = (clientName: clientName, deviceId: deviceId);
    return token;
  }

  bool validateSessionToken(String token) => _sessions.containsKey(token);
  void revokeSession(String token) => _sessions.remove(token);
  void revokeAll() => _sessions.clear();

  String _randomToken({int byteCount = 24}) => List<int>.generate(byteCount, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
