import 'app_role.dart';
import 'app_runtime.dart';
import 'role_repository.dart';

/// A failed teardown cannot be rolled back by constructing another runtime.
/// The previous owner may still hold hardware or native background leases.
class RoleShutdownException implements Exception {
  const RoleShutdownException(this.cause);

  final Object cause;

  @override
  String toString() => 'ROLE_SHUTDOWN_FAILED: $cause';
}

/// Coordinates role persistence and runtime teardown as one recoverable unit.
class RoleSwitchTransaction {
  const RoleSwitchTransaction();

  Future<void> execute({
    required AppRuntime? runtime,
    required AppRole? previousRole,
    required AppRole? nextRole,
    required RoleRepository roles,
    required Future<void> Function() clearPairingSession,
    Future<void> Function()? confirmStopped,
  }) async {
    try {
      await runtime?.dispose();
      if (runtime != null) await confirmStopped?.call();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(RoleShutdownException(error), stackTrace);
    }
    try {
      await clearPairingSession();
      await _persist(roles, nextRole);
    } catch (error, stackTrace) {
      try {
        await _persist(roles, previousRole);
      } catch (_) {
        // Preserve and report the operation that originally blocked the switch.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _persist(RoleRepository roles, AppRole? role) =>
      role == null ? roles.clearRole() : roles.saveRole(role);
}
