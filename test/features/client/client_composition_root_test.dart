import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/features/client/client_composition_root.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/pairing/pairing_session_store.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved pairing session client runtime icine restore edilir', () async {
    final payload = _payload();
    SharedPreferences.setMockInitialValues({
      'pairing_session': jsonEncode({
        'payload': payload.toJson(),
        'clientId': 'client-1',
        'trustedClientTokenExpiresAtMs':
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        'pairedAtMs': 1000,
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore()
      ..values['pairing_session_token'] = 'restored-token';

    final runtime = ClientCompositionRoot.create(
      preferences: preferences,
      strings: AppStrings(const Locale('tr')),
      secureTokens: secure,
    );
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.states.firstWhere((state) => state.session != null),
      completion(
        isA<ClientRuntimeState>()
            .having(
                (state) => state.phase, 'phase', ClientRuntimePhase.pairedIdle)
            .having((state) => state.session?.sessionToken, 'token',
                'restored-token')
            .having((state) => state.session?.payload.deviceName, 'room',
                'Bebek Odası'),
      ),
    );
    await expectLater(
      runtime.states.firstWhere((state) => state.alertsActive),
      completion(
        isA<ClientRuntimeState>()
            .having((state) => state.alertsActive, 'alertsActive', isTrue)
            .having(
              (state) => state.phase,
              'phase',
              ClientRuntimePhase.alertOnly,
            ),
      ),
    );
  });
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: MimiCamProtocolV2.schemaVersion,
      host: '127.0.0.1',
      port: 9,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http_ws'},
    );

class _FakeSecureTokenStore implements SecureTokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
