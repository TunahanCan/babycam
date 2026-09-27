import 'package:shared_preferences/shared_preferences.dart';

import 'pending_room_activation_repository.dart';

class SharedPreferencesPendingRoomActivationRepository
    implements PendingRoomActivationRepository {
  SharedPreferencesPendingRoomActivationRepository(this._preferences)
      : _confirmedRooms = _readStoredIds(_preferences);

  static const storageKey = 'broadcast_purchase.pending_rooms';
  final SharedPreferences _preferences;
  Set<String> _confirmedRooms;

  @override
  Set<String> load() => Set<String>.of(_confirmedRooms);

  static Set<String> _readStoredIds(SharedPreferences preferences) {
    final stored = preferences.get(storageKey);
    if (stored is! List) return <String>{};
    // A malformed destination must not prevent app startup or paid restore.
    return stored.whereType<String>().where((id) => id.isNotEmpty).toSet();
  }

  @override
  Future<void> save(Set<String> roomIds) async {
    final savedRooms = Set<String>.of(roomIds);
    try {
      if (!await _preferences.setStringList(
          storageKey, savedRooms.toList(growable: false))) {
        throw StateError('Could not save room activation destination.');
      }
      _confirmedRooms = savedRooms;
    } catch (_) {
      // SharedPreferences writes its cache optimistically before disk confirms.
      // Keep this app-owned repository's last confirmed state if both the write
      // and reload fail. load() never exposes that unconfirmed plugin cache.
      try {
        await _preferences.reload();
        _confirmedRooms = _readStoredIds(_preferences);
      } catch (_) {}
      rethrow;
    }
  }
}
