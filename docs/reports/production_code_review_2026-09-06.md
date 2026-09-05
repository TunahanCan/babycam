# MiuCam kapsamlı kod incelemesi — 6 Eylül 2026

## Yayın kararı

**Mevcut sürüm production ready değildir.** Aşağıdaki yerel ağ güvenliği ve
gerçek ödeme engelleri açıkken mağaza yayınına onay verilmemelidir. Bu çalışma
`f7a073e` üzerine yapılan kaynak incelemesi, doğrulanmış hata düzeltmeleri ve
regresyon kontrolleridir; bağımsız penetrasyon testi veya mağaza sertifikasyonu
değildir. Değişiklikler yalnız yerel commit olarak hazırlanmıştır.

## Açık bulgular

| Öncelik | Bulgu ve etkisi | Kanıt / gereken tamamlanma |
| --- | --- | --- |
| P0 | HTTP/WS üzerinden bearer token, ses, görüntü ve kontrol verileri şifresiz taşınıyor. Ortak veya ele geçirilmiş yerel ağda gizlilik ve sunucu kimliği korunmuyor. | `lib/core/security/transport_config.dart`, `MiuCamServer` içindeki `HttpServer.bind`. Cihaz anahtarı, QR ile kimlik pinleme, HTTPS/WSS ve bütün istemcilerde kimlik doğrulaması birlikte uygulanmalı; eski eşleşmeler taşınmalı. WebRTC medya şifrelemesi HTTP signaling ve diğer kanalları korumaz. |
| P0 | Eşleştirme açıkken `/status/public` herkese geçerli nonce veriyor; LAN erişimi olan biri `/pair/confirm` ile oda sahibinin fiziksel onayı olmadan kalıcı cihaz olabilir. | `lib/services/server/miucam_server_http_controllers.dart`. Manuel/keşif eşleşmesi fiziksel onaya bağlanmalı. Beş cihaz sınırı, nonce ömrü veya rate limit, sahiplik kanıtı değildir. |
| P1 | Gerçek ömür boyu satışın güvenilir doğrulama backend'i ve mağaza yapılandırması bu depoda yok. İade edilen/iptal edilmiş hakkı cihazda geri alma yolu doğrulanmış değil. | `purchase_verification.dart`, `broadcast_access_service.dart`, [fiyatlandırma sözleşmesi](../broadcast_pricing.md). Yapılandırılmamış derleme ödeme açmayı reddediyor. Sandbox satın alma, geri yükleme, tekrar teslim, ağ/depolama hatası, iade ve iptal uçtan uca sınanmalı. |
| P1 | İki saatlik deneme yalnız oda telefonunun yerel uygulama verisinde. Veriyi silmek veya yeniden kurmak denemeyi yeniden başlatabilir. | `BroadcastAccessService` yerel deneme kaydı. Yeniden kuruluma dayanıklı sınır isteniyorsa hesap/cihaz hakkına bağlı sunucu kaydı gerekiyor. Mevcut sınır oturum başına değil, kurulumda biriken toplam süredir. |
| P2 | DNS-SD tarayıcı başlangıcı ve sunucu reklamı native çağrılarında hâlâ genel bir zaman aşımı yok. Platform cevabı gelmezse başlangıç bekleyebilir. | `lib/services/discovery/miucam_service_discovery.dart`. Browser stop hatası/zaman aşımı bu çalışmada düzeltildi; start/advertiser için geç gelen native kaynak sahipliğiyle birlikte ayrı lifecycle kontrolü gerekli. |
| Yayın kabulü | Fiziksel iOS, güncel Android sürümleri, iki gerçek telefon ve uzun süreli termal/pil kabulü tamamlanmış değil. | Bu ortam Linux ve LG H870/Android 9. Android paketi oluşturmak iOS veya bütün cihazların kabulü değildir. İmzalama, mağaza hesapları ve nihai gizlilik iletişim bilgileri de ayrıca tamamlanmalı. |

Uygulama askıda veya zorla kapatılmışken bildirim garantisi verilmemeli.
Mevcut yerel olay kuyruğu, replay/ACK ve cihaz bildirimi, APNs/FCM teslimatı
sağlamaz. iOS'ta oda kamerası ön planda çalışır; arka plan audio hakkı bu kamera
sınırını kaldırmaz.

## Düzeltilen ve testle doğrulanan bulgular

| Alan | Önceki hata | Düzeltme ve regresyon kanıtı |
| --- | --- | --- |
| Ses başlangıcı — P1 | Bekleyen `start`, daha sonra gelen `stop/dispose` isteğini aşarak sesi ve ağ bağlantısını yeniden açabiliyordu. | `ClientLiveAudioPipeline` başlangıç niyetini nesil ile doğruluyor. `client_live_audio_pipeline_test.dart`. |
| Mikrofon — P1 | Otomatik yeniden başlatmanın geç hatası, kullanıcı durdurduktan sonra yeni kayıt denemesi planlayabiliyordu. | `MicrophoneCaptureService` eski nesilden gelen yeniden denemeyi reddediyor. `microphone_capture_service_test.dart`. |
| Ses/görüntü toparlanması — P2 | Hatalı HTTP yanıtının bitmeyen gövdesi kapatma, tekrar deneme ve kilit görünümünü bekletebiliyordu. | Hata yanıtında akışın bitmesi beklenmiyor. Gerçek HTTP testleri: ses pipeline ve medya supervisor. |
| Medya güven sınırı — P1 | HTTP yönlendirmesi, eşleştirilmiş endpoint dışındaki ses/video veya signaling hedefine geçebiliyordu. | Otomatik yönlendirme reddediliyor; endpoint dışı istek regresyonları. Bu, açık TLS bulgusunun çözümü değildir. |
| WebRTC kaynakları — P2 | Timeout sonrası oluşan peer sızabiliyor; renderer tamamlanmadan cleanup hatası peer temizliğini de atlayabiliyordu. | Geç peer kapatılıyor, renderer durumu gözetiliyor. `flutter_webrtc_client_connector_test.dart` geciktirilmiş MethodChannel testleri. |
| Ninni/rahatlatıcı ses — P1 | Native çıkış bozulunca uygulama “çalıyor” kalıyor, ağlama analizi süresiz duraklayabiliyordu. | Çıkış hatası/zaman aşımı veya üç ardışık ret sonrasında idle, analiz talebi ve UI durumu düzeltiliyor. Tek geçici ret çalmayı durdurmuyor. `room_audio_coordinator_test.dart`. |
| Bildirim teslimi — P1 | Bildirim izni yokken başarısız disk yazısı başarı sayılıyor; ACK sonrası olay yeniden başlatmada kaybolabiliyordu. Aynı ID tekrarında kayıt denenmiyordu. | Geçmiş kalıcı olmadan fallback ACK verilmiyor; yeniden teslimde kayıt tekrar deneniyor. `client_alert_delivery_coordinator_test.dart`, `client_alert_history_test.dart`. |
| Bildirim geçmişi — P1 | Geçerli geçmişi yüklerken yeniden yazma hatası kayıtları silebiliyordu. | Okuma/bozuk veri ile depolama hatası ayrıldı; başarısız temizleme tekrar denenebiliyor. Aynı geçmiş testleri. |
| Gece ışığı — P2 | Yavaş ON işlemi daha yeni OFF işleminden sonra tamamlanıp ışığı açık bırakabiliyordu. | Komutlar sıralı uygulanıyor. `night_light_controller_test.dart`. |
| Yüksek ses / ışık analizi — P2 | Algoritma desteklediği halde production pipeline iki olay türünü açmıyordu. | Üretim yapılandırması tamamlandı; mevcut cry/motion talebi dinamik olarak izleniyor, cooldown korunuyor. Aynı ağlama için ek yüksek ses bildirimi bastırılıyor; bilgi olayları sessiz kalıyor. `server_alert_delivery_scenario_test.dart` gerçek PCM/luma → WebSocket regresyonu ve alert engine testleri. |
| Eşleşmiş oda kimliği — P1 | Odanın güvenli tokenı eksikse başka odanın global tokenı kullanılabiliyordu. Yarım kayıt yanlış endpoint'e token taşıyabiliyordu. | Global fallback kaldırıldı; güvenli token zarfı oda/endpoint/client kimliğine bağlandı; eski kayıt geçişi korundu. `pairing_session_store_test.dart`. |
| Eşleşme kalıcılığı — P1 | `SharedPreferences` false sonucu yutuluyor; geçici güvenli depo hatası profil silebiliyor; yarım silme eski profili geri getirebiliyordu. | Başarısız yazılar bildiriliyor, iyimser cache yeniden yükleniyor, legacy yetki önce kaldırılıyor. Aynı store testleri. |
| Yetki kaldırma yarışları — P1 | Yavaş HTTP body okunurken silinen cihaz kontrol gönderebiliyor; kapatılıp yeniden açılan eşleştirme eski isteğe token verebiliyordu. | Body ve kalıcılık beklemelerinden sonra yetki/nesil tekrar denetleniyor; geç token iptal ediliyor. `pairing_revocation_race_test.dart` gerçek HTTP/disk gecikmeleri. |
| QR ve kaynak sınırları — P2 | Public durum sorguları ekrandaki QR nonce'ını havuzdan çıkarabiliyor; kaynak rate-limit tablosu sınırsız büyüyebiliyordu. Bilinmeyen QR transport'u HTTP'ye düşüyordu. | Ayrı public nonce, 256 kaynak sınırı, QR boyut/endpoint/port/transport doğrulaması; mDNS ve scoped IPv6 korunuyor. Pairing token ve payload testleri. |
| Yerel cihaz keşfi — P2 | Native stop hatasından sonra eski discovery referansı yeni taramayı engelliyordu; takılan stop dispose'u bitirmiyordu. | Listener/reference/cache ayrılıyor, stop üç saniyeyle sınırlı ve dispose hata durumunda da updates stream'i kapatıyor. `miucam_service_discovery_test.dart`. |
| Ömür boyu yayın — P1 | Kalıcı olarak doğrulanmış ücretli hak da deneme dosyasına yazma/okuma hatasından kilitlenebiliyordu. | Ücretli hak deneme muhasebesinden ayrıldı. Bozuk deneme kaydı ve yazılamayan depoyla beş ebeveyn/uzun yayın regresyonu. `broadcast_access_service_test.dart`. |
| Rol ve temiz kurulum — P1 | Başarısız rol veya kurulum işareti yazısı başarı sayılıyordu; eski rol yeniden yüklenebiliyordu. | Tek kanonik rol kaydı, legacy önce temizleme, false-write kontrolü ve cache yenileme. `role_storage_failure_test.dart`. |
| Ödeme doğrulama bağlantısı — P1 | Takılan auth header sağlayıcısı doğrulamayı bitirmiyordu; HTTP 303 başka sunucunun sahte başarılı doğrulamasını kabul ettirebiliyordu. | Header sağlayıcısına timeout; yönlendirme kapalı. `purchase_verification_transport_test.dart` gerçek HTTP/Completer regresyonları. |

## Yetenek kapsamı

- **Aktarım ve gürültü:** PCM çerçeveleme/normalizasyon, WAV/MJPEG parçalama,
  mikrofon yeniden başlatma, istemci jitter/oynatma kuyruğu, backpressure,
  WebRTC fallback ve kaynak temizliği; ağ kopması ve zayıf Wi-Fi profilleri.
  Otomatik PCM ölçümleri insan kulağıyla bütün cihazlarda ses kalitesi kabulü
  değildir; gerçek hoparlör geri beslemesi iki telefonla ayrıca sınanmalıdır.
- **Analiz:** Ağlama benzeri ses, yüksek ses, hareket, global ışık değişimi;
  güvenilir veri kapıları, kesintili PCM, episode/cooldown, oda içinde ninni veya
  ebeveyn konuşurken yanlış uyarıyı önleme. Sentetik pozitif/negatif örnekler
  gerçek bebek sesleriyle duyarlılık/özgüllük veya tıbbi doğruluk iddiası değildir.
- **Ebeveyn bildirimi:** İzin reddi, yerel geçmiş, ACK/replay/yeniden teslim,
  aynı olayın tekrarı, odalar arası izolasyon, erişim süresi bitişi ve bilgi
  düzeyindeki sessiz kanal.
- **Eşleşme:** QR, manuel IP, discovery, kalıcı hatırlama, oda değiştirme,
  token yenileme, kayıp cihazı kaldırma, beş eşzamanlı ebeveyn, altıncıyı
  reddetme ve token iptalinde bağlantı kapatma.
- **Kontroller ve yaşam döngüsü:** Ninni/white noise, karşılıklı konuşma,
  gece ışığı, kamera/mikrofon izinleri, rol değişimi, Android foreground service,
  iOS arka plan sözleşmesi, kaynak ve kalite bütçeleri.
- **Ücret:** Oda telefonunda toplam iki saat, ses/görüntü ve yalnız olay takibinin
  ortak sayacı, ücretsiz yerel önizleme, yeniden başlatma/saat değişimi,
  depolama hatası, mağaza sorgusu takılması, doğrulanmamış ödemeyi reddetme.
  Türkiye hedefi tek seferlik 350 TL; diğer bölgede mağaza fiyatı kullanılır.
- **Yerelleştirme ve erişilebilirlik:** Türkçe, İngilizce, Almanca, Fransızca,
  İspanyolca, Arapça, Hintçe ve Çince; uygulamada dokuz locale (Çince varyantları
  dahil). Bildirim olay/önem/tür metinleri, 405 kombinasyon, dar ekran, büyük
  yazı, RTL ve native izin/bildirim kaynakları otomatik kontrollerde kapsanır.
  Anadil uzmanı metin kabulü yapılmış sayılmaz.
- **Web sitesi:** Mevcut tasarım ve uygulama ekran görüntüleri korundu.
  Kaynak ve 16 yerelleştirilmiş sayfa, sekiz dil/234 anahtar ve tarayıcı smoke
  kontrolleri değerlendirilir. Bu çalışmada site yayınlanmadı.

## Son doğrulama

- Tam Flutter test paketi: **1.023/1.023 geçti**; başlangıca göre 49 ek test.
  Komut: `flutter test --no-pub --reporter expanded` (49 saniye).
- `flutter analyze --no-pub`: sorun yok. `dart format --output=none
  --set-exit-if-changed lib test`: 340 dosya, değişiklik yok.
- Web sitesi kaynak doğrulaması ve oluşturulan 16 sayfanın doğrulaması geçti:
  sekiz dil, 234 çeviri anahtarı. Yedi tarayıcı senaryosu geçti (masaüstü,
  tablet, 320 px dar ekran, mobil Arapça RTL, gizlilik ve JavaScript kapalı).
- Android profile APK ve **imzasız** release AAB oluşturuldu. Native Android
  birim testleri: **7/7 geçti**. Paket üretimi mağaza imzası veya satış onayı
  değildir. APK ZIP 16 KB hizalaması ve 18 adet 64-bit native kütüphanenin ELF
  LOAD hizalaması geçti; gerçek 16 KB cihazda çalıştırılmadı.
- İlk release komutunda integration testten kalan üretilmiş plugin kaydı
  derlemeyi durdurdu. `flutter build appbundle --release` ile paket/plugin
  yapılandırması yenilendi ve release derlemesi geçti. Native Kotlin geçişi
  hakkındaki mevcut toolchain uyarıları devam ediyor.

### LG H870 / Android 9

- Gerçek Android AudioTrack ile kontrollü localhost WAV/PCM sesi üç kez
  başlatılıp durduruldu. Her yaklaşık üç saniyelik kararlı oynatma aralığında
  underrun artışı sıfır; native yazma/oynatma hatası yok. Bu, mikrofon veya
  iki cihaz arasında akustik kalite testi değildir.
- Gerçek test bildirimi Android aktif bildirim listesinden bulundu; testin
  kendi bildirimi kaldırıldı. Bu test sunucudaki gerçek bir ağlama olayından
  doğmuş uçtan uca ebeveyn bildirimi değildir.
- Normal uygulamada bir host istemcisiyle USB üzerinden yönlendirilen HTTP
  aktarımı 30 saniye sürdü: **159 geçerli JPEG**, bozuk kare yok;
  **941.440 PCM byte**, kırpılmış örnek yok. Görüntüde en uzun alım aralığı
  452 ms, seste 401 ms; fiziksel oynatma gecikmesi ölçülmedi.
- Beş rahatlatıcı ses kaydı, duraklatma, ses seviyesi, ekran ışığı, torch ve
  talk yolu geçti. Talk çıkışında 16.000 byte / 25 oynatılan parça doğrulandı.
  Kontrollerin durum yanıtları tekrar okunarak kontrol edildi; bitişte ses ve
  ışık kapatıldı.
- Olay WebSocket'i süre boyunca açık kaldı; bu koşuda gerçek uyarı üretilmedi.
  Önceki [beş host ebeveyn cihaz testi](pairing_lg_h870_2026-09-06.json) ayrı
  kanıttır; bu koşuda beş fiziksel ebeveyn kullanıldığı iddia edilmez.
- Testin 30 saniyelik aktarımı ve ardından oda kontrolleri toplam sayacı
  30.178 ms'den **71.644 ms**'ye taşıdı. Bitişte sayaç pasifti. Test eşleşmesi
  oda ekranından kaldırıldı; eski token hem hemen hem force-stop/yeniden
  açılıştan sonra HTTP 401 aldı. Sayaç yeniden açılıştan sonra değişmedi.
  Test anahtarı ve USB port yönlendirmesi temizlendi.
- Profile APK SHA-256:
  `4c1d8d020e144377175a0c425f5b66114d76b3fe41638bc1286db4243b4bed45`.
  Release AAB SHA-256:
  `b54cc47558948ddaeca1b555342a035611df1b7ffcdabafc68357e041f146874`.

### Cihaz testi sırasında yürütme hatası

Native test çalıştırılırken `flutter drive --profile` komutunda
`--keep-app-running` kullanılmadı. Flutter test sonunda uygulamayı kaldırdı ve
yerel uygulama verilerini sildi. Bu, incelemeyi yapan ajanın yürütme hatasıdır;
uygulamanın olağan güncelleme davranışı değildir.

Normal APK yeniden kuruldu. Test öncesi alınmış sınırlı kayıttan oda rolü,
kurulum işareti ve tam 30.178 ms deneme kaydı geri yüklendi ve diskten
doğrulandı. Diğer yerel ayarların tam yedeği yoktu ve bunlar geri yüklenemedi.
İlk aktarım denemesi yeni kurulumda kamera/mikrofon izni olmadığı için
`MEDIA_START_FAILED` aldı; izinler yeniden verildikten sonraki koşu geçti.

Tekrarını önlemek için benchmark betiğine ve cihaz testi komutlarına
`--keep-app-running` eklendi; cihazda testten önce yedek alma adımı release
belgesine yazıldı. **Bu çalışmada tüm cihaz verilerinin korunduğu söylenemez.**

Ölçüm özeti: [makine tarafından okunabilir kanıt](production_code_review_2026-09-06.json).

Android minimum sürüm kodda yükseltilmedi. Mevcut Flutter ve eklenti çözümüyle
APK minimumu Android 7.0 / API 24; README'deki API 23 iddiası düzeltildi. iOS
minimumu 13.0; iPhone 13 veya üzeri model şartı yoktur.

## Dış kaynakla kontrol edilen sözleşmeler

- [Google Play satın alma güvenliği](https://developer.android.com/google/play/billing/security):
  işlem kanıtının güvenilir backend'de doğrulanması ve iptal/iade yönetimi.
- [Resmî Flutter in_app_purchase paketi](https://pub.dev/packages/in_app_purchase):
  desteklenen platform tabanı ve satın almayı doğrulama/teslim/tamamlama akışı.
- [Android 16 KB sayfa boyutu](https://developer.android.com/guide/practices/page-sizes):
  ZIP hizalaması ve 64-bit ELF segment hizalaması farklı kontrollerdir;
  bunların geçmesi gerçek 16 KB cihaz kabulünün yerini tutmaz.
