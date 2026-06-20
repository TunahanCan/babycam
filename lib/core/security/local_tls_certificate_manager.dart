import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';

import 'certificate_fingerprint.dart';

class LocalTlsCertificate {
  const LocalTlsCertificate({
    required this.certificatePemBytes,
    required this.privateKeyPemBytes,
    required this.fingerprintSha256Hex,
    required this.createdAt,
    required this.expiresAt,
  });

  final List<int> certificatePemBytes;
  final List<int> privateKeyPemBytes;
  final String fingerprintSha256Hex;
  final DateTime createdAt;
  final DateTime expiresAt;
}

abstract class LocalCertificateStore {
  Future<LocalTlsCertificate?> load();
  Future<void> save(LocalTlsCertificate certificate);
}

class FileLocalCertificateStore implements LocalCertificateStore {
  FileLocalCertificateStore({Directory Function()? directoryProvider})
      : _directoryProvider = directoryProvider;

  final Directory Function()? _directoryProvider;

  Future<Directory> _directory() async {
    final base =
        _directoryProvider?.call() ?? await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/mimicam_tls');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<LocalTlsCertificate?> load() async {
    final directory = await _directory();
    final certFile = File('${directory.path}/server_cert.pem');
    final keyFile = File('${directory.path}/server_key.pem');
    final metaFile = File('${directory.path}/server_cert_meta.json');
    if (!await certFile.exists() ||
        !await keyFile.exists() ||
        !await metaFile.exists()) {
      return null;
    }
    final meta = jsonDecode(await metaFile.readAsString());
    if (meta is! Map) return null;
    final createdAt = DateTime.tryParse(meta['createdAt']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(meta['expiresAt']?.toString() ?? '');
    final storedFingerprint = meta['fingerprintSha256Hex']?.toString() ?? '';
    final certificatePemBytes = await certFile.readAsBytes();
    final fingerprint = _fingerprintForCertificatePemBytes(certificatePemBytes);
    if (createdAt == null ||
        expiresAt == null ||
        storedFingerprint.isEmpty ||
        !CertificateFingerprint.constantTimeEqualsHex(
          storedFingerprint,
          fingerprint,
        )) {
      return null;
    }
    return LocalTlsCertificate(
      certificatePemBytes: certificatePemBytes,
      privateKeyPemBytes: await keyFile.readAsBytes(),
      fingerprintSha256Hex: fingerprint,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> save(LocalTlsCertificate certificate) async {
    final directory = await _directory();
    await File('${directory.path}/server_cert.pem')
        .writeAsBytes(certificate.certificatePemBytes, flush: true);
    await File('${directory.path}/server_key.pem')
        .writeAsBytes(certificate.privateKeyPemBytes, flush: true);
    await File('${directory.path}/server_cert_meta.json').writeAsString(
      jsonEncode({
        'fingerprintSha256Hex': certificate.fingerprintSha256Hex,
        'createdAt': certificate.createdAt.toIso8601String(),
        'expiresAt': certificate.expiresAt.toIso8601String(),
      }),
      flush: true,
    );
  }
}

class MemoryLocalCertificateStore implements LocalCertificateStore {
  LocalTlsCertificate? certificate;

  @override
  Future<LocalTlsCertificate?> load() async => certificate;

  @override
  Future<void> save(LocalTlsCertificate certificate) async {
    this.certificate = certificate;
  }
}

class LocalTlsCertificateManager {
  LocalTlsCertificateManager({
    LocalCertificateStore? store,
    DateTime Function()? now,
  })  : _store = store ?? FileLocalCertificateStore(),
        _now = now ?? DateTime.now;

  final LocalCertificateStore _store;
  final DateTime Function() _now;

  Future<LocalTlsCertificate> loadOrCreate({
    required String deviceId,
    required String deviceName,
    required List<String> currentHostIps,
  }) async {
    final existing = await _store.load();
    if (existing != null && existing.expiresAt.isAfter(_now())) {
      return existing;
    }

    final certificate = _generate(
      deviceId: deviceId,
      deviceName: deviceName,
      currentHostIps: currentHostIps,
    );
    await _store.save(certificate);
    return certificate;
  }

  SecurityContext createServerSecurityContext(
    LocalTlsCertificate certificate,
  ) {
    final context = SecurityContext()
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;
    context.useCertificateChainBytes(certificate.certificatePemBytes);
    context.usePrivateKeyBytes(certificate.privateKeyPemBytes);
    return context;
  }

  LocalTlsCertificate _generate({
    required String deviceId,
    required String deviceName,
    required List<String> currentHostIps,
  }) {
    final now = _now().toUtc();
    final expiresAt = now.add(const Duration(days: 3650));
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final commonName =
        deviceName.trim().isEmpty ? 'MimiCam Server' : deviceName.trim();
    final sans = <String>{
      'localhost',
      '127.0.0.1',
      ...currentHostIps.where((ip) => ip.trim().isNotEmpty),
    }.toList(growable: false);
    final csr = X509Utils.generateRsaCsrPem(
      {
        'CN': commonName,
        'O': 'MimiCam',
        'OU': deviceId,
      },
      privateKey,
      publicKey,
      san: sans,
      signingAlgorithm: 'SHA-256',
    );
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
      sans: sans,
      extKeyUsage: const [ExtendedKeyUsage.SERVER_AUTH],
      cA: false,
      serialNumber: now.millisecondsSinceEpoch.toString(),
      notBefore: now.subtract(const Duration(minutes: 5)),
    );
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final certificatePemBytes = Uint8List.fromList(utf8.encode(certPem));
    return LocalTlsCertificate(
      certificatePemBytes: certificatePemBytes,
      privateKeyPemBytes: Uint8List.fromList(utf8.encode(keyPem)),
      fingerprintSha256Hex:
          _fingerprintForCertificatePemBytes(certificatePemBytes),
      createdAt: now,
      expiresAt: expiresAt,
    );
  }
}

String _fingerprintForCertificatePemBytes(List<int> certificatePemBytes) {
  final derBytes =
      CryptoUtils.getBytesFromPEMString(utf8.decode(certificatePemBytes));
  return CertificateFingerprint.sha256HexOfDer(derBytes);
}
