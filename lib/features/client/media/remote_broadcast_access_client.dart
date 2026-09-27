import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../services/monetization/broadcast_access_service.dart';
import '../../../services/monetization/license_grant.dart';

/// Reads the room server's authoritative trial/entitlement state before a
/// client-side deadline is allowed to stop a live stream.
class RemoteBroadcastAccessClient {
  RemoteBroadcastAccessClient({
    this.timeout = const Duration(milliseconds: 1200),
    this.maxResponseBytes = 64 * 1024,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Duration timeout;
  final int maxResponseBytes;
  final HttpClient Function() _clientFactory;

  Future<BroadcastAccessSnapshot?> snapshot(PairingSession session) async {
    final decoded = await _request(session, MiuCamProtocolV2.status);
    return _snapshotFrom(decoded);
  }

  Future<bool> supportsActivation(PairingSession session) async {
    final decoded = await _request(session, MiuCamProtocolV2.status);
    return decoded['supportsBroadcastLicenseActivation'] == true;
  }

  Future<String?> readLicense(PairingSession session) async {
    final decoded = await _request(
      session,
      MiuCamProtocolV2.broadcastAccessLicense,
      allowNotFound: true,
    );
    final token = decoded['licenseToken'];
    if (token == null) return null;
    if (token is! String ||
        token.isEmpty ||
        token.length > LicenseGrantVerifier.maxTokenBytes) {
      throw const FormatException('Invalid room license response.');
    }
    return token;
  }

  Future<BroadcastAccessSnapshot> activate(
    PairingSession session,
    String licenseToken,
  ) async {
    if (licenseToken.isEmpty ||
        licenseToken.length > LicenseGrantVerifier.maxTokenBytes) {
      throw const FormatException('Invalid license token length.');
    }
    final decoded = await _request(
      session,
      MiuCamProtocolV2.broadcastAccessActivate,
      body: {'licenseToken': licenseToken},
    );
    final snapshot = _snapshotFrom(decoded);
    if (decoded['ok'] != true || snapshot == null) {
      throw const FormatException('Invalid room license activation response.');
    }
    return snapshot;
  }

  BroadcastAccessSnapshot? _snapshotFrom(Map<Object?, Object?> decoded) {
    final access = decoded['broadcastAccess'];
    if (access is! Map) return null;
    return BroadcastAccessSnapshot.fromJson(Map<Object?, Object?>.from(access));
  }

  Future<Map<Object?, Object?>> _request(
    PairingSession session,
    String path, {
    Map<String, Object?>? body,
    bool allowNotFound = false,
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(
            body == null ? 'GET' : 'POST',
            ServerEndpointBuilder(session).http(path),
          )
          .timeout(timeout);
      // A paired room may not redirect credentials or activation to a new peer.
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final responseBytes = await _readBoundedBody(response).timeout(timeout);
      if (allowNotFound && response.statusCode == HttpStatus.notFound) {
        return const {};
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Broadcast access status failed: ${response.statusCode}',
          uri: request.uri,
        );
      }
      final decoded = jsonDecode(utf8.decode(responseBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid room status response.');
      }
      return Map<Object?, Object?>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readBoundedBody(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
      throw const FormatException('Room status response is too large.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException('Room status response is too large.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}
