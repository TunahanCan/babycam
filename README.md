# BabyCam Flutter

BabyCam tek kod tabanlı bir **Flutter** uygulamasıdır. Aynı Dart kodu Android ve iOS üzerinde Server veya Client rolünde çalışacak şekilde ayrıştırılmıştır.

## Özellikler

- Server/Client rol seçimi ve kalıcı tercih.
- Server modunda kamera önizlemesi, LAN HTTP arayüzü, MJPEG video endpoint'i ve UDP discovery yayını.
- PCM16 ses yakalama, ortam gürültüsü takibi, RMS/dBFS ölçümü, bant enerjisi ve süreklilik tabanlı ağlama/inleme analizi.
- Client modunda UDP discovery dinleme, manuel adres girişi, WebView ile yayın izleme ve WebSocket uyarı bildirimi.
- Ortak protokol sabitleri: HTTP `8080`, discovery UDP `45678`, WebSocket `/ws/stream`.

## Kod organizasyonu

```text
lib/
  main.dart                         # Flutter giriş noktası
  core/babycam_protocol.dart        # Portlar, paket tipleri, discovery payload
  core/app_log.dart                 # UI log akışı
  services/audio_analyzer.dart      # Ses/ağlama/inleme skorlaması
  services/motion_analyzer.dart     # Luma downsample, hareket skoru, JPEG encode
  services/babycam_server.dart      # Kamera, mikrofon, HTTP, MJPEG, WAV, WebSocket server
  services/configuration_service.dart # Telegram/eşik ayarları
  services/discovery_service.dart   # UDP broadcast/listen
  services/network_address_provider.dart # Yerel IPv4 adres bulma
  services/notification_service.dart# Yerel bildirimler
  services/telegram_service.dart    # Telegram Bot API
  ui/home_page.dart                 # Server/Client ekranları
```

Port kapsamı için `docs/kotlin_to_flutter_porting_matrix.md` dosyasındaki Kotlin -> Dart eşleştirme tablosuna bakın.

## Build

Flutter SDK kurulu bir makinede:

```bash
flutter pub get
flutter build apk
flutter build ios
```

iOS derlemesi için macOS + Xcode gerekir.
