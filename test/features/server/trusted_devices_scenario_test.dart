import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/features/server/presentation/server_pairing_section.dart';
import 'package:miucam/features/server/presentation/server_trusted_devices_card.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets(
      'same-name phones retain distinct identifiers in removal confirmation',
      (tester) async {
    final tokens = PairingTokenService();
    await tokens.issueTrustedClientTokenPersisted(
        clientName: 'Telefon', deviceId: 'parent-a');
    await tokens.issueTrustedClientTokenPersisted(
        clientName: 'Telefon', deviceId: 'parent-b');
    final runtime = _runtime(tokens);
    await tester.pumpWidget(_app(ServerTrustedDevicesCard(runtime: runtime)));
    await tester.pumpAndSettle();
    expect(find.text('Telefon'), findsNWidgets(2));
    expect(find.text('#parent-a'), findsOneWidget);
    expect(find.text('#parent-b'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('trusted-device-parent-b')),
        matching: find.byTooltip('Erişimi kaldır')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('#parent-b')),
        findsOneWidget);
    await tester.tap(find.text('Erişimi kaldır'));
    await tester.pumpAndSettle();
    expect(tokens.trustedClients.single.clientId, 'parent-a');
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
    tokens.dispose();
  });

  testWidgets('remembered device list updates live and owner can rename it',
      (tester) async {
    final tokens = PairingTokenService();
    final runtime = _runtime(tokens);
    await tester.pumpWidget(_app(ServerTrustedDevicesCard(runtime: runtime)));
    await tester.pumpAndSettle();
    expect(
        find.text('Henüz güvenilen bir ebeveyn cihazı yok.'), findsOneWidget);
    await tokens.issueTrustedClientTokenPersisted(
        clientName: 'Telefon', deviceId: 'parent');
    await tester.pumpAndSettle();
    expect(find.text('Telefon'), findsOneWidget);
    expect(find.text('Kayıtlı: 1/5'), findsOneWidget);
    await tester.tap(find.byTooltip('Cihaz adını değiştir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Annenin telefonu');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(tokens.trustedClients.single.clientName, 'Annenin telefonu');
    expect(find.text('Annenin telefonu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
    tokens.dispose();
  });

  testWidgets('failed removal remains visible and can be retried',
      (tester) async {
    final repository = _DeviceRepository();
    final tokens = PairingTokenService(trustedClientRepository: repository);
    final token = await tokens.issueTrustedClientTokenPersisted(
        clientName: 'Telefon', deviceId: 'parent');
    final runtime = _runtime(tokens);
    await tester.pumpWidget(_app(ServerTrustedDevicesCard(runtime: runtime)));
    await tester.pumpAndSettle();
    repository.fail = true;
    Future<void> remove() async {
      await tester.tap(find.byTooltip('Erişimi kaldır'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erişimi kaldır'));
      await tester.pumpAndSettle();
    }

    await remove();
    expect(tokens.validateTrustedClientToken(token.token), isNull);
    expect(
        find.text('Erişim engellendi · silme kaydı bekliyor'), findsOneWidget);
    expect(find.text('Kayıtlı: 0/5'), findsOneWidget);
    repository.fail = false;
    await remove();
    expect(find.text('Telefon'), findsNothing);
    expect(repository.records.where((r) => !r.revoked), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
    tokens.dispose();
  });

  for (final language in ['tr', 'en', 'zh', 'hi', 'es', 'fr', 'de', 'ar']) {
    testWidgets('five-device capacity and status fit narrow $language layout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tokens = PairingTokenService();
      for (var i = 0; i < 5; i++) {
        await tokens.issueTrustedClientTokenPersisted(
            clientName: 'Parent $i', deviceId: 'parent-$i');
      }
      final runtime = _runtime(tokens, active: {'parent-0'});
      final strings = AppStrings(Locale(language));
      await tester.pumpWidget(
          _app(ServerTrustedDevicesCard(runtime: runtime), language: language));
      await tester.pumpAndSettle();
      expect(
          find.text(strings
              .uiFormat('rememberedDeviceCount', {'count': 5, 'max': 5})),
          findsOneWidget);
      expect(
          find.text(
              strings.uiFormat('watchingDeviceCount', {'count': 1, 'max': 5})),
          findsOneWidget);
      expect(
          find.text(strings.ui('trustedDeviceCapacityFull')), findsOneWidget);
      expect(find.text(strings.ui('deviceWatching')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final key in [
        'trustedDeviceCapacityFull',
        'deviceRemovalSaveFailed',
        'renameDevice'
      ]) {
        expect(strings.ui(key), isNot(key));
        expect(strings.ui(key), isNot(contains('Nicht übersetzt')));
        expect(strings.ui(key), isNot(contains('غير مترجم')));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
      tokens.dispose();
    });
  }

  testWidgets('consuming QR replaces it immediately for the next phone',
      (tester) async {
    final tokens = PairingTokenService();
    var generated = 0;
    final runtime = _runtime(tokens, onStartPairing: () async {
      generated++;
      final nonce = tokens.createPairingNonce();
      return PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: '192.168.1.10',
        port: 8080,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: nonce,
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ).toUriString();
    });
    await runtime.startPairingMode();
    await tester.pumpWidget(_app(StreamBuilder<ServerRuntimeState>(
      stream: runtime.states,
      initialData: runtime.currentState,
      builder: (_, snapshot) =>
          ServerPairingSection(runtime: runtime, state: snapshot.data!),
    )));
    await tester.pumpAndSettle();
    final original = PairingPayload.parseUri(runtime.currentState.qrPayload!)!;
    expect(tokens.validateAndConsumeNonce(original.pairingNonce), isTrue);
    await tester.pumpAndSettle();
    final replacement =
        PairingPayload.parseUri(runtime.currentState.qrPayload!)!;
    expect(generated, 2);
    expect(replacement.pairingNonce, isNot(original.pairingNonce));
    expect(tokens.isPairingNonceActive(replacement.pairingNonce), isTrue);
    expect(find.byType(ServerTrustedDevicesCard), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
    tokens.dispose();
  });
}

ServerRuntime _runtime(
  PairingTokenService tokens, {
  Set<String> active = const {},
  Future<String> Function()? onStartPairing,
}) =>
    ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      trustedClients: () => tokens.trustedClients,
      trustedClientsChanged: tokens.trustedClientsChanged,
      activeWatchClientIds: () => active,
      isPairingNonceActive: tokens.isPairingNonceActive,
      onRenameTrustedClient: tokens.renameTrustedClientPersisted,
      onRevokeTrustedClient: tokens.revokeClientPersisted,
      onRevokeAllTrustedClients: tokens.revokeAllPersisted,
      onStartPairing: onStartPairing,
    );

Widget _app(Widget child, {String language = 'tr'}) => MaterialApp(
      locale: Locale(language),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

class _DeviceRepository implements TrustedClientRepository {
  bool fail = false;
  List<TrustedClientRecord> records = [];
  @override
  List<TrustedClientRecord> readAll() => List.of(records);
  @override
  Future<void> replaceAll(Iterable<TrustedClientRecord> clients) async {
    if (fail) throw StateError('storage failed');
    records = clients.toList();
  }
}
