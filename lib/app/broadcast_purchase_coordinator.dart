import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/async/serialized_async_executor.dart';
import '../core/protocol/pairing_session.dart';
import '../features/client/media/remote_broadcast_access_client.dart';
import '../services/monetization/broadcast_access_service.dart';
import '../services/monetization/license_grant.dart';

enum ParentPurchasePhase {
  ready,
  purchasing,
  purchasePending,
  verificationPending,
  activating,
  activationPending,
  activated,
  revoked,
  unavailable,
  roomUpdateRequired,
  noPurchaseFound,
  failed,
  canceled,
}

class ParentPurchaseState {
  const ParentPurchaseState({
    this.phase = ParentPurchasePhase.ready,
    this.roomId,
    this.roomName,
    this.access,
  });

  final ParentPurchasePhase phase;
  final String? roomId;
  final String? roomName;
  final BroadcastAccessSnapshot? access;

  bool get isBusy =>
      phase == ParentPurchasePhase.purchasing ||
      phase == ParentPurchasePhase.activating;
}

/// Owns store transactions for the whole app, independently of screens/roles.
/// Parent runtimes never use this service's local trial as room authority.
class BroadcastPurchaseCoordinator {
  BroadcastPurchaseCoordinator({
    required SharedPreferences preferences,
    required this.access,
    RemoteBroadcastAccessClient? remote,
    LicenseGrantVerifier? licenseVerifier,
    bool? licenseVerificationConfigured,
  })  : _preferences = preferences,
        _remote = remote ?? RemoteBroadcastAccessClient(),
        _licenseVerifier = licenseVerifier ?? LicenseGrantVerifier(),
        _licenseVerificationConfigured = licenseVerificationConfigured ??
            (licenseVerifier ?? LicenseGrantVerifier()).isConfigured {
    _pendingRooms.addAll(
        preferences.getStringList(_pendingRoomsKey) ?? const <String>[]);
    _subscription = access.changes.listen(_onAccessChanged);
    unawaited(_load().catchError((_) {}));
  }

  static const _pendingRoomsKey = 'broadcast_purchase.pending_rooms';
  final SharedPreferences _preferences;
  final BroadcastAccessService access;
  final RemoteBroadcastAccessClient _remote;
  final LicenseGrantVerifier _licenseVerifier;
  final bool _licenseVerificationConfigured;
  final _changes = StreamController<void>.broadcast();
  final _pendingRooms = <String>{};
  final _sessions = <String, PairingSession>{};
  final _states = <String, ParentPurchaseState>{};
  final _storage = SerializedAsyncExecutor();
  late final StreamSubscription<BroadcastAccessSnapshot> _subscription;
  BroadcastAccessSnapshot? _localAccess;
  Future<void>? _operation;
  bool _tokenChangedDuringOperation = false;
  Timer? _retryTimer;
  bool _foreground = true;
  int _retryDelaySeconds = 5;
  String? _lastToken;
  bool _disposed = false;

  Stream<void> get changes => _changes.stream;
  bool get checkoutConfigured =>
      access.checkoutConfigured && _licenseVerificationConfigured;
  bool get activationConfigured => _licenseVerificationConfigured;
  bool get operationInProgress => _operation != null;
  String? get localPrice =>
      _localAccess?.hasStorePrice == true ? _localAccess!.priceLabel : null;
  bool get hasLicense =>
      access.licenseToken != null && _localAccess?.unlocked == true;
  bool get requiresRestore => _localAccess?.unlocked == true && !hasLicense;

  ParentPurchaseState stateFor(String roomId) =>
      _states[roomId] ??
      ParentPurchaseState(
        roomId: roomId,
        phase: _pendingRooms.contains(roomId)
            ? access.licenseToken != null
                ? ParentPurchasePhase.activationPending
                : ParentPurchasePhase.verificationPending
            : ParentPurchasePhase.ready,
      );

  Future<void> _load() async {
    _onAccessChanged(await access.snapshot());
  }

  void _onAccessChanged(BroadcastAccessSnapshot snapshot) {
    if (_disposed) return;
    _localAccess = snapshot;
    final token = access.licenseToken;
    if (token != null && token != _lastToken) {
      _lastToken = token;
      if (_operation != null) _tokenChangedDuringOperation = true;
      // A new purchase belongs to its saved destination, even if another room
      // was selected while the store was open. Revocation must reach every
      // known room; later explicit room attachment can reuse an active grant.
      if (!snapshot.unlocked) _pendingRooms.addAll(_sessions.keys);
      unawaited(_savePending().catchError((_) {}));
    }
    _notify();
    unawaited(retryPending().catchError((_) {}));
  }

  void attachSession(PairingSession session) {
    if (_disposed) return;
    _sessions[session.deviceId] = session;
    if (access.licenseToken != null) {
      _pendingRooms.add(session.deviceId);
      unawaited(_savePending().then((_) => retryPending()).catchError((_) {}));
    } else if (_licenseVerificationConfigured) {
      unawaited(_inheritRoomLicense(session).catchError((_) => null));
    }
  }

  Future<BroadcastAccessSnapshot?> _inheritRoomLicense(
      PairingSession session) async {
    final snapshot = await _remote.snapshot(session);
    if (_disposed || snapshot?.unlocked != true) return null;
    final token = hasLicense ? null : await _remote.readLicense(session);
    if (token != null) {
      final grant = await _licenseVerifier.verify(token,
          expectedProductId: access.productId);
      if (_disposed) return null;
      await access.applyVerifiedLicenseGrant(grant);
      if (grant.status != LicenseGrantStatus.active) return null;
    }
    _set(session, ParentPurchasePhase.activated, snapshot);
    return snapshot;
  }

  Future<BroadcastAccessSnapshot?> purchaseForRoom(
    PairingSession session, {
    bool restore = false,
  }) async {
    if (_disposed || _operation != null) return null;
    BroadcastAccessSnapshot? result;
    // Capture this session before any await: navigation cannot redirect payment.
    final target = session;
    final operation = _purchase(target, restore: restore).then((value) {
      result = value;
    });
    _operation = operation;
    _notify();
    try {
      await operation;
    } finally {
      if (identical(_operation, operation)) _operation = null;
      _notify();
      unawaited(retryPending().catchError((_) {}));
    }
    return result;
  }

  Future<BroadcastAccessSnapshot?> _purchase(
    PairingSession target, {
    required bool restore,
  }) async {
    _sessions[target.deviceId] = target;
    try {
      if (!activationConfigured ||
          ((!hasLicense || restore) && !checkoutConfigured)) {
        _set(target, ParentPurchasePhase.unavailable);
        return null;
      }
      if (!await _remote.supportsActivation(target)) {
        _set(target, ParentPurchasePhase.roomUpdateRequired);
        return null;
      }
      final existing = await _inheritRoomLicense(target);
      if (existing != null) return existing;
      // Persist the destination before opening the chargeable store sheet.
      _pendingRooms.add(target.deviceId);
      await _savePending();
      if (!hasLicense || restore) {
        _set(target, ParentPurchasePhase.purchasing);
        if (restore || requiresRestore) {
          await access.restorePurchase();
        } else {
          await access.unlockWithOneTimePurchase();
        }
      }
      _localAccess = await access.snapshot();
      if (!hasLicense) {
        _set(target, ParentPurchasePhase.verificationPending);
        return null;
      }
      return await _activate(target);
    } on BroadcastPurchaseException catch (error) {
      final phase =
          error.result.failureReason == BroadcastPurchaseFailureReason.revoked
              ? ParentPurchasePhase.revoked
              : switch (error.result.status) {
                  BroadcastPurchaseStatus.pending =>
                    ParentPurchasePhase.purchasePending,
                  BroadcastPurchaseStatus.verificationFailed =>
                    ParentPurchasePhase.verificationPending,
                  BroadcastPurchaseStatus.unavailable =>
                    ParentPurchasePhase.unavailable,
                  BroadcastPurchaseStatus.noPurchaseFound =>
                    ParentPurchasePhase.noPurchaseFound,
                  BroadcastPurchaseStatus.canceled =>
                    ParentPurchasePhase.canceled,
                  _ => ParentPurchasePhase.failed,
                };
      _set(target, phase);
      if (phase == ParentPurchasePhase.canceled ||
          phase == ParentPurchasePhase.unavailable ||
          phase == ParentPurchasePhase.noPurchaseFound) {
        _pendingRooms.remove(target.deviceId);
        await _savePending();
      }
      return null;
    } catch (_) {
      _set(
          target,
          hasLicense
              ? ParentPurchasePhase.activationPending
              : ParentPurchasePhase.failed);
      return null;
    }
  }

  Future<BroadcastAccessSnapshot?> _activate(PairingSession target) async {
    final token = access.licenseToken;
    if (_disposed || token == null) return null;
    _set(target, ParentPurchasePhase.activating);
    try {
      final local = await access.snapshot();
      if (token != access.licenseToken) {
        _set(target, ParentPurchasePhase.activationPending);
        return null;
      }
      // A room can already hold a newer active family grant. Its authoritative
      // unlocked state satisfies active delivery without replaying an older
      // token forever. Revocations must always reach the activation endpoint.
      final current = local.unlocked ? await _remote.snapshot(target) : null;
      if (token != access.licenseToken) {
        _set(target, ParentPurchasePhase.activationPending);
        return null;
      }
      final snapshot = current?.unlocked == true
          ? current!
          : await _remote.activate(target, token);
      if (token != access.licenseToken) {
        _set(target, ParentPurchasePhase.activationPending);
        return null;
      }
      _pendingRooms.remove(target.deviceId);
      await _savePending();
      _retryDelaySeconds = 5;
      _set(
          target,
          snapshot.unlocked
              ? ParentPurchasePhase.activated
              : ParentPurchasePhase.revoked,
          snapshot);
      return snapshot;
    } catch (_) {
      _set(target, ParentPurchasePhase.activationPending);
      return null;
    }
  }

  /// Retries only signed-grant delivery, never opens another checkout.
  Future<void> retryPending() async {
    if (_disposed ||
        !_foreground ||
        _operation != null ||
        access.licenseToken == null) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    final targets = [
      for (final id in _pendingRooms)
        if (_sessions[id] case final session?) session,
    ];
    if (targets.isEmpty) return;
    _tokenChangedDuringOperation = false;
    final operation = () async {
      for (final target in targets) {
        if (_disposed) break;
        await _activate(target);
      }
    }();
    _operation = operation;
    _notify();
    try {
      await operation;
    } finally {
      if (identical(_operation, operation)) _operation = null;
      _notify();
      if (_tokenChangedDuringOperation) {
        _tokenChangedDuringOperation = false;
        unawaited(retryPending().catchError((_) {}));
      } else {
        _scheduleRetry();
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed ||
        !_foreground ||
        _retryTimer != null ||
        access.licenseToken == null ||
        !_pendingRooms.any(_sessions.containsKey)) {
      return;
    }
    _retryTimer = Timer(Duration(seconds: _retryDelaySeconds), () {
      _retryTimer = null;
      unawaited(retryPending().catchError((_) {}));
    });
    _retryDelaySeconds = (_retryDelaySeconds * 2).clamp(5, 60);
  }

  void onBackground() {
    _foreground = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> onForeground() async {
    if (_disposed) return;
    _foreground = true;
    await access.reconcilePurchases();
    await _load();
    await retryPending();
  }

  Future<void> _savePending() => _storage.run(() async {
        if (!await _preferences.setStringList(
            _pendingRoomsKey, _pendingRooms.toList(growable: false))) {
          throw StateError('Could not save room activation destination.');
        }
      });

  void _set(PairingSession session, ParentPurchasePhase phase,
      [BroadcastAccessSnapshot? snapshot]) {
    if (_disposed) return;
    _states[session.deviceId] = ParentPurchaseState(
      roomId: session.deviceId,
      roomName: session.payload.deviceName,
      phase: phase,
      access: snapshot,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    await _subscription.cancel();
    await access.dispose();
    await _operation;
    await _storage.close();
    await _changes.close();
  }
}
