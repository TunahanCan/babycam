# Kotlin -> Flutter/Dart Porting Matrix

Bu dosya eski Android/Kotlin sorumluluklarının güncel Flutter/Dart karşılıklarını gösterir. Amaç eski uygulama davranışlarının sessizce kaybolmaması ve artık bilinçli olarak kaldırılan parçaların da net görünmesidir.

---

## Güncel Karşılıklar

| Eski Kotlin alanı | Sorumluluk | Güncel Flutter/Dart karşılığı |
| --- | --- | --- |
| `AppLogBuffer.kt` | Zaman damgalı log tamponu | `lib/core/app_log.dart` |
| `MimiCamProtocol.kt` | Portlar, endpointler, paket tipleri | `lib/core/mimicam_protocol.dart`, `lib/core/protocol/mimicam_protocol.dart` |
| `NetworkAddressProvider.kt` | Yerel IPv4 `ip:port` bulma | `lib/services/network_address_provider.dart` |
| `ConfigurationHelper.kt` | Eşikler, süreler, cooldown ve ayarlar | `lib/services/configuration_service.dart` |
| `AudioNormalizer.kt` | PCM/RMS/dBFS yardımcıları | `lib/services/audio_analyzer.dart`, `lib/analysis/audio/pcm16le_reader.dart` |
| `AudioAmbientTracker.kt` | Ortam ses kalibrasyonu | `lib/analysis/audio/audio_calibration_state.dart`, `lib/analysis/audio/cry_audio_analyzer_v2.dart` |
| `AudioBandEnergyCalculator.kt` | Goertzel frekans enerjisi | `lib/analysis/audio/goertzel_band_analyzer.dart` |
| `AudioPatternAnalyzer.kt` | Cry score ve smoothing | `lib/analysis/audio/cry_audio_analyzer_v2.dart` |
| `LumaDownsampler.kt` | Luma stride-aware downsample | `lib/analysis/video/luma_downsampler.dart` |
| `MotionScoreCalculator.kt` | Hareket skoru ve hysteresis | `lib/analysis/video/motion_analyzer_v2.dart` |
| `MotionAnalyzer.kt` | Kamera frame analizi | `lib/analysis/video/*`, `lib/services/server/media_analysis_coordinator.dart` |
| `ImageUtils.kt` | CameraImage -> JPEG | `CameraImageJpegEncoder` (`lib/services/motion_analyzer.dart`) |
| `LiveStreamServer.kt` | HTTP video/audio/status/event endpointleri | `lib/services/mimicam_server.dart` |
| `BabyMonitorService.kt` | Kamera/mikrofon, analiz, alert, cooldown | `lib/services/mimicam_server.dart`, `lib/services/server/media_analysis_coordinator.dart`, `lib/analysis/alert/alert_engine.dart` |
| `MainActivity.kt` | Rol seçimi, izinler, ana UI | `lib/app/app_bootstrap.dart`, `lib/app/role_permission_coordinator.dart`, `lib/features/role_selection/*`, `lib/features/server/*`, `lib/features/client/*` |
| `ui/theme/Color.kt` | Renk tokenları | `lib/core/theme/mimicam_colors.dart`, `lib/features/shared/presentation/mimicam_design_tokens.dart` |
| `ui/theme/Theme.kt` | Material tema | `lib/core/theme/mimicam_theme.dart` |
| `ui/theme/Type.kt` | Tipografi başlangıcı | `MimiCamDesignTokens` + Flutter Material typography |

---

## Yeni Flutter Katmanları

| Yeni alan | Amaç |
| --- | --- |
| `lib/app/role_repository.dart` | Seçilen cihaz rolünü kalıcı saklar. |
| `lib/app/role_resolver.dart` | Açılışta role karar verir. |
| `lib/features/server/server_composition_root.dart` | Sadece Server graph’ını kurar. |
| `lib/features/client/client_composition_root.dart` | Sadece Client graph’ını kurar. |
| `lib/features/server/pairing/*` | QR payload, nonce ve trusted token yönetimi. |
| `lib/features/client/pairing/*` | QR scan, manual IP fallback ve pairing session store. |
| `lib/core/media/adaptive_media_profile.dart` | Cihaz/ağ kalitesine göre medya profili seçimi. |
| `lib/features/client/media/network_quality_monitor.dart` | Client RTT ölçümü ve Server’a quality report gönderme. |
| `lib/l10n/app_strings.dart` | `en`, `tr`, `zh`, `hi`, `es`, `fr` UI ve alert metinleri. |
| `test/features/hard_split_navigation_test.dart` | Server/Client ekranlarının kesin ayrımını doğrular. |
| `test/features/performance/screen_render_budget_test.dart` | Kompakt ekran overflow ve repaint izolasyonunu doğrular. |

---

## Bilerek Kaldırılan veya Kapsam Dışı Bırakılanlar

| Eski alan | Güncel karar |
| --- | --- |
| UDP discovery / broadcast | Kaldırıldı. Eşleşme QR ve manuel IP:port üzerinden yapılır. |
| Telegram otomatik paylaşımı | Kaldırıldı. Alert paylaşımı otomatik relay değildir; gelecek manuel paylaşım akışına bırakılır. |
| Tek ekranda server/client karışık UI | Kaldırıldı. Role göre ayrı shell ve bottom nav kullanılır. |
| Client’ta server kontrol CTA’ları | Kaldırıldı. Client sadece izler/eşleşir/bildirim gösterir. |
| Server’da QR scanner | Kaldırıldı. Server QR üretir; QR tarama Client’a aittir. |

---

## Platforma Taşınan Parçalar

- Android foreground service hedefi `ForegroundServiceController` MethodChannel çağrılarıyla temsil edilir; native kanal production için tamamlanmalıdır.
- Wakelock davranışı `wakelock_plus` üzerinden yönetilir.
- Yerel bildirim altyapısı `flutter_local_notifications` ile soyutlanır.
- Kamera erişimi Flutter `camera` eklentisiyle, mikrofon stream’i `record` eklentisiyle yönetilir.
- QR üretimi `qr_flutter`, QR tarama `mobile_scanner` ile yapılır.
