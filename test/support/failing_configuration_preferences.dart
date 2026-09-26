import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors SharedPreferences' optimistic cache separately from durable values.
class FailingConfigurationPreferences implements SharedPreferences {
  FailingConfigurationPreferences(Map<String, Object> initial)
      : durable = Map.of(initial),
        cache = Map.of(initial);

  final Map<String, Object> durable;
  final Map<String, Object> cache;
  String? failKey;
  bool throwOnWrite = false;

  @override
  double? getDouble(String key) => cache[key] as double?;
  @override
  int? getInt(String key) => cache[key] as int?;
  @override
  bool? getBool(String key) => cache[key] as bool?;
  @override
  Set<String> getKeys() => cache.keys.toSet();
  @override
  Future<bool> setDouble(String key, double value) => _write(key, value);
  @override
  Future<bool> setInt(String key, int value) => _write(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);

  Future<bool> _write(String key, Object value) async {
    cache[key] = value;
    if (key == failKey) {
      if (throwOnWrite) throw StateError('Device storage unavailable');
      return false;
    }
    durable[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    if (key == failKey) return false;
    durable.remove(key);
    return true;
  }

  @override
  Future<void> reload() async => cache
    ..clear()
    ..addAll(durable);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
