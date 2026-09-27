# Mimari genişletme rehberi

Bu rehber repoda bugün bulunan sözleşmeleri gösterir. Genel mimari ve protokol
ayrıntıları [ARCHITECT.md](../ARCHITECT.md), fiziksel kabul koşulları
[cihaz matrisi](physical_device_test_matrix.md) içindedir.

## Sorumluluk ve sahiplik haritası

| Yapı | Gerçek dosyalar ve sorumluluk |
| --- | --- |
| Composition Root | [AppBootstrap](../lib/app/app_bootstrap.dart), [satın alma kökü](../lib/app/broadcast_purchase_composition_root.dart), [server kökü](../lib/features/server/server_composition_root.dart), [client kökü](../lib/features/client/client_composition_root.dart) bağımlılıkları bağlar. Rol runtime'ı rol değişiminde kapanır; uygulamanın satın alma grafiği yaşamaya devam eder. |
| Runtime facade | [ServerRuntime](../lib/features/server/server_runtime.dart) ve [ClientRuntime](../lib/features/client/client_runtime.dart) ekranlara durum ve işlemler sunar. Ekranlar ayrı bir trial/lisans otoritesi oluşturmaz. |
| Satın alma coordinator | [BroadcastPurchaseCoordinator](../lib/app/broadcast_purchase_coordinator.dart) ödeme hedefini, oda aktivasyonunu ve foreground tekrarlarını yönetir. Yerel hak/deneme kaydı [BroadcastAccessService](../lib/services/monetization/broadcast_access_service.dart) içindedir; server gerektiğinde bu servisi ödünç kullanır. |
| Port ve adapter | [RoomBroadcastAccessGateway](../lib/services/monetization/room_broadcast_access_gateway.dart) oda işlemlerinin portudur; [RemoteBroadcastAccessClient](../lib/features/client/media/remote_broadcast_access_client.dart) HTTP adapter'ıdır. [InAppPurchaseStore ve FlutterInAppPurchaseStore](../lib/services/monetization/in_app_purchase_store.dart) native mağaza sözleşmesini ve adapter'ını taşır. [Ortak ödeme modelleri](../lib/services/monetization/broadcast_access_models.dart) ve [doğrulama sonucu](../lib/services/monetization/purchase_verification_result.dart) platform SDK'sından bağımsızdır. |
| Repository | [PendingRoomActivationRepository](../lib/services/monetization/pending_room_activation_repository.dart) ödeme öncesi oda hedeflerini kalıcılaştırır. [SharedPreferences adapter'ı](../lib/services/monetization/shared_preferences_pending_room_activation_repository.dart) son doğrulanmış snapshot'ı sahiplenir; başarısız yazma/cache yenileme onaylanmamış hedefi kalıcı göstermez. |
| Strategy / Policy | [RetryPolicy](../lib/core/network/retry_policy.dart) gecikmeyi hesaplar; timer sahibi değildir. [MediaResourceGovernor](../lib/services/server/media_resource_governor.dart), [MediaQualitySelector](../lib/services/server/media_quality_selector.dart) ve [EpisodeNotificationPolicy](../lib/analysis/alert/episode_notification_policy.dart) kendi alanlarının kararlarını taşır. |
| Medya kaynağı adapter'ı | [ServerMediaSource](../lib/features/server/media/server_media_source.dart) kaynak sözleşmesidir. [AndroidServiceMediaSource](../lib/services/platform/android_service_media_source.dart) service-owned CameraX/AudioRecord'a bağlanır. Plugin kamera/mikrofon yolu ve deterministik test kaynağı aynı sunucu analiz/fan-out sınırlarına ulaşır. |
| Yaşam döngüsü controller'ı | [MediaRuntimeController](../lib/features/server/media/media_runtime_controller.dart) bağımsız kamera/mikrofon talebini sıralar. [MediaProfileApplyQueue](../lib/services/server/media_profile_apply_queue.dart) eski capture generation'a ait profil işlerini geçersiz kılar. |
| Analiz ve olay ayrımı | [MediaAnalysisCoordinator](../lib/services/server/media_analysis_coordinator.dart) mevcut talebi kontrol eder; saf ses/hareket analizörleri ölçüm üretir. [AlertEngine](../lib/analysis/alert/alert_engine.dart), [episode aggregator](../lib/analysis/alert/episode_notification_aggregator.dart) ve [NotificationComposer](../lib/analysis/alert/notification_composer.dart) karar, zaman içinde birleştirme ve metin üretimini ayırır. |
| HTTP medya yaşam döngüsü | [MjpegStreamService](../lib/features/server/media/mjpeg_stream_service.dart) ve [WavAudioStreamService](../lib/features/server/media/wav_audio_stream_service.dart) frame formatı/istemci kuyruğunu sahiplenir; [HttpMediaResponseLifecycle](../lib/services/server/http_media_response_lifecycle.dart) flush, kopmuş bağlantı kontrolü ve socket deadline kapatmasını paylaşır. |
| Backend domain portları | [domain.py](../backend/miucam_billing/domain.py) `StoreAdapter`, `AcknowledgingStore`, `SignedNotificationStore` Protocol'lerini tanımlar. [BillingService](../backend/miucam_billing/service.py) uzlaştırmayı yürütür; [stores.py](../backend/miucam_billing/stores.py) Google/Apple adapter'larını, [licenses.py](../backend/miucam_billing/licenses.py) repository ve imzalamayı içerir. |

## Yeni analiz veya alarm eklemek

1. Ölçüm/kararı `lib/analysis/` içinde tutun; platform çağrısı, ağ ve ekran
   bağımlılığı eklemeyin. Mevcut analizörler somut sınıflardır; kullanılmayan
   genel bir analizör interface'i varmış gibi tasarlamayın.
2. Kaynak sonucunu `MediaAnalysisCoordinator` üzerinden bağlayın. Devre dışı
   talepte ağır işlem yapılmamalı; capture boşluğu, bozuk PCM/frame ve zaman
   gerilemesi eski kanıtı yeni kayıtla birleştirmemeli.
3. Kullanıcı ayarı gerekiyorsa [DetectionSettings](../lib/core/settings/detection_settings.dart)
   ve [ConfigurationService](../lib/services/configuration_service.dart)
   sözleşmesini güncelleyin. Wire alarm kimlikleri [core/alerts](../lib/core/alerts/)
   altında; DTO dönüşümü [AlertProtocolAdapter](../lib/services/server/alert_protocol_adapter.dart)
   içindedir. Enum adı değişikliği `wireValue` değerini değiştirmemeli.
4. Pozitif örnek kadar sessizlik, parazit, kesinti ve ilgisiz sinyal testleri
   ekleyin. Başlangıç: [analiz testleri](../test/analysis/),
   [kaynak bütçesi](../test/analysis/analysis_pipeline_resource_budget_test.dart),
   [false-alert senaryoları](../test/features/server/analysis_false_alert_scenario_test.dart),
   [gerçek route bildirim zinciri](../test/features/server/server_alert_delivery_scenario_test.dart).

Sentetik sinyallerin geçmesi gerçek bebek/non-cry veri kümesinde doğruluk kanıtı
değildir. Kalibrasyon ve eşik değişikliklerini performans refactor'ıyla gizlice
birleştirmeyin.

## Yeni mağaza veya satın alma davranışı eklemek

Mağaza SDK çağrıları native adapter'da kalır.
[InAppBroadcastPurchaseGateway](../lib/services/monetization/in_app_broadcast_purchase_gateway.dart)
mağaza stream'ini sahiplenir ve **doğrulama → kalıcı teslim → acknowledgement**
sırasını uygular. [Purchase verifier](../lib/services/monetization/purchase_verification.dart)
backend sözleşmesidir; yerel receipt kontrolü lisans vermez.

- Yeni yetenek, onu kullanan dar porta eklenir. Mevcut optional portlar owned
  purchase query, license refresh ve checkout preflight'ı ayrı tutar.
- Backend adapter'ı `StoreAdapter` üzerinden güncel mağaza durumunu döndürür.
  Acknowledgement veya imzalı webhook desteği ayrı Protocol'dür; Apple'a Google
  metodu eklemek gerekmez. Yeni mağaza kimliği desteklenen source ve imza/wire
  sözleşmelerinde açıkça tanımlanmalıdır.
- Pending mağaza onayı UI timeout'undan bağımsızdır. İkinci checkout, geç gelen
  başarı, duplicate stream olayı, disk hatası ve restart aynı teslim yolundan
  geçmelidir. Room hedefi mağaza penceresi açılmadan kalıcı yazılmalıdır.
- Sessiz foreground sorgusu hesap penceresi açmamalı. iOS `AppStore.sync` yalnız
  açık Restore işleminindir. StoreKit `0.4.10+1` pin'i, sessiz JWS recovery'nin
  native davranışına bağlıdır; sürüm yükseltirken bu ayrımı tekrar doğrulayın.
- Sözleşme testleri: [gateway yaşam döngüsü](../test/services/monetization/purchase_delivery_lifecycle_test.dart),
  [native adapter](../test/services/monetization/native_purchase_store_test.dart),
  [kalıcı lisans](../test/services/monetization/broadcast_license_persistence_test.dart),
  [oda hedefi repository](../test/services/monetization/pending_room_activation_repository_test.dart),
  [coordinator](../test/app/broadcast_purchase_coordinator_test.dart),
  [backend domain](../backend/tests/test_domain_contracts.py).

Gerçek mağaza hesabı, imza anahtarı, webhook ve iki cihazlı teslim kabulü ayrıca
[yayın kontrol listesinde](RELEASE_CHECKLIST.md) doğrulanır.

## Yeni capture kaynağı veya transport eklemek

Kaynak için `ServerMediaSource` ve gereken optional luma, preview, policy, torch
ve audio-metadata portlarını uygulayın. Donanımın tek sahibi olmalı; logical
video/audio talebi ile service capture talebi aynı şey değildir. Yeni kaynak
`ServerCompositionRoot` içinde bağlanır. Başlatma geç tamamlandığında eski
generation'ın kapanmış oturuma tekrar bağlanmasına izin vermeyin.

Transport değişikliği [MiuCamProtocolV2](../lib/core/protocol/miucam_protocol.dart),
[ServerSessionRegistry](../lib/services/server/server_session_registry.dart),
[ActiveClientRegistry](../lib/services/server/active_client_registry.dart) ve
client [StreamSessionController](../lib/features/client/media/stream_session_controller.dart)
sözleşmelerini ilgilendirir. Session/attempt kimliği, exact connection lease,
yetkilendirme, fallback ve trial hesabı korunmalıdır. Mevcut WebRTC bir peer'li
opt-in yoldur; genel bir transport plug-in kayıt sistemi yoktur.

Başlangıç testleri: [media runtime](../test/features/server/media_runtime_controller_test.dart),
[Android kaynak portu](../test/services/platform/android_service_media_source_test.dart),
[HTTP uçtan uca](../test/features/server/media_stream_end_to_end_test.dart),
[TCP teardown](../test/features/server/media_stream_teardown_test.dart),
[backpressure](../test/services/server/backpressure_memory_test.dart),
[WebRTC signaling](../test/features/server/webrtc_signaling_endpoints_test.dart).
Codec, ses rotası ve background davranışı fiziksel cihazda ayrıca denenir.

## Yeni ekran veya UI durumu eklemek

Runtime/coordinator durumunu sunum widget'larına aktarın; `build` içinde servis
grafiği, mağaza listener'ı veya capture kaynağı oluşturmayın. Renk/ölçü için
[design tokens](../lib/features/shared/presentation/miucam_design_tokens.dart),
shell için [ortak widget'lar](../lib/features/shared/presentation/miucam_shells.dart),
metin için [l10n katalogları](../lib/l10n/src/) kullanılır. Görünür hata/pending
durumları ilgili domain sonucundan türemelidir.

[Server ekran matrisi](../test/features/server/server_screen_matrix_test.dart),
[watch erişilebilirliği](../test/features/client/watch_and_navigation_accessibility_test.dart),
[room controls](../test/features/client/room_controls_panel_accessibility_test.dart)
ve [purchase card](../test/features/client/client_purchase_card_test.dart)
küçük/yatay ekran, büyük yazı, uzun çeviri ve RTL değişiklikleri için başlangıçtır.
Frame-time kontrolü [screen render budget](../test/features/performance/screen_render_budget_test.dart)
testindedir; gerçek font ve cihaz ekranları ayrıca gözden geçirilir.

## Sıcak yol ve yaşam döngüsü kuralları

- JPEG kuyruğu en yeni frame'i, PCM kuyruğu sınırlı gecikmeyi korur. Kontrol
  işlemleri için olan [SerializedAsyncExecutor](../lib/core/async/serialized_async_executor.dart)
  sınırsız medya frame kuyruğu olarak kullanılmaz.
- Ses pencereleri ve PCM carry tamponları owner içinde sınırlıdır. Dışarı
  dönen byte dizisinin sahipliğini koruyun; yeniden kullanılan tamponu dinleyiciye
  verip sonraki frame'de değiştirmeyin.
- Per-frame/per-chunk yeni timer, HTTP kontrolü, settings yazımı veya büyük
  geçici dizi eklemeyin. FPS gate ve güncel analiz talebi ağır işten önce gelir.
- `Future.timeout` native işi/socket'i iptal etmez. Kaynağın dispose/lease/
  generation sözleşmesini ve geç tamamlanan sonuçların temizliğini koruyun.
- Retry policy yalnız süre hesaplar; timer, subscription ve iptal sahibi
  coordinator/controller'dır. Rol/foreground değişiminde bu sahiplik sınanır.
- Yerel süre aralıklarında monotonic saat kullanın; wire timestamp ve kullanıcıya
  gösterilen tarih ayrı amaçlara sahiptir. Tanılama boyutu sınırlı kalmalı;
  PCM/frame/receipt/lisans tokenları public snapshot'a eklenmemeli.

## Mevcut sınırlar

`MiuCamServer` route/media/session `part` dosyaları aynı private durumu paylaşır;
dosyaya ayırmak burada bağımlılık izolasyonu sağlamaz. Watch presentation'da da
`part` dosyaları vardır. Mevcut davranışı değiştirmeden yeni bir sorumluluğu
ayırırken gereken dar portu çıkarın; yalnız pattern adı için ek katman kurmayın.

Alarm replay bellekte ve süre/adet sınırlıdır. Yerel medya HTTP/WS kullanır.
Mağaza/backend dağıtımı, gerçek cihaz bataryası ve background capture doğrulaması
unit test veya yerel host benchmark'ıyla tamamlanmış sayılmaz.
