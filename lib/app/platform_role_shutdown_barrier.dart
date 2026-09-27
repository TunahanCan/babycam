import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/platform/platform_runtime_contract.dart';

/// Native stop commands may acknowledge before the service processes them.
/// Poll only during a role handoff, then release the next runtime's start gate.
class PlatformRoleShutdownBarrier {
  PlatformRoleShutdownBarrier({
    Future<PlatformRuntimeSnapshot> Function()? readSnapshot,
    this.timeout = const Duration(seconds: 8),
    this.pollInterval = const Duration(milliseconds: 100),
  }) : _readSnapshot = readSnapshot ?? _nativeSnapshot;

  final Future<PlatformRuntimeSnapshot> Function() _readSnapshot;
  final Duration timeout;
  final Duration pollInterval;

  static Future<PlatformRuntimeSnapshot> _nativeSnapshot() =>
      const PlatformRuntimeContract().snapshot(
        requireNative: !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS),
      );

  Future<void> waitUntilStopped() async {
    final elapsed = Stopwatch()..start();
    while (true) {
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
            'Previous role still owns native resources.', timeout);
      }
      final snapshot = await _readSnapshot().timeout(remaining);
      if (!snapshot.hasActiveRoleResources) return;
      final delay = timeout - elapsed.elapsed;
      if (delay <= Duration.zero) continue;
      await Future<void>.delayed(delay < pollInterval ? delay : pollInterval);
    }
  }
}
