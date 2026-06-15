import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'configuration_service.dart';

class TelegramService {
  TelegramService(this._config, {this.onLog});

  final ConfigurationService _config;
  final void Function(String message)? onLog;

  Future<void> sendMessage(String text) async {
    final token = _config.telegramBotToken;
    final chatId = _config.telegramChatId;
    if (token.isEmpty || chatId.isEmpty) {
      onLog?.call('Telegram bilgileri boş; mesaj gönderilmedi.');
      return;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.https('api.telegram.org', '/bot$token/sendMessage'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'chat_id': chatId, 'text': text}));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        onLog?.call('Telegram hata kodu: ${response.statusCode}');
      }
    } on SocketException catch (error) {
      onLog?.call('Telegram bağlantı hatası: ${error.message}');
    } on TimeoutException {
      onLog?.call('Telegram zaman aşımı.');
    } finally {
      client.close(force: true);
    }
  }
}
