import 'package:flutter/foundation.dart';

enum TransportSecurityMode {
  insecureHttpDevOnly,
  localTlsPinned,
}

class TransportSecurityConfig {
  const TransportSecurityConfig(this.mode);

  static const secureDefault =
      TransportSecurityConfig(TransportSecurityMode.localTlsPinned);
  static const insecureDevOnly =
      TransportSecurityConfig(TransportSecurityMode.insecureHttpDevOnly);

  final TransportSecurityMode mode;

  bool get isSecure => mode == TransportSecurityMode.localTlsPinned;
  String get httpScheme => isSecure ? 'https' : 'http';
  String get wsScheme => isSecure ? 'wss' : 'ws';
  String get tlsMode => isSecure ? 'selfSignedPinned' : 'insecureDevOnly';

  void validateForBuildMode({
    bool? debug,
    bool? profile,
    bool? release,
  }) {
    final isDebug = debug ?? kDebugMode;
    final isProfile = profile ?? kProfileMode;
    final isRelease = release ?? kReleaseMode;
    if (!isSecure && (isProfile || isRelease || !isDebug)) {
      throw StateError(
        'Insecure HTTP/WS transport is only allowed in debug builds.',
      );
    }
  }

  Map<String, Object?> toPayloadTransport() => {
        'httpScheme': httpScheme,
        'wsScheme': wsScheme,
        'tlsMode': tlsMode,
      };
}
