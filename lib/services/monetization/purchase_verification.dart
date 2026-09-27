import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'license_grant.dart';

const trustedBackendVerificationAuthority = 'trusted_backend';

enum BroadcastPurchaseFailureReason {
  transient,
  rejected,
  revoked,
  configuration;

  static BroadcastPurchaseFailureReason fromCode(Object? code) =>
      values.where((value) => value.name == code).firstOrNull ?? rejected;
}

abstract interface class BroadcastLicenseRefresher {
  Future<BroadcastPurchaseVerification> refreshLicense(
    String licenseToken, {
    required String expectedProductId,
  });
}

abstract interface class BroadcastCheckoutPreflight {
  Future<bool> preflight({
    required String productId,
    required String source,
    required String licensePublicKey,
  });
}

abstract interface class CancellableBroadcastPurchaseVerifier {
  void cancelPending();
}

class BroadcastPurchaseVerification {
  const BroadcastPurchaseVerification._({
    required this.verified,
    required this.source,
    required this.authority,
    this.fingerprint,
    this.entitlementId,
    this.reason,
    this.failureReason,
    this.licenseToken,
  });

  const BroadcastPurchaseVerification.verified({
    required String source,
    required String fingerprint,
    required String entitlementId,
    String authority = trustedBackendVerificationAuthority,
    String? licenseToken,
  }) : this._(
          verified: true,
          source: source,
          authority: authority,
          fingerprint: fingerprint,
          entitlementId: entitlementId,
          licenseToken: licenseToken,
        );

  const BroadcastPurchaseVerification.rejected({
    required String source,
    required String reason,
    String authority = trustedBackendVerificationAuthority,
    BroadcastPurchaseFailureReason failureReason =
        BroadcastPurchaseFailureReason.rejected,
    String? fingerprint,
    String? entitlementId,
    String? licenseToken,
  }) : this._(
          verified: false,
          source: source,
          authority: authority,
          reason: reason,
          failureReason: failureReason,
          fingerprint: fingerprint,
          entitlementId: entitlementId,
          licenseToken: licenseToken,
        );

  final bool verified;
  final String source;
  final String authority;
  final String? fingerprint;
  final String? entitlementId;
  final String? reason;
  final BroadcastPurchaseFailureReason? failureReason;
  final String? licenseToken;
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
      failureReason: BroadcastPurchaseFailureReason.configuration,
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
      failureReason: BroadcastPurchaseFailureReason.configuration,
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
class TrustedBackendPurchaseVerifier
    implements
        BroadcastPurchaseVerifier,
        BroadcastLicenseRefresher,
        BroadcastCheckoutPreflight,
        CancellableBroadcastPurchaseVerifier {
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
  final _requests = <_PurchaseVerificationOperation>{};

  @override
  void cancelPending() {
    for (final request in _requests.toList()) {
      request.close();
    }
  }

  @override
  Future<bool> preflight({
    required String productId,
    required String source,
    required String licensePublicKey,
  }) async {
    if (licensePublicKey.isEmpty ||
        !endpoint.hasAuthority ||
        (!allowInsecureEndpointForTesting && endpoint.scheme != 'https')) {
      return false;
    }
    final operation = _PurchaseVerificationOperation(_clientFactory(), timeout);
    _requests.add(operation);
    final client = operation.client;
    try {
      final request = await operation.wait(client.postUrl(endpoint));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      final headers = await operation.wait(
          headersProvider?.call() ?? Future.value(const <String, String>{}));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.write(jsonEncode(
          {'preflight': true, 'productId': productId, 'source': source}));
      final response = await operation.wait(request.close());
      final body = await operation.wait(_readBoundedBody(response));
      if (response.statusCode != HttpStatus.ok) return false;
      final decoded = jsonDecode(utf8.decode(body));
      return decoded is Map &&
          decoded['ready'] == true &&
          decoded['productId'] == productId &&
          decoded['source'] == source &&
          decoded['licensePublicKey'] == licensePublicKey;
    } catch (_) {
      return false;
    } finally {
      operation.close();
      _requests.remove(operation);
    }
  }

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
    return _request(
      {
        'productId': purchase.productID,
        'source': source,
        'purchaseId': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        'serverVerificationData':
            purchase.verificationData.serverVerificationData,
        'localVerificationData':
            purchase.verificationData.localVerificationData,
      },
      expectedProductId: expectedProductId,
      expectedSource: source,
    );
  }

  @override
  Future<BroadcastPurchaseVerification> refreshLicense(
    String licenseToken, {
    required String expectedProductId,
  }) =>
      _request({'licenseToken': licenseToken},
          expectedProductId: expectedProductId);

  Future<BroadcastPurchaseVerification> _request(
    Map<String, Object?> payload, {
    required String expectedProductId,
    String? expectedSource,
  }) async {
    final source = expectedSource ?? '';
    if (!allowInsecureEndpointForTesting && endpoint.scheme != 'https') {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Purchase verification endpoint must use HTTPS.',
        failureReason: BroadcastPurchaseFailureReason.configuration,
      );
    }
    if (!endpoint.hasAuthority) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Purchase verification endpoint is invalid.',
        failureReason: BroadcastPurchaseFailureReason.configuration,
      );
    }

    final operation = _PurchaseVerificationOperation(_clientFactory(), timeout);
    _requests.add(operation);
    final client = operation.client;
    try {
      final request = await operation.wait(client.postUrl(endpoint));
      request.followRedirects = false;
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final headers = await operation.wait(
          headersProvider?.call() ?? Future.value(const <String, String>{}));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.write(jsonEncode(payload));
      final response = await operation.wait(request.close());
      final body = await operation.wait(_readBoundedBody(response));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason:
              'Trusted purchase verifier returned HTTP ${response.statusCode}.',
          failureReason:
              response.statusCode >= 500 || response.statusCode == 429
                  ? BroadcastPurchaseFailureReason.transient
                  : BroadcastPurchaseFailureReason.rejected,
        );
      }
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        throw const FormatException('Verifier response must be a JSON object.');
      }
      final json = Map<String, Object?>.from(decoded);
      final responseSource = json['source']?.toString() ?? source;
      final licenseToken = json['licenseToken'] is String
          ? (json['licenseToken'] as String).trim()
          : null;
      if (json['verified'] != true) {
        return BroadcastPurchaseVerification.rejected(
          source: responseSource,
          reason: json['reason']?.toString().trim().isNotEmpty == true
              ? json['reason'].toString().trim()
              : 'The store transaction was rejected by the trusted verifier.',
          failureReason:
              BroadcastPurchaseFailureReason.fromCode(json['reasonCode']),
          fingerprint: json['transactionFingerprint']?.toString(),
          entitlementId: json['entitlementId']?.toString(),
          licenseToken: licenseToken,
        );
      }
      if (json['productId']?.toString() != expectedProductId ||
          !StorePayloadPurchaseVerifier.supportedSources
              .contains(responseSource) ||
          (expectedSource != null && responseSource != expectedSource)) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason: 'Verifier response does not match the submitted transaction.',
        );
      }
      final fingerprint =
          json['transactionFingerprint']?.toString().trim() ?? '';
      final entitlementId = json['entitlementId']?.toString().trim() ?? '';
      if (fingerprint.length < 32 ||
          entitlementId.isEmpty ||
          licenseToken == null ||
          licenseToken.isEmpty ||
          licenseToken.length > LicenseGrantVerifier.maxTokenBytes) {
        return BroadcastPurchaseVerification.rejected(
          source: source,
          reason: 'Verifier response is missing trusted entitlement evidence.',
        );
      }
      return BroadcastPurchaseVerification.verified(
        source: responseSource,
        fingerprint: fingerprint,
        entitlementId: entitlementId,
        licenseToken: licenseToken,
      );
    } on TimeoutException {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Trusted purchase verification timed out.',
        failureReason: BroadcastPurchaseFailureReason.transient,
      );
    } catch (error) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Trusted purchase verification failed: $error',
        failureReason: BroadcastPurchaseFailureReason.transient,
      );
    } finally {
      operation.close();
      _requests.remove(operation);
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

class _PurchaseVerificationOperation {
  _PurchaseVerificationOperation(this.client, this.timeout) {
    client.connectionTimeout = timeout;
  }

  final HttpClient client;
  final Duration timeout;
  final _closed = Completer<void>();

  Future<T> wait<T>(Future<T> future) => Future.any<T>([
        future,
        _closed.future
            .then<T>((_) => throw StateError('Verification canceled.')),
      ]).timeout(timeout);

  void close() {
    if (!_closed.isCompleted) _closed.complete();
    client.close(force: true);
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

/// Reject an incomplete billing build before opening a chargeable store sheet.
/// Store receipts still require verification after checkout and on restore.
bool isPurchaseVerifierConfigured(BroadcastPurchaseVerifier verifier) {
  if (verifier is UnavailableBroadcastPurchaseVerifier ||
      verifier is StorePayloadPurchaseVerifier) {
    return false;
  }
  if (verifier is TrustedBackendPurchaseVerifier) {
    return verifier.endpoint.hasAuthority &&
        (verifier.endpoint.scheme == 'https' ||
            verifier.allowInsecureEndpointForTesting);
  }
  return true;
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
