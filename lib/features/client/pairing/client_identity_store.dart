import '../../../core/security/secure_random_token_generator.dart';
import 'pairing_session_store.dart';

class ClientIdentityStore {
  ClientIdentityStore({
    SecureTokenStore? secureTokens,
    SecureRandomTokenGenerator? tokenGenerator,
  })  : _secureTokens = secureTokens ?? const FlutterSecureTokenStore(),
        _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator();

  static const _clientIdKey = 'mimicam_client_id';

  final SecureTokenStore _secureTokens;
  final SecureRandomTokenGenerator _tokenGenerator;

  Future<String> clientId() async {
    final existing = await _secureTokens.read(key: _clientIdKey);
    final normalized = _normalize(existing);
    if (normalized != null && normalized != 'client_local') return normalized;
    final next = 'client_${_tokenGenerator.generateHex(byteCount: 8)}';
    await _secureTokens.write(key: _clientIdKey, value: next);
    return next;
  }

  String? _normalize(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
