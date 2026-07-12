import 'app_role.dart';
import 'app_runtime.dart';
import 'role_repository.dart';

/// Coordinates role persistence and runtime teardown as one recoverable unit.
class RoleSwitchTransaction {
  const RoleSwitchTransaction();

  Future<void> execute({
    required AppRuntime? runtime,
    required AppRole? previousRole,
    required AppRole? nextRole,
    required RoleRepository roles,
    required Future<void> Function() clearPairingSession,
  }) async {
    try {
      await runtime?.dispose();
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
