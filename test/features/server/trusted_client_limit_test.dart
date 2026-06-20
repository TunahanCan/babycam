import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';

void main() {
  test('en fazla 5 trusted client eşleşebilir, revoke slot açar', () {
    final service = PairingTokenService();

    for (var index = 0; index < 5; index++) {
      service.issueTrustedClientToken(
        clientName: 'Client $index',
        deviceId: 'client_$index',
      );
    }

    expect(service.pairedClientCount, 5);
    expect(
      () => service.issueTrustedClientToken(
        clientName: 'Client 6',
        deviceId: 'client_6',
      ),
      throwsA(isA<TrustedClientLimitException>()),
    );

    service.revokeClient('client_0');
    final token = service.issueTrustedClientToken(
      clientName: 'Client 6',
      deviceId: 'client_6',
    );

    expect(token.clientId, 'client_6');
    expect(service.pairedClientCount, 5);
  });
}
