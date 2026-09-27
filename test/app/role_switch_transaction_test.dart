import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/app/app_runtime.dart';
import 'package:miucam/app/role_repository.dart';
import 'package:miucam/app/role_switch_transaction.dart';

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

  test('holds persistence until runtime and native stop barriers both finish',
      () async {
    final operations = <String>[];
    final roles = _FakeRoleRepository(operations)..role = AppRole.server;
    final stopped = Completer<void>();
    final nativeStopped = Completer<void>();
    final operation = const RoleSwitchTransaction().execute(
      runtime: _FakeRuntime(() => stopped.future),
      previousRole: AppRole.server,
      nextRole: AppRole.client,
      roles: roles,
      confirmStopped: () {
        operations.add('confirm-native');
        return nativeStopped.future;
      },
      clearPairingSession: () async => operations.add('clear-session'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(operations, isEmpty);
    expect(roles.role, AppRole.server);
    stopped.complete();
    await Future<void>.delayed(Duration.zero);
    expect(operations, ['confirm-native']);
    expect(roles.role, AppRole.server);
    nativeStopped.complete();
    await operation;
    expect(operations, ['confirm-native', 'clear-session', 'save-client']);
  });

  for (final failNative in [false, true]) {
    test(
        'shutdown failure does not persist or clear pairing (native=$failNative)',
        () async {
      final operations = <String>[];
      final roles = _FakeRoleRepository(operations)..role = AppRole.server;
      final failure = StateError('Still active');
      await expectLater(
        const RoleSwitchTransaction().execute(
          runtime: _FakeRuntime(() async {
            if (!failNative) throw failure;
          }),
          previousRole: AppRole.server,
          nextRole: AppRole.client,
          roles: roles,
          confirmStopped: () async => throw failure,
          clearPairingSession: () async => operations.add('clear-session'),
        ),
        throwsA(isA<RoleShutdownException>()
            .having((error) => error.cause, 'cause', same(failure))),
      );
      expect(operations, isEmpty);
      expect(roles.role, AppRole.server);
    });
  }
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
