import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/monetization/shared_preferences_pending_room_activation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = SharedPreferencesPendingRoomActivationRepository.storageKey;

void main() {
  for (final stored in <Object?>[
    null,
    true,
    42,
    'room-A',
    {'room': 'A'}
  ]) {
    test('malformed destination container is ignored: $stored', () async {
      final preferences = _DiskPreferences(stored);
      final repository =
          SharedPreferencesPendingRoomActivationRepository(preferences);
      expect(repository.load(), isEmpty);
      expect(preferences.writeCalls, 0);
    });
  }

  test('load retains typed nonempty IDs and deduplicates without coercion',
      () async {
    SharedPreferences.setMockInitialValues({
      _key: <Object?>['room-A', '', 42, null, true, 'room-B', 'room-A'],
    });
    final preferences = await SharedPreferences.getInstance();
    final repository =
        SharedPreferencesPendingRoomActivationRepository(preferences);
    expect(repository.load(), {'room-A', 'room-B'});
    final callerCopy = repository.load()..add('not-persisted');
    expect(callerCopy, contains('not-persisted'));
    expect(repository.load(), {'room-A', 'room-B'});
  });

  for (final throws in [false, true]) {
    test(
        'unconfirmed save reloads durable IDs before rejecting: throws=$throws',
        () async {
      final failure = StateError('Synthetic disk failure');
      final preferences = _DiskPreferences(['durable-room'])
        ..writeAccepted = false
        ..writeFailure = throws ? failure : null
        ..writeGate = Completer<void>();
      final repository =
          SharedPreferencesPendingRoomActivationRepository(preferences);
      final saving = repository.save({'unconfirmed-room'});
      final rejected = expectLater(
          saving, throws ? throwsA(same(failure)) : throwsStateError);
      expect(preferences.cache[_key], ['unconfirmed-room'],
          reason: 'The plugin changes its cache before disk acknowledges.');
      expect(repository.load(), {'durable-room'});
      preferences.writeGate!.complete();
      await rejected;
      expect(preferences.reloads, 1);
      expect(preferences.durable[_key], ['durable-room']);
      expect(repository.load(), {'durable-room'});
      expect(
          SharedPreferencesPendingRoomActivationRepository(preferences).load(),
          {'durable-room'},
          reason: 'Recreating the coordinator must not revive a failed write.');
    });
  }

  test('successful save snapshots caller IDs before asynchronous persistence',
      () async {
    final preferences = _DiskPreferences(['previous-room'])
      ..writeGate = Completer<void>();
    final repository =
        SharedPreferencesPendingRoomActivationRepository(preferences);
    final roomIds = {'room-A', 'room-B'};
    final saving = repository.save(roomIds);
    roomIds
      ..clear()
      ..add('later-room');
    expect(preferences.durable[_key], ['previous-room']);
    expect(repository.load(), {'previous-room'});
    preferences.writeGate!.complete();
    await saving;
    expect(preferences.durable[_key], ['room-A', 'room-B']);
    expect(repository.load(), {'room-A', 'room-B'});
    repository.load().clear();
    expect(repository.load(), {'room-A', 'room-B'});
    expect(preferences.reloads, 0);
    expect(SharedPreferencesPendingRoomActivationRepository(preferences).load(),
        {'room-A', 'room-B'});
    await repository.save({});
    expect(repository.load(), isEmpty);
    expect(preferences.durable[_key], isEmpty);
  });

  test('write and reload failures retain the last confirmed owner snapshot',
      () async {
    final preferences = _DiskPreferences(['initial-room']);
    final repository =
        SharedPreferencesPendingRoomActivationRepository(preferences);
    await repository.save({'confirmed-room'});
    final writeFailure = StateError('Synthetic disk write failure');
    preferences
      ..writeFailure = writeFailure
      ..reloadFailure = StateError('Synthetic reload failure');
    await expectLater(
        repository.save({'unconfirmed-room'}), throwsA(same(writeFailure)));
    expect(preferences.cache[_key], ['unconfirmed-room'],
        reason:
            'An unreadable plugin cache can still contain optimistic data.');
    expect(preferences.durable[_key], ['confirmed-room']);
    expect(repository.load(), {'confirmed-room'});
    repository.load().clear();
    expect(repository.load(), {'confirmed-room'},
        reason: 'A later coordinator using this app-owned repository sees only '
            'the last confirmed destinations.');
  });
}

/// Models the legacy plugin's cache-before-disk contract without native I/O.
class _DiskPreferences implements SharedPreferences {
  _DiskPreferences(Object? initial)
      : durable = {if (initial != null) _key: initial};

  final Map<String, Object> durable;
  late final Map<String, Object> cache = Map.of(durable);
  bool writeAccepted = true;
  Object? writeFailure;
  Object? reloadFailure;
  Completer<void>? writeGate;
  int writeCalls = 0;
  int reloads = 0;

  @override
  Object? get(String key) => cache[key];

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    writeCalls++;
    cache[key] = List<String>.of(value);
    await writeGate?.future;
    if (writeFailure case final failure?) throw failure;
    if (!writeAccepted) return false;
    durable[key] = List<String>.of(value);
    return true;
  }

  @override
  Future<void> reload() async {
    reloads++;
    if (reloadFailure case final failure?) throw failure;
    cache
      ..clear()
      ..addAll(durable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
