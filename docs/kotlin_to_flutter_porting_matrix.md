# Kotlin -> Flutter/Dart Porting Matrix

Bu dosya eski Android/Kotlin kaynaklarının her birinin Flutter/Dart karşılığını gösterir. Amaç eski repodaki hiçbir uygulama sorumluluğunun sessizce düşmemesidir.

| Eski Kotlin dosyası | Sorumluluk | Flutter/Dart karşılığı |
| --- | --- | --- |
| `AppLogBuffer.kt` | Zaman damgalı ekran log tamponu | `lib/core/app_log.dart` |
| `BabyCamProtocol.kt` | Portlar, paket tipleri, discovery payload parse/serialize | `lib/core/babycam_protocol.dart` |
| `AudioNormalizer.kt` | PCM16 normalize, RMS dB, zero-cross rate | `lib/services/audio_analyzer.dart` |
| `AudioAmbientTracker.kt` | Ortam ses seviyesini adaptif izleme | `lib/services/audio_analyzer.dart` |
| `AudioBandEnergyCalculator.kt` | Goertzel frekans/bant enerjisi | `lib/services/audio_analyzer.dart` |
| `AudioPatternAnalyzer.kt` | Cry score, band balance, smoothing | `lib/services/audio_analyzer.dart` |
| `LumaDownsampler.kt` | Luma stride farkındalıklı downsample | `lib/services/motion_analyzer.dart` |
| `MotionScoreCalculator.kt` | Hareket gürültü tahmini ve smoothing | `lib/services/motion_analyzer.dart` |
| `MotionAnalyzer.kt` | Kamera frame analizi, background update, JPEG callback | `lib/services/motion_analyzer.dart` + `lib/services/babycam_server.dart` |
| `ImageUtils.kt` | Kamera frame -> JPEG dönüşümü | `CameraImageJpegEncoder` (`lib/services/motion_analyzer.dart`) |
| `NetworkAddressProvider.kt` | Yerel IPv4 `ip:port` bulma | `lib/services/network_address_provider.dart` |
| `BabyCamDiscovery.kt` | UDP broadcast/listener | `lib/services/discovery_service.dart` |
| `LiveStreamServer.kt` | HTTP `/`, `/video`, `/audio`, `/status`, WebSocket AV/alert | `lib/services/babycam_server.dart` |
| `ConfigurationHelper.kt` | Telegram ve eşik ayarları | `lib/services/configuration_service.dart` |
| `BabyMonitorService.kt` | Kamera/mikrofon yakalama, motion/cry duration windows, cooldown, Telegram/client alert | `lib/services/babycam_server.dart` + `lib/services/telegram_service.dart` |
| `MainActivity.kt` | İzinler, rol/UI, log akışı, client WebView/alert | `lib/ui/home_page.dart` |
| `ui/theme/Color.kt` | Material renkleri | `ThemeData(colorSchemeSeed: Colors.pink)` (`lib/main.dart`) |
| `ui/theme/Theme.kt` | Material tema seçimi | `ThemeData(... useMaterial3: true)` (`lib/main.dart`) |
| `ui/theme/Type.kt` | Typography başlangıç ayarı | Flutter Material typography defaults (`lib/main.dart`) |

## Bilerek platforma taşınan parçalar

- Android foreground service/wake-lock modeli Flutter tarafında `wakelock_plus` ve uygulama lifecycle'ı ile temsil edilir.
- Android native notification channel detayları `flutter_local_notifications` üzerinden platform eklentisine bırakılır.
- Android CameraX geniş açı lens filtresi Flutter `camera` eklentisinin döndürdüğü kamera listesine indirgenmiştir; platformlar arası API lens focal-length filtrelemeyi standart sunmadığı için ilk uygun kamera seçilir.
