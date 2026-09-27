import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/async/serialized_async_executor.dart';
import 'broadcast_access_models.dart';
import 'in_app_broadcast_purchase_gateway.dart';
import 'license_grant.dart';
import 'purchase_verification.dart';

// Keep the established import path compatible for application and test callers.
export 'broadcast_access_models.dart';
export 'in_app_broadcast_purchase_gateway.dart';
export 'in_app_purchase_store.dart';
export 'purchase_verification.dart';

/// Authoritative room-device entitlement and crash-resilient trial ledger.
///
/// The paired client must treat the room/server response as the single access
/// authority instead of maintaining a second independent local trial.
class BroadcastAccessService {
  BroadcastAccessService(
    this._preferences, {
    BroadcastPurchaseGateway? purchaseGateway,
    DateTime Function()? now,
    int Function()? monotonicNowMs,
    Duration freeLimit = BroadcastAccessConfig.freeLimit,
    Duration checkpointInterval = BroadcastAccessConfig.checkpointInterval,
    String priceLabel = BroadcastAccessConfig.oneTimePriceLabel,
    String productId = BroadcastAccessConfig.productId,
    LicenseGrantVerifier? licenseGrantVerifier,
    this.ownsPurchaseGateway = true,
    this.entitlementRefreshInterval = const Duration(hours: 6),
    this.persistenceTimeout = const Duration(seconds: 5),
  })  : assert(checkpointInterval > Duration.zero),
        _purchaseGateway = purchaseGateway ??
            InAppBroadcastPurchaseGateway(
                expectedProductId: productId,
                licenseGrantVerifier: licenseGrantVerifier),
        _now = now ?? DateTime.now,
        _monotonicNowOverride = monotonicNowMs,
        _freeLimit = freeLimit,
        _checkpointInterval = checkpointInterval,
        _fallbackPriceLabel = priceLabel,
        _productId = productId,
        _licenseGrantVerifier = licenseGrantVerifier ?? LicenseGrantVerifier(),
        _stopwatch = Stopwatch()..start() {
    _initialization = _initializeTrialLedger().catchError((Object error) {
      // A damaged trial ledger fails closed for free broadcasting, but cannot
      // prevent a paid owner from recovering their entitlement through restore.
      _trialInitializationError = error;
      _storedUsedMs = _freeLimit.inMilliseconds;
      _trialLedgerInitialized = true;
    });
    final gateway = _purchaseGateway;
    if (gateway is BroadcastPurchaseDeliveryGateway) {
      (gateway as BroadcastPurchaseDeliveryGateway)
          .attachDeliveryHandler(_deliverVerifiedPurchase);
    }
    final updateSource = _purchaseGateway is BroadcastPurchaseUpdateSource
        ? _purchaseGateway as BroadcastPurchaseUpdateSource
        : null;
    _purchaseUpdates =
        (updateSource?.updates ?? const Stream<BroadcastPurchaseResult>.empty())
            .listen(
      _handlePurchaseUpdate,
      onError: (Object _, StackTrace __) {},
    );
    unawaited(_loadOfferBestEffort());
  }

  static const _prefix = 'broadcast_access.';
  static const _unlockedKey = '${_prefix}unlocked';
  static const _usedMsKey = '${_prefix}used_ms';
  static const _verifiedAtMsKey = '${_prefix}verified_at_ms';
  static const _verificationSourceKey = '${_prefix}verification_source';
  static const _verificationFingerprintKey =
      '${_prefix}verification_fingerprint';
  static const _verificationAuthorityKey = '${_prefix}verification_authority';
  static const _entitlementIdKey = '${_prefix}entitlement_id';
  static const _activeMarkerKey = '${_prefix}active_marker';
  static const _activeCheckpointWallMsKey =
      '${_prefix}active_checkpoint_wall_ms';
  static const _lastObservedWallMsKey = '${_prefix}last_observed_wall_ms';
  static const _trialLedgerKey = '${_prefix}trial_ledger_v1';
  static const _entitlementRecordKey = '${_prefix}entitlement_v1';

  final SharedPreferences _preferences;
  final BroadcastPurchaseGateway _purchaseGateway;
  final DateTime Function() _now;
  final int Function()? _monotonicNowOverride;
  final Duration _freeLimit;
  final Duration _checkpointInterval;
  final String _fallbackPriceLabel;
  final String _productId;
  final Stopwatch _stopwatch;
  final LicenseGrantVerifier _licenseGrantVerifier;
  final bool ownsPurchaseGateway;
  final Duration entitlementRefreshInterval;
  final Duration persistenceTimeout;
  final _activeSessions = <String, int>{};
  final _changes = StreamController<BroadcastAccessSnapshot>.broadcast();
  late final Future<void> _initialization;
  late final StreamSubscription<BroadcastPurchaseResult> _purchaseUpdates;
  final _mutations = SerializedAsyncExecutor();
  Timer? _checkpointTimer;
  int? _activeStartedAtMonoMs;
  int _storedUsedMs = 0;
  int _lastObservedWallMs = 0;
  bool _trialLedgerInitialized = false;
  bool _trialLedgerDirty = false;
  bool _entitlementPersistenceFailed = false;
  Object? _lastPersistenceError;
  String? _localizedPriceLabel;
  BroadcastPurchaseResult? _lastPurchaseResult;
  bool _disposed = false;
  Object? _trialInitializationError;
  int? _lastRefreshMonoMs;
  Future<BroadcastAccessSnapshot>? _refreshOperation;
  Future<BroadcastAccessSnapshot>? _reconcileOperation;

  Stream<BroadcastAccessSnapshot> get changes => _changes.stream;
  BroadcastPurchaseResult? get lastPurchaseResult => _lastPurchaseResult;
  Object? get lastPersistenceError => _lastPersistenceError;
  String get productId => _productId;
  String? get licenseToken => _entitlementRecord()['licenseToken'] as String?;
  bool get checkoutConfigured =>
      _purchaseGateway is BroadcastEntitlementRefreshGateway
          ? (_purchaseGateway as BroadcastEntitlementRefreshGateway)
              .checkoutConfigured
          : true;

  Future<BroadcastAccessSnapshot> snapshot() async {
    await _initialization;
    // Local trial enforcement must never wait for store connectivity. Price
    // availability is published separately through changes when it arrives.
    await _mutations.drain();
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async {
    await _initialization;
    return _serialize(() async {
      _requireTrialOrEntitlement();
      final before = _snapshot();
      if (before.isLocked) throw BroadcastAccessLockedException(before);
      final normalized = _normalizeSessionId(sessionId);
      if (_activeSessions.containsKey(normalized)) return before;
      final monoNow = _monoNowMs();
      if (_activeSessions.isEmpty && !before.unlocked) {
        _activeStartedAtMonoMs = monoNow;
        try {
          await _writeTrialLedger(active: true);
        } catch (_) {
          _activeStartedAtMonoMs = null;
          rethrow;
        }
        _startCheckpointTimer();
      }
      _activeSessions[normalized] = monoNow;
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    await _initialization;
    return _serialize(() async {
      final removed = _activeSessions.remove(_normalizeSessionId(sessionId));
      if (removed == null) {
        if (_trialLedgerDirty) {
          await _writeTrialLedger(active: _activeSessions.isNotEmpty);
        }
        return _snapshot();
      }
      if (_activeSessions.isEmpty) {
        _checkpointTimer?.cancel();
        _checkpointTimer = null;
        await _checkpointActiveElapsed(keepActive: false);
      }
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> endAllSessions() async {
    await _initialization;
    return _serialize(() async {
      _requireTrialOrEntitlement();
      _activeSessions.clear();
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      await _checkpointActiveElapsed(keepActive: false);
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> unlockWithOneTimePurchase() async {
    await _initialization;
    final result = await _purchaseGateway.purchase(
      productId: _productId,
      priceLabel: _localizedPriceLabel ?? _fallbackPriceLabel,
    );
    _lastPurchaseResult = result;
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    return _serialize(() => _persistVerifiedUnlock(result));
  }

  Future<BroadcastAccessSnapshot> restorePurchase() async {
    await _initialization;
    final result = await _purchaseGateway.restore(productId: _productId);
    _lastPurchaseResult = result;
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    return _serialize(() => _persistVerifiedUnlock(result));
  }

  Future<void> _deliverVerifiedPurchase(BroadcastPurchaseResult result) async {
    if (_disposed) throw StateError('Entitlement owner is disposed.');
    await _initialization;
    await _serialize(() => _persistVerifiedUnlock(result));
  }

  Future<BroadcastAccessSnapshot> applyVerifiedLicenseGrant(
    VerifiedLicenseGrant grant,
  ) async {
    if (_disposed) throw StateError('Entitlement owner is disposed.');
    await _initialization;
    return _serialize(() => _persistLicenseGrant(grant));
  }

  Future<BroadcastAccessSnapshot> refreshEntitlement() {
    final current = _refreshOperation;
    if (current != null) return current;
    late final Future<BroadcastAccessSnapshot> operation;
    operation = _refreshEntitlement().whenComplete(() {
      if (identical(_refreshOperation, operation)) _refreshOperation = null;
    });
    _refreshOperation = operation;
    return operation;
  }

  /// Recovers store events missed while this app was stopped, then refreshes
  /// any signed grant. This performs no interactive store restore/sync.
  Future<BroadcastAccessSnapshot> reconcilePurchases() {
    final ongoing = _reconcileOperation;
    if (ongoing != null) return ongoing;
    late final Future<BroadcastAccessSnapshot> operation;
    operation = (() async {
      await _initialization;
      if (!_disposed) unawaited(_loadOfferBestEffort());
      final gateway = _purchaseGateway;
      if (!_disposed && gateway is BroadcastOwnedPurchaseGateway) {
        try {
          await (gateway as BroadcastOwnedPurchaseGateway)
              .reconcilePurchases(includeFinished: licenseToken == null);
        } catch (_) {
          // Store/network absence cannot remove an already delivered right.
        }
      }
      return refreshEntitlement();
    })()
        .whenComplete(() {
      if (identical(_reconcileOperation, operation)) _reconcileOperation = null;
    });
    _reconcileOperation = operation;
    return operation;
  }

  Future<BroadcastAccessSnapshot> _refreshEntitlement() async {
    await _initialization;
    final token = licenseToken;
    final gateway = _purchaseGateway;
    final nowMs = _monoNowMs();
    final lastRefresh = _lastRefreshMonoMs;
    if (_disposed ||
        token == null ||
        gateway is! BroadcastEntitlementRefreshGateway ||
        (lastRefresh != null &&
            nowMs - lastRefresh < entitlementRefreshInterval.inMilliseconds)) {
      return _snapshot();
    }
    _lastRefreshMonoMs = nowMs;
    try {
      final result = await (gateway as BroadcastEntitlementRefreshGateway)
          .refreshLicense(token);
      if (!_disposed &&
          result.licenseToken != null &&
          (result.unlocksAccess ||
              result.failureReason == BroadcastPurchaseFailureReason.revoked)) {
        return await _serialize(() => _persistVerifiedUnlock(result));
      }
    } catch (_) {
      // Temporary network/verification failures do not revoke a paid right.
    }
    return _snapshot();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    try {
      await _initialization;
      await endAllSessions();
    } finally {
      // Storage failure must not leave billing listeners or queued writes
      // alive after the owner has disposed this service.
      await _purchaseUpdates.cancel();
      final gateway = _purchaseGateway;
      if (gateway is BroadcastPurchaseDeliveryGateway) {
        (gateway as BroadcastPurchaseDeliveryGateway)
            .detachDeliveryHandler(_deliverVerifiedPurchase);
      }
      if (ownsPurchaseGateway) await _purchaseGateway.dispose();
      await _mutations.close();
      await _changes.close();
    }
  }

  Future<void> _initializeTrialLedger() async {
    // A durable, verified lifetime grant no longer depends on the trial file.
    // Corruption or a full disk must not revoke a previously purchased right.
    if (_hasValidPersistedEntitlement()) {
      _trialLedgerInitialized = true;
      return;
    }
    if (_entitlementRecord()['status'] == LicenseGrantStatus.revoked.name) {
      _storedUsedMs = _freeLimit.inMilliseconds;
      _trialLedgerInitialized = true;
      return;
    }
    final nowWallMs = _nowMs();
    final encoded = _preferences.getString(_trialLedgerKey);
    late final bool wasActive;
    late final int checkpointWallMs;
    if (encoded == null) {
      // The old keys are read only for migration. After the first successful
      // write, one atomic record is the sole authority for trial accounting.
      _storedUsedMs = (_preferences.getInt(_usedMsKey) ?? 0)
          .clamp(0, _freeLimit.inMilliseconds);
      _lastObservedWallMs =
          _preferences.getInt(_lastObservedWallMsKey) ?? nowWallMs;
      wasActive = _preferences.getBool(_activeMarkerKey) == true;
      checkpointWallMs = _preferences.getInt(_activeCheckpointWallMsKey) ??
          _lastObservedWallMs;
    } else {
      final ledger = jsonDecode(encoded);
      if (ledger is! Map ||
          ledger['version'] != 1 ||
          ledger['usedMs'] is! int ||
          ledger['active'] is! bool ||
          ledger['lastObservedWallMs'] is! int ||
          (ledger['active'] == true && ledger['checkpointWallMs'] is! int)) {
        throw const FormatException('Invalid broadcast trial ledger.');
      }
      _storedUsedMs =
          (ledger['usedMs'] as int).clamp(0, _freeLimit.inMilliseconds);
      _lastObservedWallMs = ledger['lastObservedWallMs'] as int;
      wasActive = ledger['active'] as bool;
      checkpointWallMs =
          ledger['checkpointWallMs'] as int? ?? _lastObservedWallMs;
    }
    if (wasActive) {
      final wallDelta = nowWallMs - checkpointWallMs;
      // Charge at most one checkpoint interval after an unclean shutdown. This
      // bounds lost trial time without charging arbitrary offline time. A wall
      // clock rollback is treated as an unclean full interval.
      final recoveredMs = wallDelta < 0
          ? _checkpointInterval.inMilliseconds
          : min(wallDelta, _checkpointInterval.inMilliseconds);
      _storedUsedMs =
          (_storedUsedMs + recoveredMs).clamp(0, _freeLimit.inMilliseconds);
    }
    await _writeTrialLedger(active: false);
    _trialLedgerInitialized = true;
  }

  Future<void> _loadOfferBestEffort() async {
    try {
      final gateway = _purchaseGateway;
      final offerGateway = gateway is BroadcastProductOfferGateway
          ? gateway as BroadcastProductOfferGateway
          : null;
      if (offerGateway == null) return;
      final offer = await offerGateway.loadOffer(productId: _productId);
      final price = offer?.localizedPrice.trim();
      if (price != null && price.isNotEmpty) {
        _localizedPriceLabel = price;
        await _initialization;
        _publishSnapshot();
      }
    } catch (_) {
      // Store catalog availability is reflected by the purchase operation. A
      // cached/fallback label keeps diagnostics usable while the store is down.
    }
  }

  void _handlePurchaseUpdate(BroadcastPurchaseResult result) {
    _lastPurchaseResult = result;
    final price = result.localizedPrice?.trim();
    if (price != null && price.isNotEmpty) _localizedPriceLabel = price;
    if (_purchaseGateway is BroadcastPurchaseDeliveryGateway) return;
    if (!result.unlocksAccess || _disposed) return;
    unawaited(_initialization
        .then((_) => _serialize(() async {
              return _persistVerifiedUnlock(result);
            }))
        .then<void>((_) {}, onError: (_) {}));
  }

  Future<BroadcastAccessSnapshot> _persistVerifiedUnlock(
    BroadcastPurchaseResult result,
  ) async {
    final token = result.licenseToken;
    if (token != null && token.isNotEmpty) {
      final grant = await _licenseGrantVerifier.verify(token,
          expectedProductId: _productId);
      if (grant.entitlementId != result.entitlementId ||
          grant.transactionFingerprint != result.verificationFingerprint ||
          grant.source != result.verificationSource ||
          (grant.status == LicenseGrantStatus.active &&
              !result.unlocksAccess) ||
          (grant.status == LicenseGrantStatus.revoked &&
              result.failureReason != BroadcastPurchaseFailureReason.revoked)) {
        throw const LicenseGrantException(
            code: 'LICENSE_ENTITLEMENT_MISMATCH',
            message:
                'Signed license does not match the verified store response.');
      }
      return _persistLicenseGrant(grant);
    }
    final source = result.verificationSource?.trim();
    final fingerprint = result.verificationFingerprint?.trim();
    final entitlementId = result.entitlementId.trim();
    if (!result.unlocksAccess ||
        source == null ||
        source.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty ||
        entitlementId.isEmpty) {
      throw const BroadcastPurchaseException(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        message: 'Trusted purchase evidence is missing.',
      ));
    }
    if (_entitlementRecord()['fingerprint'] == fingerprint &&
        _hasValidPersistedEntitlement()) {
      return _snapshot();
    }
    if (_entitlementRecord()['issuedAtMs'] != null) {
      throw const LicenseGrantException(
          code: 'LICENSE_VERIFICATION_UNAVAILABLE',
          message: 'A signed entitlement requires a signed update.');
    }
    final previouslyUnlocked = _hasValidPersistedEntitlement();
    try {
      // Establish an atomic old state before updating compatibility keys. A
      // crash halfway through those writes must never create mixed evidence.
      if (_preferences.getString(_entitlementRecordKey) == null) {
        await _saveEntitlementRecord(_entitlementRecord());
      }
      await _requireSaved(
          _preferences.setString(_verificationSourceKey, source));
      await _requireSaved(
          _preferences.setString(_verificationFingerprintKey, fingerprint));
      await _requireSaved(_preferences.setString(
        _verificationAuthorityKey,
        result.verificationAuthority,
      ));
      await _requireSaved(
          _preferences.setString(_entitlementIdKey, entitlementId));
      await _requireSaved(_preferences.setInt(_verifiedAtMsKey, _nowMs()));
      // Write the grant last, after every piece of trusted evidence is durable.
      await _requireSaved(_preferences.setBool(_unlockedKey, true));
      await _saveEntitlementRecord({
        'unlocked': true,
        'source': source,
        'fingerprint': fingerprint,
        'authority': result.verificationAuthority,
        'entitlementId': entitlementId,
        'verifiedAtMs': _nowMs(),
      });
      _entitlementPersistenceFailed = false;
      _stopLifetimeTrialMeter();
    } catch (_) {
      _entitlementPersistenceFailed = !previouslyUnlocked;
      // Legacy SharedPreferences changes its cache before writing the device.
      // Undo a failed grant in that cache as well, so service recreation cannot
      // mistake an unsaved true value for a lifetime entitlement.
      try {
        await _preferences
            .setBool(_unlockedKey, previouslyUnlocked)
            .timeout(persistenceTimeout);
      } catch (_) {}
      rethrow;
    }
    return _snapshot();
  }

  BroadcastAccessSnapshot _snapshot() {
    final entitlement = _entitlementRecord();
    final unlocked = _hasValidPersistedEntitlement();
    final usedMs = _effectiveUsedMs();
    final freeLimitMs = _freeLimit.inMilliseconds;
    final remainingMs =
        unlocked ? freeLimitMs : (freeLimitMs - usedMs).clamp(0, freeLimitMs);
    return BroadcastAccessSnapshot(
      unlocked: unlocked,
      active: _activeSessions.isNotEmpty,
      freeLimitMs: freeLimitMs,
      usedMs: usedMs.clamp(0, freeLimitMs),
      remainingMs: remainingMs,
      priceLabel: _localizedPriceLabel ?? _fallbackPriceLabel,
      hasStorePrice: _localizedPriceLabel != null,
      productId: _productId,
      entitlementId: entitlement['entitlementId'] as String?,
      purchaseVerifiedAtMs: entitlement['verifiedAtMs'] as int?,
      purchaseVerificationSource: entitlement['source'] as String?,
      purchaseVerificationAuthority: entitlement['authority'] as String?,
      purchaseVerificationFingerprint: entitlement['fingerprint'] as String?,
    );
  }

  bool _hasValidPersistedEntitlement() {
    final record = _entitlementRecord();
    return !_entitlementPersistenceFailed &&
        record['unlocked'] == true &&
        record['authority'] == trustedBackendVerificationAuthority &&
        (record['source'] as String? ?? '').isNotEmpty &&
        (record['fingerprint'] as String? ?? '').isNotEmpty &&
        (record['entitlementId'] as String? ?? '').isNotEmpty &&
        (record['verifiedAtMs'] as int? ?? 0) > 0;
  }

  Map<String, Object?> _entitlementRecord() {
    final encoded = _preferences.getString(_entitlementRecordKey);
    if (encoded != null) {
      try {
        final decoded = Map<String, Object?>.from(jsonDecode(encoded) as Map);
        if (decoded['unlocked'] is! bool ||
            [
              'source',
              'fingerprint',
              'authority',
              'entitlementId',
              'licenseToken',
              'status'
            ].any((key) => decoded[key] != null && decoded[key] is! String) ||
            ['verifiedAtMs', 'issuedAtMs']
                .any((key) => decoded[key] != null && decoded[key] is! int)) {
          throw const FormatException('Invalid entitlement record.');
        }
        return decoded;
      } catch (_) {
        return {'unlocked': false};
      }
    }
    return {
      'unlocked': _preferences.getBool(_unlockedKey) ?? false,
      'source': _preferences.getString(_verificationSourceKey),
      'fingerprint': _preferences.getString(_verificationFingerprintKey),
      'authority': _preferences.getString(_verificationAuthorityKey),
      'entitlementId': _preferences.getString(_entitlementIdKey),
      'verifiedAtMs': _preferences.getInt(_verifiedAtMsKey),
    };
  }

  Future<void> _saveEntitlementRecord(Map<String, Object?> record) async {
    final previous = _preferences.getString(_entitlementRecordKey);
    try {
      await _requireSaved(
          _preferences.setString(_entitlementRecordKey, jsonEncode(record)));
    } catch (_) {
      try {
        if (previous == null) {
          await _preferences
              .remove(_entitlementRecordKey)
              .timeout(persistenceTimeout);
        } else {
          await _preferences
              .setString(_entitlementRecordKey, previous)
              .timeout(persistenceTimeout);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<BroadcastAccessSnapshot> _persistLicenseGrant(
      VerifiedLicenseGrant grant) async {
    if (grant.productId != _productId) {
      throw const LicenseGrantException(
          code: 'LICENSE_PRODUCT_MISMATCH',
          message: 'License product does not match.');
    }
    final previous = _entitlementRecord();
    final lastIssuedAt = previous['issuedAtMs'] as int?;
    if (lastIssuedAt != null &&
        (grant.issuedAtMs < lastIssuedAt ||
            (grant.issuedAtMs == lastIssuedAt &&
                (previous['status'] != grant.status.name ||
                    previous['entitlementId'] != grant.entitlementId ||
                    previous['fingerprint'] != grant.transactionFingerprint ||
                    previous['source'] != grant.source)))) {
      throw const LicenseGrantException(
          code: 'LICENSE_GRANT_STALE',
          message: 'License is older than the saved entitlement state.');
    }
    if (grant.status == LicenseGrantStatus.revoked &&
        (previous['entitlementId'] != grant.entitlementId ||
            previous['fingerprint'] != grant.transactionFingerprint)) {
      throw const LicenseGrantException(
          code: 'LICENSE_ENTITLEMENT_MISMATCH',
          message: 'Revocation does not match this entitlement.');
    }
    if (previous['licenseToken'] == grant.token) return _snapshot();
    await _saveEntitlementRecord({
      'unlocked': grant.status == LicenseGrantStatus.active,
      'source': grant.source,
      'fingerprint': grant.transactionFingerprint,
      'authority': trustedBackendVerificationAuthority,
      'entitlementId': grant.entitlementId,
      'verifiedAtMs': _nowMs(),
      'licenseToken': grant.token,
      'issuedAtMs': grant.issuedAtMs,
      'status': grant.status.name,
    });
    _entitlementPersistenceFailed = false;
    if (grant.status == LicenseGrantStatus.active) {
      _stopLifetimeTrialMeter();
    } else {
      // A refunded lifetime grant does not create a fresh free trial.
      _storedUsedMs = _freeLimit.inMilliseconds;
      _activeStartedAtMonoMs = null;
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
    }
    return _snapshot();
  }

  void _requireTrialOrEntitlement() {
    final error = _trialInitializationError;
    if (error != null && !_hasValidPersistedEntitlement()) throw error;
  }

  int _effectiveUsedMs() {
    final startedAt = _activeStartedAtMonoMs;
    if (_activeSessions.isEmpty || startedAt == null) return _storedUsedMs;
    final elapsed = (_monoNowMs() - startedAt).clamp(
      0,
      _freeLimit.inMilliseconds,
    );
    return (_storedUsedMs + elapsed).clamp(0, _freeLimit.inMilliseconds);
  }

  Future<void> _checkpointActiveElapsed({required bool keepActive}) async {
    if (_hasValidPersistedEntitlement()) {
      _stopLifetimeTrialMeter();
      return;
    }
    final startedAt = _activeStartedAtMonoMs;
    if (startedAt != null) {
      final monoNow = _monoNowMs();
      final elapsed = (monoNow - startedAt).clamp(
        0,
        _freeLimit.inMilliseconds,
      );
      // Account once in memory before awaiting storage. A failed final stop
      // must neither lose elapsed usage nor bill offline time on retry.
      _storedUsedMs =
          (_storedUsedMs + elapsed).clamp(0, _freeLimit.inMilliseconds);
      _activeStartedAtMonoMs = keepActive ? monoNow : null;
    }
    await _writeTrialLedger(active: keepActive);
  }

  void _stopLifetimeTrialMeter() {
    _storedUsedMs = _effectiveUsedMs();
    _activeStartedAtMonoMs = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _trialLedgerDirty = false;
  }

  Future<void> _writeTrialLedger({required bool active}) async {
    final nowWallMs = _nowMs();
    _lastObservedWallMs = max(_lastObservedWallMs, nowWallMs);
    final previous = _preferences.getString(_trialLedgerKey);
    _trialLedgerDirty = true;
    try {
      await _requireSaved(_preferences.setString(
        _trialLedgerKey,
        jsonEncode({
          'version': 1,
          'usedMs': _storedUsedMs,
          'active': active,
          'lastObservedWallMs': _lastObservedWallMs,
          if (active) 'checkpointWallMs': _lastObservedWallMs,
        }),
      ));
      _trialLedgerDirty = false;
    } catch (_) {
      // setString updates the plugin cache before the platform write. Restore
      // the previous record there; the in-memory counter retains unsaved usage
      // for the next checkpoint or start retry.
      try {
        if (previous == null) {
          await _preferences
              .remove(_trialLedgerKey)
              .timeout(persistenceTimeout);
        } else {
          await _preferences
              .setString(_trialLedgerKey, previous)
              .timeout(persistenceTimeout);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _requireSaved(Future<bool> write) async {
    try {
      if (!await write.timeout(persistenceTimeout)) {
        throw StateError('Broadcast access could not be saved.');
      }
      _lastPersistenceError = null;
    } catch (error) {
      _lastPersistenceError = error;
      throw BroadcastAccessPersistenceException(error);
    }
  }

  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    if (_disposed) return;
    _checkpointTimer = Timer.periodic(_checkpointInterval, (_) {
      if (_disposed || _activeSessions.isEmpty) return;
      unawaited(_serialize(() async {
        if (_activeSessions.isNotEmpty) {
          await _checkpointActiveElapsed(keepActive: true);
        }
      }).catchError((_) {}));
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    return _mutations.run(() async {
      try {
        return await operation();
      } finally {
        _publishSnapshot();
      }
    });
  }

  void _publishSnapshot() {
    if (!_disposed && _trialLedgerInitialized && !_changes.isClosed) {
      _changes.add(_snapshot());
    }
  }

  int _nowMs() => _now().millisecondsSinceEpoch;
  int _monoNowMs() =>
      _monotonicNowOverride?.call() ?? _stopwatch.elapsedMilliseconds;

  String _normalizeSessionId(String sessionId) {
    final trimmed = sessionId.trim();
    return trimmed.isEmpty ? 'broadcast' : trimmed;
  }
}
