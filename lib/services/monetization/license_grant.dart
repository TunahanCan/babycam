import 'dart:convert';

import 'package:cryptography/cryptography.dart';

enum LicenseGrantStatus { active, revoked }

/// A backend-signed household entitlement, after signature/claim validation.
/// Pairing authorizes delivery to a room; an unsigned status snapshot does not.
class VerifiedLicenseGrant {
  const VerifiedLicenseGrant._({
    required this.token,
    required this.productId,
    required this.entitlementId,
    required this.source,
    required this.transactionFingerprint,
    required this.issuedAtMs,
    required this.status,
  });

  final String token;
  final String productId;
  final String entitlementId;
  final String source;
  final String transactionFingerprint;
  final int issuedAtMs;
  final LicenseGrantStatus status;
  int get version => 1;
  String get audience => 'miucam';
}

class LicenseGrantException implements Exception {
  const LicenseGrantException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// Verifies compact EdDSA JWTs using the backend's pinned Ed25519 public key.
/// Lifetime grants have no clock-based expiry. The service persists issuedAtMs
/// ordering, including revocations, to reject an older active grant on replay.
class LicenseGrantVerifier {
  LicenseGrantVerifier({List<int>? publicKey})
      : _publicKey = _readPublicKey(publicKey);

  static const maxTokenBytes = 12 * 1024;
  static const _maxJsonBytes = 8 * 1024;
  static const _configuredKey =
      String.fromEnvironment('MIUCAM_LICENSE_PUBLIC_KEY');
  final SimplePublicKey? _publicKey;

  bool get isConfigured => _publicKey != null;

  String? get publicKeyBase64Url {
    final key = _publicKey;
    return key == null ? null : base64Url.encode(key.bytes).replaceAll('=', '');
  }

  Future<VerifiedLicenseGrant> verify(
    String token, {
    required String expectedProductId,
  }) async {
    final publicKey = _publicKey;
    if (publicKey == null) {
      throw const LicenseGrantException(
        code: 'LICENSE_VERIFICATION_UNAVAILABLE',
        message: 'License signature verification is not configured.',
      );
    }
    if (token.length > maxTokenBytes) {
      throw const LicenseGrantException(
        code: 'LICENSE_TOKEN_TOO_LARGE',
        message: 'License token exceeds its size limit.',
      );
    }
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        throw const FormatException('Invalid token segments.');
      }
      final header = _decodeObject(parts[0], maxBytes: 1024);
      final claims = _decodeObject(parts[1], maxBytes: _maxJsonBytes);
      final signature = _decodeSegment(parts[2]);
      if (signature.length != 64 ||
          header.length != 2 ||
          header['alg'] != 'EdDSA' ||
          header['typ'] != 'JWT') {
        throw const FormatException('Unsupported license signature header.');
      }
      const claimNames = {
        'aud',
        'version',
        'productId',
        'entitlementId',
        'source',
        'transactionFingerprint',
        'issuedAtMs',
        'status',
      };
      if (claims.length != claimNames.length ||
          !claims.keys.every(claimNames.contains) ||
          claims['aud'] != 'miucam' ||
          claims['version'] is! int ||
          claims['version'] != 1) {
        throw const FormatException('Unsupported license claims.');
      }
      final productId = _requiredText(claims, 'productId');
      final entitlementId = _requiredText(claims, 'entitlementId');
      final source = _requiredText(claims, 'source');
      final fingerprint = _requiredText(claims, 'transactionFingerprint');
      final issuedAt = claims['issuedAtMs'];
      final status = claims['status'];
      if ((source != 'app_store' && source != 'google_play') ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
          issuedAt is! int ||
          issuedAt <= 0 ||
          issuedAt > 9007199254740991 ||
          (status != 'active' && status != 'revoked')) {
        throw const FormatException('Invalid license claim values.');
      }
      final valid = await Ed25519().verify(
        ascii.encode('${parts[0]}.${parts[1]}'),
        signature: Signature(signature, publicKey: publicKey),
      );
      if (!valid) throw const FormatException('Invalid license signature.');
      if (productId != expectedProductId) {
        throw const LicenseGrantException(
          code: 'LICENSE_PRODUCT_MISMATCH',
          message: 'License belongs to a different product.',
        );
      }
      return VerifiedLicenseGrant._(
        token: token,
        productId: productId,
        entitlementId: entitlementId,
        source: source,
        transactionFingerprint: fingerprint,
        issuedAtMs: issuedAt,
        status: status == 'active'
            ? LicenseGrantStatus.active
            : LicenseGrantStatus.revoked,
      );
    } on LicenseGrantException {
      rethrow;
    } catch (_) {
      throw const LicenseGrantException(
        code: 'INVALID_LICENSE_TOKEN',
        message: 'License signature or claims are invalid.',
      );
    }
  }

  static String _requiredText(Map<String, Object?> claims, String name) {
    final value = claims[name];
    if (value is! String ||
        value.isEmpty ||
        value.length > 256 ||
        value.trim() != value ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('Invalid license text claim.');
    }
    return value;
  }

  static Map<String, Object?> _decodeObject(String segment,
      {required int maxBytes}) {
    final bytes = _decodeSegment(segment);
    if (bytes.length > maxBytes) {
      throw const FormatException('License claims too large.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected license object.');
    }
    return decoded;
  }

  static List<int> _decodeSegment(String segment) {
    if (segment.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment)) {
      throw const FormatException('Invalid license base64url.');
    }
    final decoded = base64Url.decode(base64Url.normalize(segment));
    if (base64Url.encode(decoded).replaceAll('=', '') != segment) {
      throw const FormatException('Noncanonical license base64url.');
    }
    return decoded;
  }

  static SimplePublicKey? _readPublicKey(List<int>? injected) {
    try {
      final bytes = injected ??
          _decodeSegment(
              _configuredKey.trim().replaceFirst(RegExp(r'={1,2}$'), ''));
      if (bytes.length != 32 ||
          bytes.any((value) => value < 0 || value > 255)) {
        return null;
      }
      return SimplePublicKey(List<int>.of(bytes), type: KeyPairType.ed25519);
    } catch (_) {
      return null;
    }
  }
}
