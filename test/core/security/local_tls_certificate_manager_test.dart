import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/security/local_tls_certificate_manager.dart';

void main() {
  test('loadOrCreate ilk çağrıda cert üretir ve sonra aynı certi yükler',
      () async {
    final store = MemoryLocalCertificateStore();
    final manager = LocalTlsCertificateManager(
      store: store,
      now: () => DateTime.utc(2026, 1, 1),
    );

    final first = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'Bebek Odası',
      currentHostIps: const ['127.0.0.1'],
    );
    final second = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'Bebek Odası',
      currentHostIps: const ['127.0.0.1'],
    );

    expect(first.fingerprintSha256Hex, isNotEmpty);
    expect(first.fingerprintSha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(second.fingerprintSha256Hex, first.fingerprintSha256Hex);
    expect(second.certificatePemBytes, first.certificatePemBytes);
    expect(second.privateKeyPemBytes, first.privateKeyPemBytes);
    expect(first.toString(), isNot(contains('BEGIN PRIVATE KEY')));
  });

  test('sertifika ve private key SecurityContext içine verilebilir', () async {
    final manager = LocalTlsCertificateManager(
      store: MemoryLocalCertificateStore(),
      now: () => DateTime.utc(2026, 1, 1),
    );
    final certificate = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'MimiCam Server',
      currentHostIps: const ['127.0.0.1'],
    );

    expect(
      () => manager.createServerSecurityContext(certificate),
      returnsNormally,
    );
  });

  test('dosya store meta fingerprint bozulursa sertifika yeniden üretilir',
      () async {
    final temp = await Directory.systemTemp.createTemp('mimicam_tls_test_');
    addTearDown(() => temp.delete(recursive: true));
    final store = FileLocalCertificateStore(directoryProvider: () => temp);
    final manager = LocalTlsCertificateManager(
      store: store,
      now: () => DateTime.utc(2026, 1, 1),
    );
    final first = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'MimiCam Server',
      currentHostIps: const ['127.0.0.1'],
    );
    final metaFile = File('${temp.path}/mimicam_tls/server_cert_meta.json');
    final meta = jsonDecode(await metaFile.readAsString()) as Map;
    await metaFile.writeAsString(jsonEncode({
      ...meta,
      'fingerprintSha256Hex': '00' * 32,
    }));

    final second = await manager.loadOrCreate(
      deviceId: 'server_local',
      deviceName: 'MimiCam Server',
      currentHostIps: const ['127.0.0.1'],
    );

    expect(second.fingerprintSha256Hex, isNot(first.fingerprintSha256Hex));
    expect(second.fingerprintSha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}
