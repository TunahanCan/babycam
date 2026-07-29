import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const trustedBackendVerificationAuthority = 'trusted_backend';

class BroadcastPurchaseVerification {
  const BroadcastPurchaseVerification._({
    required this.verified,
    required this.source,
    required this.authority,
    this.fingerprint,
    this.entitlementId,
    this.reason,
  });

  const BroadcastPurchaseVerification.verified({
    required String source,
    required String fingerprint,
    required String entitlementId,
    String authority = trustedBackendVerificationAuthority,
  }) : this._(
          verified: true,
          source: source,
          authority: authority,
          fingerprint: fingerprint,
          entitlementId: entitlementId,
        );

  const BroadcastPurchaseVerification.rejected({
    required String source,
    required String reason,
    String authority = trustedBackendVerificationAuthority,
  }) : this._(
          verified: false,
          source: source,
          authority: authority,
          reason: reason,
        );

  final bool verified;
  final String source;
  final String authority;
  final String? fingerprint;
  final String? entitlementId;
  final String? reason;
}

abstract class BroadcastPurchaseVerifier {
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  });
}

/// Performs only local envelope validation and then fails closed.
///
/// Non-empty store payloads are evidence to send to Apple/Google through a
/// trusted backend; their presence is not proof that a transaction is valid.
class StorePayloadPurchaseVerifier implements BroadcastPurchaseVerifier {
  const StorePayloadPurchaseVerifier();

  static const supportedSources = {'app_store', 'google_play'};

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async {
    final preflight = validatePurchaseEnvelope(
      purchase,
      expectedProductId: expectedProductId,
    );
    if (preflight != null) return preflight;
    return BroadcastPurchaseVerification.rejected(
      source: purchase.verificationData.source.trim(),
      reason: 'Trusted backend purchase verification is not configured.',
    );
  }
}

class UnavailableBroadcastPurchaseVerifier
    implements BroadcastPurchaseVerifier {
  const UnavailableBroadcastPurchaseVerifier(this.reason);

  final String reason;

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async {
    final preflight = validatePurchaseEnvelope(
      purchase,
      expectedProductId: expectedProductId,
    );
    if (preflight != null) return preflight;
    return BroadcastPurchaseVerification.rejected(
      source: purchase.verificationData.source.trim(),
      reason: reason,
    );
  }
}

typedef PurchaseVerificationHeadersProvider = Future<Map<String, String>>
    Function();

/// Sends the opaque Apple/Google evidence to a trusted HTTPS backend.
///
/// The backend, not the app, must validate the transaction with the relevant
/// store and return a stable transaction fingerprint plus the entitlement id
/// shared by the paired devices. No store secret is embedded in the app.
class TrustedBackendPurchaseVerifier implements BroadcastPurchaseVerifier {
  TrustedBackendPurchaseVerifier({
    required this.endpoint,
    HttpClient Function()? clientFactory,
    this.headersProvider,
    this.timeout = const Duration(seconds: 12),
    this.maxResponseBytes = 64 * 1024,
    this.allowInsecureEndpointForTesting = false,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri endpoint;
  final HttpClient Function() _clientFactory;
  final PurchaseVerificationHeadersProvider? headersProvider;
  final Duration timeout;
  final int maxResponseBytes;
  final bool allowInsecureEndpointForTesting;

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async {
    final preflight = validatePurchaseEnvelope(
      purchase,
      expectedProductId: expectedProductId,
    );
    if (preflight != null) return preflight;
    final source = purchase.verificationData.source.trim();
    if (!allowInsecureEndpointForTesting && endpoint.scheme != 'https') {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Purchase verification endpoint must use HTTPS.',
      );
    }
    if (!endpoint.hasAuthority) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Purchase verification endpoint is invalid.',
      );
    }

    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final headers = await headersProvider?.call() ?? const <String, String>{};
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.write(jsonEncode({
        'productId': purchase.productID,
        'source': source,
        'purchaseId': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        'serverVerificationData':
            purchase.verificationData.serverVerificationData,
        'localVerificationData':
            purchase.verificationData.localVerificationData,
      }));
      final response = await request.close().timeout(timeout);
      final body = await _readBoundedBody(response).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason:
              'Trusted purchase verifier returned HTTP ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const FormatException('Verifier response must be a JSON object.');
      }
      final json = Map<String, Object?>.from(decoded);
      if (json['verified'] != true) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason: json['reason']?.toString().trim().isNotEmpty == true
              ? json['reason'].toString().trim()
              : 'The store transaction was rejected by the trusted verifier.',
        );
      }
      if (json['productId']?.toString() != expectedProductId ||
          json['source']?.toString() != source) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason: 'Verifier response does not match the submitted transaction.',
        );
      }
      final fingerprint =
          json['transactionFingerprint']?.toString().trim() ?? '';
      final entitlementId = json['entitlementId']?.toString().trim() ?? '';
      if (fingerprint.length < 32 || entitlementId.isEmpty) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason: 'Verifier response is missing trusted entitlement evidence.',
        );
      }
      return BroadcastPurchaseVerification.verified(
        source: source,
        fingerprint: fingerprint,
        entitlementId: entitlementId,
      );
    } on TimeoutException {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Trusted purchase verification timed out.',
      );
    } catch (error) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Trusted purchase verification failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readBoundedBody(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (builder.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Verifier response is too large.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

BroadcastPurchaseVerifier defaultBroadcastPurchaseVerifier() {
  const endpointText = String.fromEnvironment(
    'MIUCAM_PURCHASE_VERIFIER_URL',
  );
  if (endpointText.trim().isEmpty) {
    return const UnavailableBroadcastPurchaseVerifier(
      'Set MIUCAM_PURCHASE_VERIFIER_URL to a trusted HTTPS verifier.',
    );
  }
  final endpoint = Uri.tryParse(endpointText.trim());
  if (endpoint == null ||
      endpoint.scheme != 'https' ||
      !endpoint.hasAuthority) {
    return const UnavailableBroadcastPurchaseVerifier(
      'MIUCAM_PURCHASE_VERIFIER_URL must be a valid HTTPS URL.',
    );
  }
  return TrustedBackendPurchaseVerifier(endpoint: endpoint);
}

BroadcastPurchaseVerification? validatePurchaseEnvelope(
  PurchaseDetails purchase, {
  required String expectedProductId,
}) {
  final source = purchase.verificationData.source.trim();
  if (purchase.productID != expectedProductId) {
    return BroadcastPurchaseVerification.rejected(
      source: source,
      reason: 'The store transaction belongs to a different product.',
    );
  }
  if (!StorePayloadPurchaseVerifier.supportedSources.contains(source)) {
    return BroadcastPurchaseVerification.rejected(
      source: source,
      reason: 'Unknown purchase verification source.',
    );
  }
  if (purchase.status != PurchaseStatus.purchased &&
      purchase.status != PurchaseStatus.restored) {
    return BroadcastPurchaseVerification.rejected(
      source: source,
      reason: 'The transaction is not in a deliverable state.',
    );
  }
  if (purchase.verificationData.serverVerificationData.trim().isEmpty ||
      purchase.verificationData.localVerificationData.trim().isEmpty) {
    return BroadcastPurchaseVerification.rejected(
      source: source,
      reason: 'The store did not provide verification evidence.',
    );
  }
  return null;
}

String purchaseEvidenceFingerprint(PurchaseDetails purchase) => sha256
    .convert(utf8.encode([
      purchase.verificationData.source.trim(),
      purchase.productID,
      purchase.purchaseID ?? '',
      purchase.transactionDate ?? '',
      purchase.verificationData.serverVerificationData,
    ].join('\u0000')))
    .toString();
