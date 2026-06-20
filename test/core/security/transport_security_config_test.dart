import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/security/transport_security_config.dart';

void main() {
  test('localTlsPinned secure scheme üretir', () {
    const config =
        TransportSecurityConfig(TransportSecurityMode.localTlsPinned);

    expect(config.httpScheme, 'https');
    expect(config.wsScheme, 'wss');
    expect(config.isSecure, isTrue);
  });

  test('insecureHttpDevOnly debug scheme üretir', () {
    const config =
        TransportSecurityConfig(TransportSecurityMode.insecureHttpDevOnly);

    expect(config.httpScheme, 'http');
    expect(config.wsScheme, 'ws');
    expect(config.isSecure, isFalse);
  });

  test('release/profile benzeri modda insecure transport reddedilir', () {
    const config =
        TransportSecurityConfig(TransportSecurityMode.insecureHttpDevOnly);

    expect(
      () => config.validateForBuildMode(debug: false, release: true),
      throwsStateError,
    );
    expect(
      () => config.validateForBuildMode(debug: false, profile: true),
      throwsStateError,
    );
  });
}
