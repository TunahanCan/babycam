import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../l10n/app_strings.dart';
import 'configuration_service.dart';

class TelegramService {
  TelegramService(this._config, {required AppStrings strings, this.onLog}) : _strings = strings;

  final ConfigurationService _config;
  final AppStrings _strings;
  final void Function(String message)? onLog;

  Future<void> sendMessage(String text) async {
    final token = _config.telegramBotToken;
    final chatId = _config.telegramChatId;
    if (token.isEmpty || chatId.isEmpty) {
      onLog?.call(_strings.telegramMissingConfig);
      return;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.https('api.telegram.org', '/bot$token/sendMessage'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'chat_id': chatId, 'text': text}));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        onLog?.call(_strings.telegramStatusCode(response.statusCode));
      }
    } on SocketException catch (error) {
      onLog?.call(_strings.telegramConnectionError(error.message));
    } on TimeoutException {
      onLog?.call(_strings.telegramTimeout);
    } finally {
      client.close(force: true);
    }
  }
}
