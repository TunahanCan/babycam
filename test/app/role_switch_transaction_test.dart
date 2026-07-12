import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/app/app_runtime.dart';
import 'package:mimicam/app/role_repository.dart';
import 'package:mimicam/app/role_switch_transaction.dart';

void main() {
  test('disposes runtime, clears session, then persists the next role',
      () async {
    final operations = <String>[];
    final roles = _FakeRoleRepository(operations);

    await const RoleSwitchTransaction().execute(
      runtime: _FakeRuntime(() async => operations.add('dispose')),
      previousRole: AppRole.server,
      nextRole: AppRole.client,
      roles: roles,
      clearPairingSession: () async => operations.add('clear-session'),
    );

    expect(operations, ['dispose', 'clear-session', 'save-client']);
    expect(roles.role, AppRole.client);
  });

  test('restores the previous role when switching fails', () async {
    final operations = <String>[];
    final roles = _FakeRoleRepository(operations)..failNextSave = true;

    await expectLater(
      const RoleSwitchTransaction().execute(
        runtime: _FakeRuntime(() async => operations.add('dispose')),
        previousRole: AppRole.server,
        nextRole: AppRole.client,
        roles: roles,
        clearPairingSession: () async => operations.add('clear-session'),
      ),
      throwsStateError,
    );

    expect(
      operations,
      ['dispose', 'clear-session', 'save-client', 'save-server'],
    );
    expect(roles.role, AppRole.server);
  });
}

class _FakeRuntime implements AppRuntime {
  _FakeRuntime(this._onDispose);

  final Future<void> Function() _onDispose;

  @override
  Future<void> dispose() => _onDispose();
}

class _FakeRoleRepository implements RoleRepository {
  _FakeRoleRepository(this.operations);

  final List<String> operations;
  AppRole? role;
  bool failNextSave = false;

  @override
  Future<void> clearRole() async {
    operations.add('clear-role');
    role = null;
  }

  @override
  Future<AppRole?> loadRole() async => role;

  @override
  Future<void> saveRole(AppRole role) async {
    operations.add('save-${role.name}');
    if (failNextSave) {
      failNextSave = false;
      throw StateError('persistence failed');
    }
    this.role = role;
  }
}
