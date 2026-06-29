import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/protocol/alert_event_dto.dart';

class ClientAlertHistory {
  ClientAlertHistory({
    SharedPreferences? preferences,
    this.maxItems = 80,
  }) : _preferences = preferences;

  static const storageKey = 'client_alert_history_v1';

  final SharedPreferences? _preferences;
  final int maxItems;
  final _alerts = <AlertEventDto>[];
  final _changes = StreamController<List<AlertEventDto>>.broadcast();
  Future<void> _storageOperation = Future<void>.value();
  var _disposed = false;

  List<AlertEventDto> get alerts => List.unmodifiable(_alerts);
  Stream<List<AlertEventDto>> get changes => _changes.stream;

  Future<void> load() async {
    final preferences = _preferences;
    if (preferences == null) {
      _emit();
      return;
    }
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      _emit();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('history not a list');
      final loaded = <AlertEventDto>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final alert = AlertEventDto.fromJson(Map<String, Object?>.from(item));
        if (alert != null) loaded.add(alert);
      }
      _replaceWith(_mergeAlerts([..._alerts, ...loaded]));
      await _persist();
    } catch (_) {
      await preferences.remove(storageKey);
      if (_alerts.isNotEmpty) await _persist();
    }
    _emit();
  }

  Future<void> add(AlertEventDto alert) async {
    _replaceWith(_mergeAlerts([alert, ..._alerts]));
    await _persist();
    _emit();
  }

  Future<void> clear() async {
    _alerts.clear();
    await _removePersisted();
    _emit();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }

  List<AlertEventDto> _mergeAlerts(List<AlertEventDto> alerts) {
    final seen = <String>{};
    final merged = <AlertEventDto>[];
    for (final alert in alerts) {
      if (!seen.add(alert.id)) continue;
      merged.add(alert);
      if (merged.length == maxItems) break;
    }
    return merged;
  }

  void _replaceWith(List<AlertEventDto> alerts) {
    _alerts
      ..clear()
      ..addAll(alerts);
  }

  Future<void> _persist() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await _enqueueStorage(() async {
      await preferences.setString(
        storageKey,
        jsonEncode(_alerts.map((alert) => alert.toJson()).toList()),
      );
    });
  }

  Future<void> _removePersisted() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await _enqueueStorage(() async {
      await preferences.remove(storageKey);
    });
  }

  Future<void> _enqueueStorage(Future<void> Function() operation) {
    _storageOperation = _storageOperation.catchError((_) {}).then(
          (_) => operation(),
        );
    return _storageOperation;
  }

  void _emit() {
    if (_disposed) return;
    _changes.add(alerts);
  }
}
