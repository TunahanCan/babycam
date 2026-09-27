# Yerel ağ, medya ve bildirim kabul doğrulaması — 27 Eylül 2026

Bu çalışma ses/video akışını ve bildirim kararlarını mevcut üretim sınıflarıyla sınadı. Yeni kabul paketinde gerçek loopback TCP/HTTP bağlantıları, üretim `ClientMediaStreamSupervisor`, WAV/MJPEG ayrıştırıcıları ve `ClientLiveAudioPipeline` birlikte çalıştı. Oda üreticisi kontrollü yerel HTTP sunucusu, hoparlör sınırı ise aldığı PCM verisini kaydeden bir test nesnesiydi. Kamera, mikrofon veya kullanıcı kaydı kullanılmadı.

## Yeni kabul senaryoları

`test/features/client/media_lan_acceptance_test.dart`: **7 test geçti**.

| Senaryo | Doğrulanan davranış |
| --- | --- |
| WAV başlığı, PCM örnekleri ve MJPEG parçalı geliyor | Tek sayılı ağ parçaları örnek sırasını bozmuyor; hoparlöre tam 20 ms / 640 bayt PCM kareleri gidiyor. Görüntü baytları korunuyor. |
| Ses kapatma ve yeniden açma | Ses çıkışı kapanıyor, kapalıyken yeni PCM yazılmıyor; görüntü aynı HTTP bağlantısında devam ediyor. Yeniden açılan ses eski kuyruğu oynatmıyor. |
| İki medya yanıtının bağlantısı sona eriyor | İki kanal yeniden bağlanıp akışa dönüyor; ses sahipliği üst üste binmiyor, eski PCM tekrar oynatılmıyor. |
| Sunucu iki soketi açık tutup veri göndermiyor | Ses ve görüntü ayrı zaman aşımı olayları üretiyor; tekrar bağlantıdan gelen yeni medya işleniyor. |
| Ses uç noktası HTTP 401 dönüyor | Hata gövdesi bitmese de iki kanal duruyor, tek oturum yenileme isteği oluşuyor; yeniden deneme döngüsü açılmıyor. |
| Ses uç noktası HTTP 403 dönüyor | Aynı yetki iptali davranışı doğrulanıyor. |
| İki yanıtın HTTP başlıkları beklenirken rol kapanıyor | Kapanış bağlantı zaman aşımını beklemiyor; terminal kapanıştan sonra yeniden başlatma çağrısı akış veya yeniden deneme üretmiyor. |

Kopma, sessize alma ve rol çıkışında PCM yazımının durması doğrudan kaydedildi. Bekleme sonrası yeni istek/yazım oluşmaması kontrolleri, testteki yeniden deneme aralığını aşan süreyi kapsıyor; uzun süreli pil ölçümü yerine geçmiyor.

## Mevcut zincirlerin yeniden doğrulanması

Yeni 7 test dahil **395 medya/analiz/bildirim testi geçti**. Bu turdaki senaryolar ürün kodunda değişiklik gerektiren bir hata ortaya çıkarmadı.

- Gerçek `MiuCamServer` HTTP uç noktalarında iki ebeveynin eşzamanlı WAV/MJPEG izlemesi, istemci/toplam bağlantı sınırları ve oturum sonlandırmada medya bağlantılarının kapanması.
- Sentetik PCM → üretim ses analizi → olay birleştirme → gerçek yerel WebSocket → istemci geçmişi ve bildirim teslimi zinciri. Sessiz oda, fan/sabit ton, kısa ses patlaması, kalibrasyon, ses verisi kesintisi ve yeniden etkinleştirme kontrol edildi.
- Ninni ve ebeveyn konuşması sırasında kendi sesinden bildirim üretmeme; aynı sırada ebeveynin ses akışını koruma; bastırma bitince yeni sürekli ağlama kanıtının tek bildirim üretmesi.
- Kamera açılışı, genel ışık değişimi, sensör benekleri, hareket alanı ve kısa hareketin elenmesi; sürekli yerel hareketin bildirimi.
- Aynı olayın yeniden tesliminde mükerrer bildirim yapmama, bildirim izni/kanalı kapalıyken geçmişe kaydetme ve teslim hatasının tekrar denenebilmesi.
- Ses tamponu sınırları ve yavaş çıkışta geri basınç; konuşma/ninni sahipliği; WebRTC bağlantı hatası, geç gelen native kaynak ve kapanış hatası davranışları.

## Tekrarlanabilir komutlar

Proje kökünde:

```sh
flutter test --no-pub --reporter expanded \
  test/analysis test/services/server \
  test/features/server/media_stream_end_to_end_test.dart \
  test/features/server/media_stream_teardown_test.dart \
  test/features/server/server_audio_discontinuity_scenario_test.dart \
  test/features/server/analysis_false_alert_scenario_test.dart \
  test/features/server/server_alert_delivery_scenario_test.dart \
  test/features/server/media_resource_counter_test.dart \
  test/features/server/media_runtime_controller_test.dart \
  test/features/server/webrtc_signaling_endpoints_test.dart \
  test/features/server/flutter_webrtc_server_shutdown_test.dart \
  test/features/client/media_lan_acceptance_test.dart \
  test/features/client/client_live_audio_pipeline_test.dart \
  test/features/client/client_live_audio_retry_test.dart \
  test/features/client/client_media_stream_supervisor_test.dart \
  test/features/client/client_alert_delivery_coordinator_test.dart \
  test/features/client/client_alert_listener_test.dart \
  test/features/client/client_media_ownership_test.dart \
  test/features/client/flutter_webrtc_client_connector_test.dart \
  test/features/client/webrtc_client_media_supervisor_test.dart \
  test/features/client/mjpeg_stream_parser_test.dart \
  test/features/client/wav_pcm_stream_parser_test.dart
```

Çalıştırılan SDK: `/home/tnnhn/flutter/flutter/bin/flutter`. Yerel çıktı: `build/media_mock_acceptance_focused.log` (395/395). Yeni dosyanın Dart analizi temiz.

## Doğrulamanın sınırları

Loopback, gerçek kablosuz ağ parazitini ve işletim sisteminin arka plan kısıtlarını modellemez. Hoparlör, kamera ve WebRTC native sınırları test nesneleriyle doğrulandı; bu tur gerçek cihaz kurulumu veya medya yakalama yapılmadı. Pil/ısınma ölçümü, iki fiziksel cihaz arasında uzun süreli akış ve iOS arka plan kabul testi burada yapılmış sayılmaz. Sentetik ağlama ve hareket senaryolarının geçmesi gerçek ev ortamlarındaki yanlış bildirim oranına ilişkin bir ölçüm değildir.
