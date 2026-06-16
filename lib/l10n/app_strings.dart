import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('tr')];

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;

  bool get isTurkish => locale.languageCode == 'tr';

  String get appTitle => 'MimiCam';
  String get reset => isTurkish ? 'Sıfırla' : 'Reset';
  String get server => 'Server';
  String get client => 'Client';
  String get selectRoleStatus => isTurkish
      ? 'Rol seçin: Server yayın yapar, Client yayını izler.'
      : 'Choose a role: Server streams, Client watches the stream.';
  String serverActiveStatus(String url) => isTurkish
      ? 'Server aktif. Client cihazlarda bu adresi açın: $url'
      : 'Server is active. Open this address on client devices: $url';
  String get clientSearchingLog => isTurkish
      ? 'Client modu: ağda MimiCam server aranıyor.'
      : 'Client mode: searching for a MimiCam server on the network.';
  String get clientActiveStatus => isTurkish
      ? 'Client modu aktif. Server otomatik aranıyor.'
      : 'Client mode is active. Searching for the server automatically.';
  String get alertWebSocketDisconnected => isTurkish
      ? 'Uyarı WebSocket bağlantısı koptu.'
      : 'Alert WebSocket connection was lost.';
  String clientConnectedStatus(String url) =>
      isTurkish ? 'Client bağlı: $url' : 'Client connected: $url';
  String serverAlertLog(String message) =>
      isTurkish ? 'Server uyarısı: $message' : 'Server alert: $message';
  String get roleResetStatus => isTurkish
      ? 'Rol sıfırlandı. Server veya Client seçin.'
      : 'Role reset. Choose Server or Client.';
  String get addressPreparing =>
      isTurkish ? 'Adres hazırlanıyor...' : 'Preparing address...';
  String get serverAddressLabel => isTurkish
      ? 'Server adresi (IP veya IP:8080)'
      : 'Server address (IP or IP:8080)';
  String get waitingForServer =>
      isTurkish ? 'Server bekleniyor...' : 'Waiting for server...';

  String get notificationTitle =>
      isTurkish ? 'MimiCam uyarısı' : 'MimiCam alert';
  String get notificationChannelName =>
      isTurkish ? 'MimiCam Uyarıları' : 'MimiCam Alerts';

  String get telegramMissingConfig => isTurkish
      ? 'Telegram bilgileri boş; mesaj gönderilmedi.'
      : 'Telegram configuration is empty; message was not sent.';
  String telegramStatusCode(int code) =>
      isTurkish ? 'Telegram hata kodu: $code' : 'Telegram error code: $code';
  String telegramConnectionError(String message) => isTurkish
      ? 'Telegram bağlantı hatası: $message'
      : 'Telegram connection error: $message';
  String get telegramTimeout =>
      isTurkish ? 'Telegram zaman aşımı.' : 'Telegram timed out.';
  String telegramServerStarted(String url) => isTurkish
      ? '👋 Merhaba! Baby monitor servisi başlatıldı. Yayın: $url'
      : '👋 Hello! Baby monitor service started. Stream: $url';

  String get cameraNotFound =>
      isTurkish ? 'Kamera bulunamadı.' : 'Camera not found.';
  String serverStartedLog(String url) =>
      isTurkish ? 'Server başladı: $url' : 'Server started: $url';
  String get microphonePermissionMissing => isTurkish
      ? 'Mikrofon izni yok; ses analizi devre dışı.'
      : 'Microphone permission is missing; audio analysis is disabled.';
  String audioAnalysisLog(String summary) =>
      isTurkish ? 'Ses analizi: $summary' : 'Audio analysis: $summary';
  String audioAlert(String reason, int confidencePercent, String summary) =>
      isTurkish
          ? '🔊 $reason. Güven $confidencePercent%. $summary'
          : '🔊 $reason. Confidence $confidencePercent%. $summary';
  String motionAlert(int scorePercent) => isTurkish
      ? '👶 Hareket algılandı. Skor: $scorePercent%'
      : '👶 Motion detected. Score: $scorePercent%';
  String webSocketClientConnected(String address) => isTurkish
      ? 'WebSocket client bağlandı: $address'
      : 'WebSocket client connected: $address';

  String get unknownFundamentalFrequency => isTurkish ? 'belirsiz' : 'unknown';
  String get noSoundReason => isTurkish ? 'Ses yok' : 'No sound';
  String get cryingSound => isTurkish ? 'ağlama' : 'crying';
  String get moaningSound => isTurkish ? 'inleme' : 'moaning';
  String audioSummary(
          {required double dbfs,
          required double ambientDbfs,
          required String f0,
          required int centroidHz,
          required int bandwidthHz,
          required double zcr,
          required double entropy,
          required int cryPercent,
          required int moanPercent}) =>
      isTurkish
          ? 'seviye ${dbfs.toStringAsFixed(1)} dBFS, ortam ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, merkez $centroidHz Hz, bant $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropi ${entropy.toStringAsFixed(2)}, ağlama $cryPercent%, inleme $moanPercent%'
          : 'level ${dbfs.toStringAsFixed(1)} dBFS, ambient ${ambientDbfs.toStringAsFixed(1)} dBFS, F0 $f0, center $centroidHz Hz, band $bandwidthHz Hz, ZCR ${zcr.toStringAsFixed(2)}, entropy ${entropy.toStringAsFixed(2)}, crying $cryPercent%, moaning $moanPercent%';
  String pitchSuffix(int fundamentalHz) => fundamentalHz > 0
      ? (isTurkish
          ? ', temel frekans $fundamentalHz Hz'
          : ', fundamental frequency $fundamentalHz Hz')
      : '';
  String cryLikeReason(String pitch, int centroidHz) => isTurkish
      ? 'Ağlama benzeri vokal ses$pitch, parlaklık $centroidHz Hz'
      : 'Cry-like vocal sound$pitch, brightness $centroidHz Hz';
  String moanLikeReason(String pitch, int centroidHz) => isTurkish
      ? 'İnleme benzeri düşük frekanslı sürekli ses$pitch, merkez $centroidHz Hz'
      : 'Moan-like low-frequency sustained sound$pitch, center $centroidHz Hz';

  String get streamActiveHtml =>
      isTurkish ? 'LAN MJPEG yayını aktif.' : 'LAN MJPEG stream is active.';
  String get audioOnlyHtml =>
      isTurkish ? 'Sadece WAV ses akışı' : 'WAV audio stream only';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) => SynchronousFuture(AppStrings(
      locale.languageCode == 'tr' ? const Locale('tr') : const Locale('en')));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
