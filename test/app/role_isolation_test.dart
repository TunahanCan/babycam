import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';

class SpyFactories {
  int serverCreates = 0;
  int clientCreates = 0;
  void resolve(AppRole role) {
    switch (role) {
      case AppRole.server:
        serverCreates++;
      case AppRole.client:
        clientCreates++;
    }
  }
}

void main() {
  test('role=server iken sadece ServerCompositionRoot çağrılır', () {
    final spy = SpyFactories()..resolve(AppRole.server);
    expect(spy.serverCreates, 1);
    expect(spy.clientCreates, 0);
  });

  test('role=client iken sadece ClientCompositionRoot çağrılır', () {
    final spy = SpyFactories()..resolve(AppRole.client);
    expect(spy.clientCreates, 1);
    expect(spy.serverCreates, 0);
  });
}
