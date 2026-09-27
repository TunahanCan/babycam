import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/broadcast_purchase_coordinator.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:miucam/services/monetization/pending_room_activation_repository.dart';
import 'package:miucam/services/monetization/room_broadcast_access_gateway.dart';
import 'package:miucam/services/monetization/shared_preferences_pending_room_activation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/license_token_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forgetting a room during preflight prevents checkout', () async {
    final h = await _Harness.create();
    h.remote.holdSupport = Completer<void>();
    try {
      final purchase = h.coordinator.purchaseForRoom(_session('A'));
      await h.remote.supportEntered.future;
      await h.coordinator.forgetRoom('A');
      h.remote.holdSupport!.complete();
      expect(await purchase, isNull);
      expect(h.gateway.purchases, 0);
      expect(h.remote.snapshotReads, 0);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.ready);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test(
      'unpair during checkout preserves payment without delivering to old room',
      () async {
    final h = await _Harness.create();
    h.gateway.hold = Completer<void>();
    try {
      final purchase = h.coordinator.purchaseForRoom(_session('A'));
      await h.gateway.entered.future;
      await h.coordinator.forgetRoom('A');
      h.gateway.hold!.complete();
      expect(await purchase, isNull);
      await _until(() => !h.coordinator.operationInProgress);
      expect(h.access.licenseToken, h.token);
      expect(h.remote.activated, isEmpty);
      expect(h.gateway.purchases, 1);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.ready);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      await h.coordinator.purchaseForRoom(_session('B'));
      expect(h.remote.activated.single.deviceId, 'B');
      expect(h.gateway.purchases, 1);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('re-pairing the same room invalidates its old in-flight activation',
      () async {
    final h = await _Harness.create();
    h.remote.holdFirstSnapshot = Completer<void>();
    try {
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(h.token, expectedProductId: BroadcastAccessConfig.productId));
      h.coordinator.attachSession(_session('A', token: 'old-session'));
      await h.remote.snapshotEntered.future;
      await h.coordinator.forgetRoom('A');
      h.coordinator.attachSession(_session('A', token: 'new-session'));
      h.remote.holdFirstSnapshot!.complete();
      await _until(() => !h.coordinator.operationInProgress);
      await h.coordinator.retryPending();
      expect(h.remote.activated.single.sessionToken, 'new-session');
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.activated);
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('late activation response cannot restore a forgotten room state',
      () async {
    final h = await _Harness.create();
    h.remote.holdFirstActivation = Completer<void>();
    try {
      final purchase = h.coordinator.purchaseForRoom(_session('A'));
      await h.remote.activationEntered.future;
      await h.coordinator.forgetRoom('A');
      h.remote.holdFirstActivation!.complete();
      expect(await purchase, isNull);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.ready);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      expect(h.access.licenseToken, h.token);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('destination storage failure prevents a chargeable checkout', () async {
    final h = await _Harness.create(pendingActivations: _FailingDestinations());
    try {
      expect(await h.coordinator.purchaseForRoom(_session('A')), isNull);
      expect(h.gateway.purchases, 0);
      expect(h.remote.activated, isEmpty);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.failed);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('cleanup failure keeps delivered access visible and retries the cleanup',
      () async {
    final destinations = _CleanupFailingDestinations();
    final h = await _Harness.create(pendingActivations: destinations);
    h.coordinator.onBackground();
    try {
      final delivered = await h.coordinator.purchaseForRoom(_session('A'));
      expect(delivered?.unlocked, isTrue);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.activated);
      expect(destinations.load(), {'A'});
      expect(h.remote.activated.length, 1);

      destinations.failCleanup = false;
      // A real room now reports the delivered entitlement as active; retrying
      // disk cleanup must not open checkout or send another activation token.
      h.remote.roomSnapshots['A'] = delivered!;
      await h.coordinator.onForeground();
      await _until(() => !h.coordinator.operationInProgress);
      expect(destinations.load(), isEmpty);
      expect(h.remote.activated.length, 1);
      expect(h.gateway.purchases, 1);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.activated);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('checkout remains bound to A while the parent changes to room B',
      () async {
    final h = await _Harness.create();
    h.gateway.hold = Completer<void>();
    final runtime = ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: payload.deviceId),
      purchases: h.coordinator,
    );
    try {
      await runtime.pairWithServer(_session('A').payload);
      final purchase = runtime.unlockBroadcastAccess();
      await h.gateway.entered.future;
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          ['A']);
      await runtime.pairWithServer(_session('B').payload);
      h.gateway.hold!.complete();
      await purchase;
      await _until(() => !h.coordinator.operationInProgress);
      expect(h.remote.activated.first.deviceId, 'A');
      expect(h.gateway.purchases, 1);
      expect(runtime.currentState.session!.deviceId, 'B');
      expect(h.remote.activated.map((e) => e.deviceId), ['A']);
      expect(runtime.currentState.broadcastAccess, isNull,
          reason: 'Completing A checkout must not update room B presentation.');
      expect((await h.access.snapshot()).usedMs, 0,
          reason: 'Parent checkout never starts a second local trial.');
    } finally {
      await runtime.dispose();
      await h.coordinator.dispose();
    }
  });

  test(
      'offline activation survives app recreation and retries without a charge',
      () async {
    final h = await _Harness.create();
    h.remote.offline = true;
    await h.coordinator.purchaseForRoom(_session('A'));
    await _until(() => !h.coordinator.operationInProgress);
    expect(h.coordinator.stateFor('A').phase,
        ParentPurchasePhase.activationPending);
    expect(h.access.licenseToken, h.token);
    await h.coordinator.dispose();

    final gateway = _Gateway(h.token);
    final service = BroadcastAccessService(h.preferences,
        purchaseGateway: gateway, licenseGrantVerifier: h.verifier);
    final remote = _Remote();
    final reopened = BroadcastPurchaseCoordinator(
      pendingActivations:
          SharedPreferencesPendingRoomActivationRepository(h.preferences),
      access: service,
      remote: remote,
      licenseVerifier: h.verifier,
    );
    try {
      await service.snapshot();
      reopened.attachSession(_session('A', token: 'renewed-token'));
      await _until(
          () => reopened.stateFor('A').phase == ParentPurchasePhase.activated);
      expect(remote.activated.single.sessionToken, 'renewed-token');
      expect(gateway.purchases, 0);
      expect(gateway.restores, 0);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
    } finally {
      await reopened.dispose();
    }
  });

  test('missing key or unsupported room never opens a chargeable checkout',
      () async {
    for (final keyConfigured in [false, true]) {
      final h = await _Harness.create(keyConfigured: keyConfigured);
      h.remote.supported = !keyConfigured;
      try {
        await h.coordinator.purchaseForRoom(_session('A'));
        expect(h.gateway.purchases, 0);
        expect(
            h.coordinator.stateFor('A').phase,
            keyConfigured
                ? ParentPurchasePhase.roomUpdateRequired
                : ParentPurchasePhase.unavailable);
      } finally {
        await h.coordinator.dispose();
      }
    }
  });

  test('paired licensed room shares a signed family grant without checkout',
      () async {
    final h = await _Harness.create();
    h.remote.roomSnapshots['A'] = _locked.copyWith(unlocked: true);
    h.remote.roomTokens['A'] = h.token;
    try {
      await h.coordinator.purchaseForRoom(_session('A'));
      expect(h.gateway.purchases, 0);
      expect(h.gateway.restores, 0);
      expect(h.access.licenseToken, h.token);
      await _until(() => !h.coordinator.operationInProgress);
      await h.coordinator.purchaseForRoom(_session('B'));
      expect(h.remote.activated.map((e) => e.deviceId), contains('B'));
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('legacy local purchase restores instead of charging a second time',
      () async {
    final h = await _Harness.create(legacy: true);
    try {
      expect(h.coordinator.requiresRestore, isTrue);
      await h.coordinator.purchaseForRoom(_session('A'));
      expect(h.gateway.purchases, 0);
      expect(h.gateway.restores, 1);
      expect(h.remote.activated.map((e) => e.deviceId), contains('A'));
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('server role teardown borrows the app-owned purchase listener',
      () async {
    final h = await _Harness.create();
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      broadcastAccess: h.access,
      broadcastAccessChanges: h.access.changes,
      ownsBroadcastAccess: false,
    );
    await runtime.dispose();
    expect(h.gateway.disposed, isFalse);
    await h.coordinator.purchaseForRoom(_session('A'));
    expect(h.access.licenseToken, h.token);
    await h.coordinator.dispose();
    expect(h.gateway.disposed, isTrue);
  });

  test('parent price comes from its own store, not the room store', () async {
    final h = await _Harness.create();
    try {
      await _until(() => h.coordinator.localPrice != null);
      expect(h.coordinator.localPrice, '£7.99');
      expect(_locked.priceLabel, '€4,99');
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('restore without a purchase clears pending activation and explains why',
      () async {
    final h = await _Harness.create();
    h.gateway.restoreResult = const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.noPurchaseFound);
    try {
      await h.coordinator.purchaseForRoom(_session('A'), restore: true);
      expect(h.coordinator.stateFor('A').phase,
          ParentPurchasePhase.noPurchaseFound);
      expect(h.gateway.restores, 1);
      expect(h.gateway.purchases, 0);
      expect(h.remote.activated, isEmpty);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('a signed revocation arriving during activation is delivered next',
      () async {
    final h = await _Harness.create();
    final fixture = await LicenseTokenFixture.create();
    final revoked = await fixture.token(claims: {
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    });
    h.remote.holdFirstActivation = Completer<void>();
    h.remote.revokedToken = revoked;
    try {
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(h.token, expectedProductId: BroadcastAccessConfig.productId));
      h.coordinator.attachSession(_session('A'));
      await h.remote.activationEntered.future;
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(revoked, expectedProductId: BroadcastAccessConfig.productId));
      h.remote.holdFirstActivation!.complete();
      await _until(() =>
          h.remote.activationTokens.length == 2 &&
          !h.coordinator.operationInProgress);
      expect(h.remote.activationTokens, [h.token, revoked]);
      expect(h.coordinator.stateFor('A').access!.unlocked, isFalse);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.revoked);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('store-confirmed revocation is distinct from pending verification',
      () async {
    final h = await _Harness.create();
    h.gateway.restoreResult = const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        failureReason: BroadcastPurchaseFailureReason.revoked);
    try {
      await h.coordinator.purchaseForRoom(_session('A'), restore: true);
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.revoked);
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('an already licensed room does not retry the older active parent grant',
      () async {
    final h = await _Harness.create();
    h.remote.roomSnapshots['A'] = _locked.copyWith(unlocked: true);
    h.remote.rejectedToken = h.token;
    try {
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(h.token, expectedProductId: BroadcastAccessConfig.productId));
      await _until(() => h.coordinator.hasLicense);
      h.coordinator.attachSession(_session('A'));
      await _until(() =>
          h.remote.snapshotReads > 0 || h.remote.activationTokens.isNotEmpty);
      await _until(() =>
          !h.coordinator.operationInProgress &&
          (h.coordinator.stateFor('A').access != null ||
              h.coordinator.stateFor('A').phase ==
                  ParentPurchasePhase.activationPending));
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.activated);
      expect(h.remote.activationTokens, isEmpty);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('background activation waits for foreground and never repeats payment',
      () async {
    final h = await _Harness.create();
    try {
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(h.token, expectedProductId: BroadcastAccessConfig.productId));
      h.coordinator.onBackground();
      h.coordinator.attachSession(_session('A'));
      await Future<void>.delayed(Duration.zero);
      expect(h.remote.activated, isEmpty);
      await h.coordinator.onForeground();
      await _until(() => !h.coordinator.operationInProgress);
      expect(h.remote.activated.single.deviceId, 'A');
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });

  test('revocation during an unlocked-room probe is still delivered', () async {
    final h = await _Harness.create();
    final fixture = await LicenseTokenFixture.create();
    final revoked = await fixture.token(claims: {
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    });
    h.remote.roomSnapshots['A'] = _locked.copyWith(unlocked: true);
    h.remote.holdFirstSnapshot = Completer<void>();
    h.remote.revokedToken = revoked;
    try {
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(h.token, expectedProductId: BroadcastAccessConfig.productId));
      await _until(() => h.coordinator.hasLicense);
      h.coordinator.attachSession(_session('A'));
      await h.remote.snapshotEntered.future;
      await h.access.applyVerifiedLicenseGrant(await h.verifier
          .verify(revoked, expectedProductId: BroadcastAccessConfig.productId));
      h.remote.holdFirstSnapshot!.complete();
      await _until(() =>
          h.remote.activationTokens.isNotEmpty &&
          !h.coordinator.operationInProgress);
      expect(h.remote.activationTokens, [revoked]);
      expect(h.remote.snapshotReads, 1,
          reason: 'Revocation must bypass the already-unlocked shortcut.');
      expect(h.coordinator.stateFor('A').phase, ParentPurchasePhase.revoked);
      expect(h.coordinator.stateFor('A').access!.unlocked, isFalse);
      expect(h.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      expect(h.gateway.purchases, 0);
    } finally {
      await h.coordinator.dispose();
    }
  });
}

Future<void> _until(bool Function() done) async {
  for (var attempt = 0; attempt < 200 && !done(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(done(), isTrue);
}

class _Harness {
  _Harness(this.preferences, this.token, this.verifier, this.gateway,
      this.access, this.remote, this.coordinator);
  final SharedPreferences preferences;
  final String token;
  final LicenseGrantVerifier verifier;
  final _Gateway gateway;
  final BroadcastAccessService access;
  final _Remote remote;
  final BroadcastPurchaseCoordinator coordinator;

  static Future<_Harness> create(
      {bool keyConfigured = true,
      bool legacy = false,
      PendingRoomActivationRepository? pendingActivations}) async {
    SharedPreferences.setMockInitialValues(legacy
        ? {
            'broadcast_access.unlocked': true,
            'broadcast_access.verification_source': 'google_play',
            'broadcast_access.verification_authority':
                trustedBackendVerificationAuthority,
            'broadcast_access.verification_fingerprint': 'a' * 64,
            'broadcast_access.entitlement_id': 'household_test',
            'broadcast_access.verified_at_ms': 1700000000000,
          }
        : {});
    final preferences = await SharedPreferences.getInstance();
    final fixture = await LicenseTokenFixture.create();
    final token = await fixture.token();
    final verifier = LicenseGrantVerifier(publicKey: fixture.publicKey);
    final gateway = _Gateway(token);
    final access = BroadcastAccessService(preferences,
        purchaseGateway: gateway, licenseGrantVerifier: verifier);
    final remote = _Remote();
    final coordinator = BroadcastPurchaseCoordinator(
      pendingActivations: pendingActivations ??
          SharedPreferencesPendingRoomActivationRepository(preferences),
      access: access,
      remote: remote,
      licenseVerifier: verifier,
      licenseVerificationConfigured: keyConfigured,
    );
    await access.snapshot();
    await Future<void>.delayed(Duration.zero);
    return _Harness(
        preferences, token, verifier, gateway, access, remote, coordinator);
  }
}

class _Gateway extends BroadcastPurchaseGateway
    implements BroadcastProductOfferGateway {
  _Gateway(this.token);
  final String token;
  int purchases = 0;
  int restores = 0;
  bool disposed = false;
  Completer<void>? hold;
  final entered = Completer<void>();
  BroadcastPurchaseResult? restoreResult;

  @override
  BroadcastProductOffer? get cachedOffer => const BroadcastProductOffer(
      productId: BroadcastAccessConfig.productId,
      localizedPrice: '£7.99',
      rawPrice: 7.99,
      currencyCode: 'GBP');
  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) async =>
      cachedOffer;
  @override
  Future<BroadcastPurchaseResult> purchase(
      {required String productId, required String priceLabel}) async {
    purchases++;
    if (!entered.isCompleted) entered.complete();
    await hold?.future;
    return result;
  }

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    restores++;
    return restoreResult ?? result;
  }

  BroadcastPurchaseResult get result => BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.purchased,
        verified: true,
        verificationSource: 'google_play',
        verificationFingerprint: 'a' * 64,
        entitlementId: 'household_test',
        licenseToken: token,
      );
  @override
  Future<void> dispose() async => disposed = true;
}

class _Remote implements RoomBroadcastAccessGateway {
  bool supported = true;
  bool offline = false;
  final activated = <PairingSession>[];
  final activationTokens = <String>[];
  final activationEntered = Completer<void>();
  Completer<void>? holdFirstActivation;
  String? revokedToken;
  String? rejectedToken;
  int snapshotReads = 0;
  final snapshotEntered = Completer<void>();
  Completer<void>? holdFirstSnapshot;
  final roomSnapshots = <String, BroadcastAccessSnapshot>{};
  final roomTokens = <String, String>{};
  Completer<void>? holdSupport;
  final supportEntered = Completer<void>();
  @override
  Future<bool> supportsActivation(PairingSession session) async {
    if (!supportEntered.isCompleted) supportEntered.complete();
    await holdSupport?.future;
    return supported;
  }

  @override
  Future<BroadcastAccessSnapshot?> snapshot(PairingSession session) async {
    snapshotReads++;
    final snapshot = roomSnapshots[session.deviceId] ?? _locked;
    if (!snapshotEntered.isCompleted) snapshotEntered.complete();
    if (snapshotReads == 1) await holdFirstSnapshot?.future;
    return snapshot;
  }

  @override
  Future<String?> readLicense(PairingSession session) async =>
      roomTokens[session.deviceId];
  @override
  Future<BroadcastAccessSnapshot> activate(
      PairingSession session, String licenseToken) async {
    if (offline) throw StateError('Room disconnected after checkout');
    activated.add(session);
    activationTokens.add(licenseToken);
    if (licenseToken == rejectedToken) throw StateError('LICENSE_GRANT_STALE');
    if (!activationEntered.isCompleted) activationEntered.complete();
    if (activationTokens.length == 1) await holdFirstActivation?.future;
    return _locked.copyWith(unlocked: licenseToken != revokedToken);
  }
}

class _FailingDestinations implements PendingRoomActivationRepository {
  @override
  Set<String> load() => {};

  @override
  Future<void> save(Set<String> roomIds) async =>
      throw StateError('Storage unavailable');
}

class _CleanupFailingDestinations implements PendingRoomActivationRepository {
  bool failCleanup = true;
  Set<String> _saved = {};

  @override
  Set<String> load() => Set.of(_saved);

  @override
  Future<void> save(Set<String> roomIds) async {
    if (roomIds.isEmpty && failCleanup) throw StateError('Disk unavailable');
    _saved = Set.of(roomIds);
  }
}

PairingSession _session(String id, {String? token}) => PairingSession(
      payload: PairingPayload(
        schemaVersion: 2,
        host: '127.0.0.1',
        port: 1,
        deviceId: id,
        deviceName: 'Room $id',
        pairingNonce: 'nonce',
        expiresAtMs:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: token ?? 'token-$id',
    );

const _locked = BroadcastAccessSnapshot(
  unlocked: false,
  active: false,
  freeLimitMs: 7200000,
  usedMs: 7200000,
  remainingMs: 0,
  priceLabel: '€4,99',
  hasStorePrice: true,
  productId: BroadcastAccessConfig.productId,
);
