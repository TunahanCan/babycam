import 'package:shared_preferences/shared_preferences.dart';

/// Models durable preferences separately from the alert history's RAM copy.
class FailingAlertPreferences implements SharedPreferences {
  FailingAlertPreferences([Map<String, String> initial = const {}])
      : saved = Map.of(initial);

  final Map<String, String> saved;
  bool failWrites = false;
  bool throwOnWrite = false;
  int writeAttempts = 0;
  int removalAttempts = 0;

  @override
  String? getString(String key) => saved[key];

  @override
  Future<bool> setString(String key, String value) async {
    writeAttempts++;
    if (throwOnWrite) throw StateError('storage unavailable');
    if (failWrites) return false;
    saved[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    removalAttempts++;
    if (failWrites) return false;
    saved.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
