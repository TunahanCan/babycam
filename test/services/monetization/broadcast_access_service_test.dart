import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('free broadcast time is counted as active wall-clock time', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final clock = _Clock();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      freeLimit: const Duration(minutes: 5),
    );

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

  test('one-time purchase unlocks broadcast after trial is exhausted',
      () async {
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

    expect((await service.snapshot()).isLocked, isTrue);

    final unlocked = await service.unlockWithOneTimePurchase();

    expect(unlocked.unlocked, isTrue);
    await expectLater(service.beginSession('after-purchase'), completes);
  });
}

class _Clock {
  DateTime _now = DateTime(2026, 1, 1, 12);

  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

class _FakePurchaseGateway implements BroadcastPurchaseGateway {
  _FakePurchaseGateway({
    this.result = const BroadcastPurchaseResult(
      status: BroadcastPurchaseStatus.purchased,
    ),
  });

  final BroadcastPurchaseResult result;

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
  Future<void> dispose() async {}
}
