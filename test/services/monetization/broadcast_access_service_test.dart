import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('free broadcast time uses monotonic active wall time', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final clock = _Clock();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    await service.beginSession('a');
    await service.beginSession('b');
    clock.advance(const Duration(minutes: 2));
    await service.endSession('a');
    clock.advance(const Duration(minutes: 3));
    final activeLocked = await service.snapshot();

    expect(activeLocked.isLocked, isTrue);
    expect(activeLocked.usedMs, const Duration(minutes: 5).inMilliseconds);

    await service.endSession('b');
    await expectLater(
      service.beginSession('c'),
      throwsA(isA<BroadcastAccessLockedException>()),
    );
  });

  test('unfinished active checkpoint is recovered after process restart',
      () async {
    final clock = _Clock();
    final checkpoint = clock.now().millisecondsSinceEpoch - 10000;
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': 2000,
      'broadcast_access.active_marker': true,
      'broadcast_access.active_checkpoint_wall_ms': checkpoint,
      'broadcast_access.last_observed_wall_ms': checkpoint,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      freeLimit: const Duration(minutes: 5),
      checkpointInterval: const Duration(seconds: 15),
    );
    addTearDown(service.dispose);

    final snapshot = await service.snapshot();

    expect(snapshot.usedMs, 12000);
    final migrated =
        jsonDecode(prefs.getString('broadcast_access.trial_ledger_v1')!) as Map;
    expect(migrated['active'], isFalse);
    expect(migrated.containsKey('checkpointWallMs'), isFalse);
    final restartedAgain = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(restartedAgain.dispose);
    // The legacy active flag stays available for migration diagnostics but
    // cannot be applied a second time once the atomic ledger exists.
    expect((await restartedAgain.snapshot()).usedMs, 12000);
  });

  test('wall-clock rollback charges one bounded checkpoint interval', () async {
    final clock = _Clock();
    final futureCheckpoint =
        clock.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'broadcast_access.active_marker': true,
      'broadcast_access.active_checkpoint_wall_ms': futureCheckpoint,
      'broadcast_access.last_observed_wall_ms': futureCheckpoint,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      checkpointInterval: const Duration(seconds: 15),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).usedMs, 15000);
  });

  test(
      'the default two hours are shared by five viewers and survive idle restart',
      () async {
    final preferences = _FaultInjectingPreferences();
    final clock = _Clock();
    final service = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(service.dispose);
    for (var index = 0; index < 5; index++) {
      await service.beginSession('viewer-$index');
    }
    await service.beginSession('viewer-0');
    clock.advance(const Duration(hours: 1));
    final midway = await service.endSession('viewer-0');
    expect(midway.usedMs, const Duration(hours: 1).inMilliseconds);
    expect(midway.remaining, const Duration(hours: 1));
    expect(midway.active, isTrue);
    clock.advance(const Duration(hours: 1));
    final exhausted = await service.endAllSessions();
    expect(exhausted.isLocked, isTrue);
    expect(exhausted.usedMs, const Duration(hours: 2).inMilliseconds);

    clock.advance(const Duration(days: 7));
    final restarted = BroadcastAccessService(
      _FaultInjectingPreferences(preferences.durable),
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(restarted.dispose);
    await expectLater(restarted.beginSession('after-restart'),
        throwsA(isA<BroadcastAccessLockedException>()));
    expect((await restarted.snapshot()).usedMs, exhausted.usedMs);
  });

  test('changing the phone wall clock cannot reset active trial usage',
      () async {
    final clock = _Clock();
    final service = BroadcastAccessService(
      _FaultInjectingPreferences(),
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(service.dispose);
    await service.beginSession('viewer');
    clock.advance(const Duration(minutes: 45));
    clock.shiftWall(const Duration(days: -30));
    expect((await service.snapshot()).usedMs,
        const Duration(minutes: 45).inMilliseconds);
    clock.advance(const Duration(minutes: 75));
    expect((await service.snapshot()).isLocked, isTrue);
  });

  test(
      'an unclean restart charges at most one interval, not days of offline time',
      () async {
    final clock = _Clock();
    final preferences = _FaultInjectingPreferences();
    final first = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    await first.beginSession('viewer');
    clock.advance(const Duration(seconds: 10));
    // Keep the durable state at the point the process disappears. Disposing
    // the test instance only releases its real periodic timer.
    final crashedDisk = Map<String, Object>.of(preferences.durable);
    await first.dispose();
    clock.advance(const Duration(days: 7));
    final recoveredPreferences = _FaultInjectingPreferences(crashedDisk);
    final restarted = BroadcastAccessService(
      recoveredPreferences,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(restarted.dispose);
    final recovered = await restarted.snapshot();
    expect(recovered.usedMs, const Duration(seconds: 15).inMilliseconds);
    expect(recovered.active, isFalse);

    final secondRestart = BroadcastAccessService(
      _FaultInjectingPreferences(recoveredPreferences.durable),
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(secondRestart.dispose);
    expect((await secondRestart.snapshot()).usedMs, recovered.usedMs);
  });

  test('a false trial-start write cannot report a started broadcast', () async {
    final preferences = _FaultInjectingPreferences();
    final service = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(service.dispose);
    await service.snapshot();
    preferences.rejectWrites = true;

    await expectLater(service.beginSession('viewer'),
        throwsA(isA<BroadcastAccessPersistenceException>()));

    expect((await service.snapshot()).active, isFalse);
    expect(service.lastPersistenceError, isNotNull);
    final cached =
        jsonDecode(preferences.getString('broadcast_access.trial_ledger_v1')!)
            as Map;
    expect(cached['active'], isFalse);
    preferences.rejectWrites = false;
    expect((await service.beginSession('retry')).active, isTrue);
  });

  test('a failed final stop retains usage without charging idle time on retry',
      () async {
    final preferences = _FaultInjectingPreferences();
    final clock = _Clock();
    final service = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(service.dispose);
    await service.beginSession('viewer');
    clock.advance(const Duration(seconds: 90));
    preferences.rejectWrites = true;
    await expectLater(service.endSession('viewer'),
        throwsA(isA<BroadcastAccessPersistenceException>()));
    expect((await service.snapshot()).usedMs, 90000);
    expect((await service.snapshot()).active, isFalse);
    clock.advance(const Duration(minutes: 5));
    expect((await service.snapshot()).usedMs, 90000);

    preferences.rejectWrites = false;
    await service.endSession('viewer');
    final retriedStop = jsonDecode(
            preferences.durable['broadcast_access.trial_ledger_v1']! as String)
        as Map;
    expect(retriedStop['usedMs'], 90000);
    expect(retriedStop['active'], isFalse);
    await service.beginSession('retry');
    clock.advance(const Duration(seconds: 10));
    expect((await service.endSession('retry')).usedMs, 100000);
    final restarted = BroadcastAccessService(
      _FaultInjectingPreferences(preferences.durable),
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
    );
    addTearDown(restarted.dispose);
    expect((await restarted.snapshot()).usedMs, 100000);
  });

  test('a failed lifetime grant is not exposed through the preferences cache',
      () async {
    final preferences = _FaultInjectingPreferences();
    final service = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(service.dispose);
    await service.snapshot();
    preferences.rejectValue =
        (key, value) => key == 'broadcast_access.unlocked' && value == true;

    await expectLater(service.unlockWithOneTimePurchase(),
        throwsA(isA<BroadcastAccessPersistenceException>()));

    expect((await service.snapshot()).unlocked, isFalse);
    expect(preferences.getBool('broadcast_access.unlocked'), isFalse);
    final recreated = BroadcastAccessService(
      preferences,
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(recreated.dispose);
    expect((await recreated.snapshot()).unlocked, isFalse);
    preferences.rejectValue = null;
    expect((await service.unlockWithOneTimePurchase()).unlocked, isTrue);
    final restarted = BroadcastAccessService(
      _FaultInjectingPreferences(preferences.durable),
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(restarted.dispose);
    expect((await restarted.snapshot()).unlocked, isTrue);
  });

  test(
      'an initialization storage failure denies trial and still disposes billing',
      () async {
    final preferences = _FaultInjectingPreferences()..rejectWrites = true;
    final gateway = _FakePurchaseGateway();
    final service =
        BroadcastAccessService(preferences, purchaseGateway: gateway);

    await expectLater(service.beginSession('viewer'),
        throwsA(isA<BroadcastAccessPersistenceException>()));
    await expectLater(
        service.dispose(), throwsA(isA<BroadcastAccessPersistenceException>()));
    expect(gateway.disposed, isTrue);
    expect(preferences.getString('broadcast_access.trial_ledger_v1'), isNull);
  });

  test(
      'start, periodic checkpoint and stop publish changes without snapshot loops',
      () async {
    final clock = _Clock();
    final service = BroadcastAccessService(
      _FaultInjectingPreferences(),
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      checkpointInterval: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    final events = <BroadcastAccessSnapshot>[];
    final checkpoint = Completer<void>();
    final subscription = service.changes.listen((snapshot) {
      events.add(snapshot);
      if (snapshot.active &&
          snapshot.usedMs == 10000 &&
          !checkpoint.isCompleted) {
        checkpoint.complete();
      }
    });
    addTearDown(subscription.cancel);
    await service.beginSession('viewer');
    await Future<void>.delayed(Duration.zero);
    expect(events.last.active, isTrue);
    clock.advance(const Duration(seconds: 10));
    await checkpoint.future.timeout(const Duration(seconds: 1));
    await service.endAllSessions();
    await Future<void>.delayed(Duration.zero);
    expect(events.last.active, isFalse);
    final count = events.length;
    await service.snapshot();
    await service.snapshot();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(count));
  });

  test('one-time purchase persists complete trusted entitlement evidence',
      () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(minutes: 5).inMilliseconds,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(
        result: _verifiedResult(),
      ),
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).isLocked, isTrue);
    final unlocked = await service.unlockWithOneTimePurchase();

    expect(unlocked.unlocked, isTrue);
    expect(unlocked.purchaseVerificationSource, 'google_play');
    expect(
      unlocked.purchaseVerificationAuthority,
      trustedBackendVerificationAuthority,
    );
    expect(unlocked.purchaseVerificationFingerprint, hasLength(64));
    expect(unlocked.entitlementId, 'household-42');
    expect(unlocked.purchaseVerifiedAtMs, isNotNull);
    await expectLater(service.beginSession('after-purchase'), completes);
  });

  test('bare local unlocked boolean fails closed without trusted evidence',
      () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.unlocked': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).unlocked, isFalse);
  });

  test('unverified purchase cannot persist lifetime entitlement', () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(minutes: 5).inMilliseconds,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(
        result: const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.purchased,
        ),
      ),
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.unlockWithOneTimePurchase(),
      throwsA(isA<BroadcastPurchaseException>()),
    );
    expect((await service.snapshot()).unlocked, isFalse);
  });

  test('late verified gateway update unlocks without an active UI request',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = _FakePurchaseGateway();
    final service = BroadcastAccessService(prefs, purchaseGateway: gateway);
    addTearDown(service.dispose);
    final changed = service.changes.first;

    gateway.emit(_verifiedResult(status: BroadcastPurchaseStatus.restored));
    final snapshot = await changed;

    expect(snapshot.unlocked, isTrue);
    expect(snapshot.entitlementId, 'household-42');
  });

  test('localized ProductDetails price is exposed by access snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = _FakePurchaseGateway(
      offer: const BroadcastProductOffer(
        productId: BroadcastAccessConfig.productId,
        localizedPrice: '€4,99',
        rawPrice: 4.99,
        currencyCode: 'EUR',
      ),
    );
    final service = BroadcastAccessService(prefs, purchaseGateway: gateway);
    addTearDown(service.dispose);

    final snapshot = await service.snapshot();
    expect(snapshot.priceLabel, '€4,99');
    expect(snapshot.hasStorePrice, isTrue);
  });

  test('local store envelope preflight never claims authenticity', () async {
    const verifier = StorePayloadPurchaseVerifier();
    final missing = _purchase(
      status: PurchaseStatus.purchased,
      serverData: '',
      localData: '',
    );
    final structurallyValid = _purchase(status: PurchaseStatus.purchased);

    final missingResult = await verifier.verify(
      missing,
      expectedProductId: BroadcastAccessConfig.productId,
    );
    final validEnvelopeResult = await verifier.verify(
      structurallyValid,
      expectedProductId: BroadcastAccessConfig.productId,
    );

    expect(missingResult.verified, isFalse);
    expect(validEnvelopeResult.verified, isFalse);
    expect(validEnvelopeResult.reason, contains('backend'));
  });

  test('purchase stream handles pending timeout then late verified completion',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(gateway.dispose);
    final lateResult =
        gateway.updates.firstWhere((result) => result.unlocksAccess);

    final purchaseFuture = gateway.purchase(
      productId: BroadcastAccessConfig.productId,
      priceLabel: 'fallback',
    );
    await store.buyStarted.future;
    store.emit([_purchase(status: PurchaseStatus.pending)]);

    expect((await purchaseFuture).status, BroadcastPurchaseStatus.pending);

    final purchased = _purchase(
      status: PurchaseStatus.purchased,
      pendingComplete: true,
    );
    store.emit([purchased]);
    expect((await lateResult).unlocksAccess, isTrue);
    expect(store.completedPurchases, 1);

    final duplicate =
        gateway.updates.firstWhere((result) => result.unlocksAccess);
    store.emit([purchased]);
    await duplicate;
    expect(store.completedPurchases, 1);
  });

  test('restored startup transaction is processed without restore UI request',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere((result) => result.unlocksAccess);

    store.emit([
      _purchase(
        status: PurchaseStatus.restored,
        pendingComplete: true,
      ),
    ]);

    expect((await update).status, BroadcastPurchaseStatus.restored);
    expect(store.completedPurchases, 1);
  });

  test('purchase stream errors become observable results', () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.error,
    );

    store.emitError(StateError('billing disconnected'));

    expect((await update).message, contains('billing disconnected'));
  });

  test('store transaction is not acknowledged when verification fails',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const StorePayloadPurchaseVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.verificationFailed,
    );

    store.emit([
      _purchase(
        status: PurchaseStatus.purchased,
        pendingComplete: true,
      ),
    ]);

    expect((await update).verified, isFalse);
    expect(store.completedPurchases, 0);
  });

  test('ack failure does not cache entitlement and store redelivery retries',
      () async {
    final store = _FakeInAppPurchaseStore()..completeFailuresRemaining = 1;
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final failed = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.verificationFailed,
    );
    final purchase = _purchase(
      status: PurchaseStatus.purchased,
      pendingComplete: true,
    );

    store.emit([purchase]);
    await failed;
    final retried =
        gateway.updates.firstWhere((result) => result.unlocksAccess);
    store.emit([purchase]);

    expect((await retried).unlocksAccess, isTrue);
    expect(store.completeAttempts, 2);
    expect(store.completedPurchases, 1);
  });

  test('trusted backend verifier sends evidence and validates response binding',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<Map<String, Object?>>();
    unawaited(server.forEach((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      received.complete(body);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'verified': true,
        'productId': BroadcastAccessConfig.productId,
        'source': 'google_play',
        'transactionFingerprint': 'a' * 64,
        'entitlementId': 'household-42',
      }));
      await request.response.close();
    }));
    final verifier = TrustedBackendPurchaseVerifier(
      endpoint: Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/verify',
      ),
      allowInsecureEndpointForTesting: true,
    );

    final result = await verifier.verify(
      _purchase(status: PurchaseStatus.purchased),
      expectedProductId: BroadcastAccessConfig.productId,
    );

    expect(result.verified, isTrue);
    expect(result.entitlementId, 'household-42');
    expect((await received.future)['serverVerificationData'], 'store-token');
  });
}

BroadcastPurchaseResult _verifiedResult({
  BroadcastPurchaseStatus status = BroadcastPurchaseStatus.purchased,
}) =>
    BroadcastPurchaseResult(
      status: status,
      verified: true,
      verificationSource: 'google_play',
      verificationFingerprint: 'f' * 64,
      entitlementId: 'household-42',
    );

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String serverData = 'store-token',
  String localData = '{"purchaseState":0}',
  bool pendingComplete = false,
}) {
  final purchase = PurchaseDetails(
    purchaseID: 'order-1',
    productID: BroadcastAccessConfig.productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: localData,
      serverVerificationData: serverData,
      source: 'google_play',
    ),
    transactionDate: '1',
    status: status,
  );
  purchase.pendingCompletePurchase = pendingComplete;
  return purchase;
}

class _Clock {
  DateTime _now = DateTime(2026, 1, 1, 12);
  int _monotonicMs = 0;

  DateTime now() => _now;
  int monotonicNowMs() => _monotonicMs;

  void shiftWall(Duration duration) => _now = _now.add(duration);

  void advance(Duration duration) {
    _now = _now.add(duration);
    _monotonicMs += duration.inMilliseconds;
  }
}

class _FakePurchaseGateway
    implements
        BroadcastPurchaseGateway,
        BroadcastPurchaseUpdateSource,
        BroadcastProductOfferGateway {
  _FakePurchaseGateway({
    BroadcastPurchaseResult? result,
    this.offer,
  }) : result = result ?? _verifiedResult();

  final BroadcastPurchaseResult result;
  final BroadcastProductOffer? offer;
  bool disposed = false;
  final _updates = StreamController<BroadcastPurchaseResult>.broadcast();

  void emit(BroadcastPurchaseResult result) => _updates.add(result);

  @override
  Stream<BroadcastPurchaseResult> get updates => _updates.stream;

  @override
  BroadcastProductOffer? get cachedOffer => offer;

  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) async =>
      offer;

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      result;

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      result;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _updates.close();
  }
}

/// Matches legacy SharedPreferences: the cache changes even when the device
/// write returns false. [durable] is copied to simulate a new process.
class _FaultInjectingPreferences implements SharedPreferences {
  _FaultInjectingPreferences([Map<String, Object> initial = const {}])
      : _cache = Map.of(initial),
        durable = Map.of(initial);

  final Map<String, Object> _cache;
  final Map<String, Object> durable;
  bool rejectWrites = false;
  bool Function(String key, Object? value)? rejectValue;

  @override
  String? getString(String key) => _cache[key] as String?;
  @override
  int? getInt(String key) => _cache[key] as int?;
  @override
  bool? getBool(String key) => _cache[key] as bool?;
  @override
  bool containsKey(String key) => _cache.containsKey(key);

  Future<bool> _set(String key, Object value) async {
    _cache[key] = value;
    if (rejectWrites || (rejectValue?.call(key, value) ?? false)) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);
  @override
  Future<bool> remove(String key) async {
    _cache.remove(key);
    if (rejectWrites || (rejectValue?.call(key, null) ?? false)) return false;
    durable.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInAppPurchaseStore implements InAppPurchaseStore {
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();
  final buyStarted = Completer<void>();
  int completeAttempts = 0;
  int completeFailuresRemaining = 0;
  int completedPurchases = 0;

  void emit(List<PurchaseDetails> purchases) => _purchases.add(purchases);

  void emitError(Object error) =>
      _purchases.addError(error, StackTrace.current);

  Future<void> dispose() => _purchases.close();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: BroadcastAccessConfig.productId,
            title: 'Lifetime',
            description: 'Lifetime room access',
            price: '₺300,00',
            rawPrice: 300,
            currencyCode: 'TRY',
            currencySymbol: '₺',
          ),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    if (!buyStarted.isCompleted) buyStarted.complete();
    return true;
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeAttempts++;
    if (completeFailuresRemaining > 0) {
      completeFailuresRemaining--;
      throw StateError('ack unavailable');
    }
    completedPurchases++;
  }
}

class _AcceptingVerifier implements BroadcastPurchaseVerifier {
  const _AcceptingVerifier();

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async =>
      BroadcastPurchaseVerification.verified(
        source: purchase.verificationData.source,
        fingerprint: 'f' * 64,
        entitlementId: 'household-42',
      );
}
