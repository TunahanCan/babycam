import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/security/local_tls_certificate_manager.dart';
import 'package:mimicam/core/security/pinned_http_client_factory.dart';

void main() {
  test('pinned HTTPS client doğru fingerprint ile status çağırır', () async {
    final fixture = await _SecureServerFixture.start();
    addTearDown(fixture.close);

    final client = PinnedHttpClientFactory().create(
      expectedFingerprintSha256Hex: fixture.fingerprint,
      expectedHost: InternetAddress.loopbackIPv4.address,
      expectedPort: fixture.port,
    );
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(Uri(
      scheme: 'https',
      host: InternetAddress.loopbackIPv4.address,
      port: fixture.port,
      path: MimiCamProtocolV2.status,
    ));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer token');
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(await utf8.decoder.bind(response).join()), {'ok': true});
  });

  test('pinned HTTPS client yanlış fingerprint ile bağlanamaz', () async {
    final fixture = await _SecureServerFixture.start();
    addTearDown(fixture.close);

    final client = PinnedHttpClientFactory().create(
      expectedFingerprintSha256Hex: '00' * 32,
      expectedHost: InternetAddress.loopbackIPv4.address,
      expectedPort: fixture.port,
    );
    addTearDown(() => client.close(force: true));

    final request = client.getUrl(Uri(
      scheme: 'https',
      host: InternetAddress.loopbackIPv4.address,
      port: fixture.port,
      path: MimiCamProtocolV2.status,
    ));

    await expectLater(request, throwsA(anything));
  });

  test('wss events doğru fingerprint ile açılır', () async {
    final fixture = await _SecureServerFixture.start();
    addTearDown(fixture.close);

    final client = PinnedHttpClientFactory().create(
      expectedFingerprintSha256Hex: fixture.fingerprint,
      expectedHost: InternetAddress.loopbackIPv4.address,
      expectedPort: fixture.port,
    );
    addTearDown(() => client.close(force: true));

    final socket = await WebSocket.connect(
      Uri(
        scheme: 'wss',
        host: InternetAddress.loopbackIPv4.address,
        port: fixture.port,
        path: MimiCamProtocolV2.events,
      ).toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer token'},
      compression: CompressionOptions.compressionOff,
      customClient: client,
    );
    addTearDown(socket.close);

    expect(socket.readyState, WebSocket.open);
  });
}

class _SecureServerFixture {
  _SecureServerFixture(this.server, this.fingerprint);

  final HttpServer server;
  final String fingerprint;

  int get port => server.port;

  static Future<_SecureServerFixture> start() async {
    final manager = LocalTlsCertificateManager(
      store: MemoryLocalCertificateStore(),
      now: () => DateTime.utc(2026, 1, 1),
    );
    final certificate = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'MimiCam Server',
      currentHostIps: const ['127.0.0.1'],
    );
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      manager.createServerSecurityContext(certificate),
    );
    server.listen((request) async {
      if (request.uri.path == MimiCamProtocolV2.events &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.status) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    return _SecureServerFixture(server, certificate.fingerprintSha256Hex);
  }

  Future<void> close() => server.close(force: true);
}
