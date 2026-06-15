import 'package:shared_preferences/shared_preferences.dart';

class ConfigurationService {
  ConfigurationService(this._prefs);

  static const _generalPrefix = 'config.';
  static const _telegramPrefix = 'telegram_config.';
  static const _buildTelegramBotToken = String.fromEnvironment('TELEGRAM_BOT_TOKEN');
  static const _buildTelegramChatId = String.fromEnvironment('TELEGRAM_CHAT_ID');

  final SharedPreferences _prefs;

  static Future<ConfigurationService> load() async => ConfigurationService(await SharedPreferences.getInstance());

  String get telegramBotToken => _buildTelegramBotToken.isNotEmpty ? _buildTelegramBotToken : _prefs.getString('${_telegramPrefix}bot_token') ?? '';
  String get telegramChatId => _buildTelegramChatId.isNotEmpty ? _buildTelegramChatId : _prefs.getString('${_telegramPrefix}chat_id') ?? '';

  double get motionThreshold => _prefs.getDouble('${_generalPrefix}motion_threshold') ?? 0.22;
  int get motionWindowMs => _prefs.getInt('${_generalPrefix}motion_window_ms') ?? 3000;
  int get motionMinDurationMs => _prefs.getInt('${_generalPrefix}motion_min_duration_ms') ?? 2000;
  double get cryScoreThreshold => _prefs.getDouble('${_generalPrefix}cry_score_threshold') ?? 0.65;
  int get cryMinDurationMs => _prefs.getInt('${_generalPrefix}cry_min_duration_ms') ?? 1500;
  int get cryWindowMs => _prefs.getInt('${_generalPrefix}cry_window_ms') ?? 5000;
  int get notifyCooldownMs => _prefs.getInt('${_generalPrefix}notify_cooldown_ms') ?? 60000;

  Future<void> setTelegramBotToken(String token) => _prefs.setString('${_telegramPrefix}bot_token', token);
  Future<void> setTelegramChatId(String chatId) => _prefs.setString('${_telegramPrefix}chat_id', chatId);
  Future<void> setMotionThreshold(double threshold) => _prefs.setDouble('${_generalPrefix}motion_threshold', threshold);
  Future<void> setMotionWindowMs(int windowMs) => _prefs.setInt('${_generalPrefix}motion_window_ms', windowMs);
  Future<void> setMotionMinDurationMs(int durationMs) => _prefs.setInt('${_generalPrefix}motion_min_duration_ms', durationMs);
  Future<void> setCryScoreThreshold(double threshold) => _prefs.setDouble('${_generalPrefix}cry_score_threshold', threshold);
  Future<void> setCryMinDurationMs(int durationMs) => _prefs.setInt('${_generalPrefix}cry_min_duration_ms', durationMs);
  Future<void> setCryWindowMs(int windowMs) => _prefs.setInt('${_generalPrefix}cry_window_ms', windowMs);

  Future<void> resetToDefaults() async {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_generalPrefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
