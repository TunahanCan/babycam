# LG H870 doğrulama raporu — 5 Eylül 2026

Durum: 816 Flutter testi, 7 Kotlin testi ve LG üzerindeki 30 dakikalık LAN
medya/bellek testi geçti. Son APK kuruldu. Bu belge tüm fiziksel cihaz release
matrisinin geçtiği anlamına gelmez.

## Ortam ve kapsam

- Fiziksel cihaz: LG H870, Android 9 / API 28, ARM64; USB ile bağlı ve şarjda.
- Medya: Gerçek Wi-Fi LAN üzerinden LG kamera/mikrofon → Linux test istemcisi.
  Varsayılan MJPEG + 16 kHz, mono PCM16LE/WAV yolu kullanıldı.
- Flutter 3.44.2 / Dart 3.12.2; Linux, Java 21. CI sürümü 3.44.4 / Java 17
  olduğundan bu oturum CI toolchain eşdeğerliği iddiası taşımaz.
- Cihazda profile build; ayrıca unsigned Android release AAB derlemesi.
- İkinci fiziksel telefon yok. İki eşzamanlı host istemcisi sunucunun çoklu
  bağlantısını test eder; iki gerçek ebeveyn telefonunun kabul testi değildir.
- Ham ortam sesi veya kamera görüntüsü rapora kaydedilmedi. Akış çözüldü,
  örnek/kare sayıları ve sinyal istatistikleri tutuldu.

## Düzeltilen sorunlar

| Alan | Bulgu ve düzeltme |
| --- | --- |
| Ses kazancı | Blok sınırında ani kazanç değişimi yapay tıklama üretiyordu. 5 ms geçiş eklendi; sürekli 100 Hz regresyon sinyalinde yapay sınır sıçraması 518 → 6 PCM birimine indi. |
| PCM bütünlüğü | Tek örneğin byte'ları farklı recorder parçalarına düştüğünde analiz/kazanç hizası bozulabiliyordu. Eksik byte artık sonraki parça ile birleştiriliyor. |
| Ses oturumu | Yeni mikrofon/bas-konuş oturumu eski kazancı devralıyordu. Kazanç ve parça kalıntısı oturum başında sıfırlanıyor. |
| Ses oynatma kurtarma | Periyodik native write hatası veya tamamlanmayan write sesin kalıcı durmasına yol açabiliyordu. Hata mevcut yeniden bağlanma yoluna aktarılıyor; native beklemeler sınırlandırılıyor. |
| Adaptif görüntü | Aynı çözünürlükte FPS artışı ve 480p → 720p geçişi bekleme süresini atlayabiliyordu. Kalite boyutları birlikte karşılaştırılıyor; kötü ağ/yeniden bağlantı sonrası stabilite sayacı sıfırlanıyor. |
| MJPEG | Sahte, bozuk veya çelişkili Content-Length alanları kabul edilebiliyordu. Reddedilip sonraki geçerli kareye toparlanıyor. |
| Hareket analizi | BGRA görüntüde yalnız mavi kanal kullanılıyordu; artık RGB luma hesaplanıyor. Hareket enerjisi 0..1 aralığına normalleştiriliyor. |
| Kare sıklığı | Saat geriye alınınca görüntü durabiliyor; hızlı profil değişimleri FPS sınırını atlayabiliyordu. Son kabul edilen kare zamanı doğru korunuyor ve saat geri sıçraması toparlanıyor. |
| Gece ışığı | Android servis kamerasında torch komutu yoktu. CameraX ON/OFF ve sonucunu bekleyen köprü eklendi; kapanış/timeout ışığı kapatıyor. Torch → ekran ışığı geçişi de torch'u bırakıyor. |
| Bildirim bağlantısı | Sessiz ağ kaybı WebSocket'i bağlı gösterebiliyordu. İki uçta ping/liveness ile ölü bağlantı bırakılıyor ve yeniden bağlanılıyor. |
| Bildirim teslimatı | Geçici native gönderim hatasından sonra yeniden başlatılan istemci bildirimi atlayabiliyordu. Bekleyen teslimat işareti geçmişle birlikte saklanıyor. |
| Android bildirim kategorisi | Tek kategori kapalıyken sonsuz yeniden bağlanma oluşabiliyordu. Kalıcı kategori reddi geçmişte tutulup onaylanıyor; açık kategoriler çalışıyor. |
| Algılama durumu | Ninni veya bas-konuş sırasında ağlama/yüksek ses analizi durduğu halde arayüz bunu açıklamıyordu. Sunucu gerçek `paused/reason` bilgisini yayınlıyor; ebeveyn ekranları duraklamayı ve nasıl devam ettirileceğini gösteriyor. Diğer ebeveynin başlattığı ses de görünür ekranlarda yenileniyor. |
| LG ayarlar görünümü | Güvenilen cihazlar başlığı, yanındaki toplu erişim düğmesi nedeniyle kelime ortasından bölünüyordu. Düğme ayrı satıra alındı. |

Her ürün düzeltmesi ilgili regresyon testleriyle doğrulandı. Kamera lifecycle
testinde beklenen asenkron hata geç gözleniyordu; hata gözlemleme sırası ve
normal başlatma zaman payı da düzeltildi.

## Tamamlanan doğrulamalar

| Kontrol | Sonuç |
| --- | --- |
| Başlangıç Flutter testleri | 774/774 |
| Düzeltmeler sonrası son tam Flutter testleri | 816/816 |
| Kotlin/JVM testleri | 7/7 |
| Dart analiz / format / diff whitespace | Temiz |
| Android profile APK | Oluştu ve LG'ye kuruldu |
| Android release AAB | Oluştu; imzasız, mağazaya yüklenmedi |
| Gerçek AudioTrack oynatma | 3 × yaklaşık 3 saniye; iki stop/restart. İlerleyen playback head, sıfır steady-state underrun, sıfır yazma kaybı/hatası |
| Gerçek Android bildirimi | Gönderim ve aktif sistem bildirimi doğrulandı; yalnız test bildirimi silindi |
| LG arayüz performansı | Slider p95 32,761 ms; scroll p95 24,189 ms. İkisi de 35 ms test bütçesinin altında |
| Kamera/mikrofon izni reddi | İki durumda da kontrollü MEDIA_START_FAILED / HTTP 500; süreç ayakta. İzinler geri açıldı |
| Yalnız görüntü / yalnız ses | İki bağımsız 20 saniyelik LAN akışı geçti |
| Görüntü + ses | Son 20 saniyelik testte 116 geçerli kare, 638.720 PCM byte; bozuk JPEG veya kırpılmış PCM örneği yok |
| Oda kontrolleri | Beyaz/pembe gürültü, yağmur, ninni, piş piş; play/pause/stop/volume ve state readback geçti |
| Bas-konuş | 16.000 byte / 25 PCM blok alımı ve oynatma kabulü, oturum kapanışı doğrulandı |
| Gerçek torch | Native ON → ekran ışığı → OFF komutları ve durumları doğrulandı |
| Arka plan / ekran kilidi | Önceki profile kısa koşusunda 90 s boyunca 474 kare; ses/görüntüde 500 ms üzeri veri boşluğu yok |
| İki istemci | İki ayrı host kimliğiyle eşzamanlı 30 s; iki ses/video akışı ve olay bağlantıları geçti |
| Gerçek algılama durumu | Son APK üzerinde idle, sıfır sesli ninni, pause, talk ve talk stop için `/status` ve `/comfort/state` sonuçları birbirini doğruladı |
| Son kurulan APK | 60 s; 305 görüntü karesi, 1.919.360 PCM byte, dijital kırpılma / 500 ms üzeri aralık yok; 10 oda kontrolü ve olay bağlantısı geçti |
| Erişim iptali | Ayarlar'dan yalnız iki host test kimliği kaldırıldı; açık ses/görüntü akışı kapandı, iki eski trusted token HTTP 401 aldı |
| Test araçları | Device matrix self-test/dry-run; LAN probe erken EOF, susan stream, sağlıklı PCM ve rapor sınırı self-testleri geçti |

AudioTrack testinin kaynağı telefondaki kontrollü localhost WAV sunucusudur.
LG mikrofonunun gerçek LAN aktarımı ayrı test edildi. Bu iki test fiziksel
hoparlör kaydı, insanın dinleyerek kalite değerlendirmesi veya gerçek
camdan-cama gecikme ölçümü yerine geçmez.

İlk izin kontrolü, cihaz integration testlerinden sonra rol seçilmemiş kurulumda
çalıştığı için sunucuya ulaşamadı. Sunucu rolü ve eşleşme kurulduktan sonra
senaryo tekrarlandı; tablodaki sonuç bu geçerli ikinci koşuya aittir.
Flutter testleri ve Android derlemeleri aynı üretilmiş plugin kaydını
paylaşıyor. Integration test / normal uygulama geçişinde ve paralel test +
derleme sırasında `integration_test` kaydı release classpath'ine sızdığı için
iki AAB denemesi başarısız oldu. Son doğrulamada Flutter testleri ve Android
derlemeleri sırayla, normal bağımlılık hazırlığıyla çalıştırıldı.
Son profile APK ve 89,9 MB AAB başarıyla oluştu; `jarsigner` AAB'nin imzasız
olduğunu doğruladı. Son tam paketteki iki yeni fullscreen testinin yanlış
selector'ı düzeltildikten sonra 816 testin tamamı geçti.

## Uzun yayın ölçümü

30 dakika ses + görüntü + olay WebSocket'i ölçümü **geçti**. `/status`
örnekleri beş saniyede bir, Android PSS/PID/pil verileri yaklaşık 30 saniyede
bir kaydedildi. Taşıma istatistikleri host alım zamanlarıdır; fiziksel oynatma
veya camdan-cama gecikme olarak yorumlanmamalıdır.

| Ölçüm | Sonuç |
| --- | --- |
| Süre | 1.800 saniye |
| Görüntü | 9.411 kare; 52.735.769 byte; parser hatası 0; bitmap olarak çözülen 95 JPEG örneğinde hata 0 |
| Görüntü alım aralığı | p95 295 ms, en uzun 550 ms; 500 ms üzerinde 5 aralık |
| Ses | 57.584.640 PCM byte; beklenen sürenin %99,978'i |
| Ses alım aralığı | p95 35 ms, en uzun 397 ms; 500 ms üzerinde 0 aralık |
| Ses sinyali | Peak 8.564 / 32.767; dijital kırpılma 0 |
| Durum örnekleri | 358; ses, görüntü ve olay bağlantısı süre boyunca açık |
| Süreç / hata sayaçları | PID 31781 sabit; yeni analiz, taşıma kaybı, yeniden bağlantı veya profil uygulama hatası 0 |
| Bellek | İlk 5 dakika hariç 49 PSS örneği; OLS +69,18 KiB/dk = **0,676 MiB / 10 dk**, <1 MiB kapısı geçti |
| PSS aralığı | 212.068–221.695 KiB; EGL/GL sabit |
| Pil sıcaklığı | 36,1 → 40,1 °C; USB şarjında. SoC sıcaklığı değildir; OS thermal state `unknown` |

Olay soketinin canlılığı ölçüldü; sessiz ortamda gerçek uyarı olayı üretilmedi.
Başlangıçtaki analiz hatası ve ses taşıma kaybı sayaçlarında önceki izin
testlerinden kalan birer kayıt vardı; uzun koşuda bunlar artmadı.
Bu koşu medya/DSP/native düzeltmelerini içerir; sonradan eklenen algılama
durumu ve arayüz uyarıları son APK'da ayrıca kısa testten geçirildi. Soak APK'sı
ayrı saklandı; soak ve son APK SHA-256 değerleri metadata'da ayrıdır.

## Gürültü hakkında sonuç sınırı

Tıklama, örnek hizası ve takılan oynatma için kanıtlı hatalar düzeltildi.
Kısa gerçek LG mikrofon testlerinde dijital clipping görülmedi. Ancak Android
servisinin mikrofon yolu kazanç düzenleyicisini kullanmıyor; kazanç rampası
düzeltmesi tek başına LG kaynaklı tüm gürültünün çözüldüğünü göstermez.
Kullanıcının duyduğu aralıklı gürültü, aynı akustik/cihaz çifti koşullarında
yeniden üretilip kulaktan doğrulanmadı.

## Ninni ve bas-konuş sırasında algılama

Mevcut kendi hoparlör sesini bastırma kuralı, oda ses modu `idle` değilken
**tüm ağlama ve yüksek ses analizini durduruyor**. Ninni döngüsü boyunca,
ses seviyesi sıfır olsa bile bu geçerli. Canlı ses aktarımı ve hareket analizi
devam ediyor. Bu oturumda gerçek yankı giderme / kaynak ayrıştırma eklenmedi;
ürün bu sınırlamayı artık açıkça gösteriyor. “Ninni çalarken ağlama uyarısı
gelir” beklentisini karşılamıyor. Regresyon testleri bu gerçek durumu ve
TR/RTL, dar ekran ve büyük yazıdaki uyarı görünürlüğünü kapsıyor.

## Açık release kapıları

- İkinci fiziksel telefon, Android 13–16, iOS ve iki yönlü çapraz platform
  matrisi; Linux ortamında iOS release derlemesi.
- Gerçek telefon çağrısı/alarm/audio focus, Bluetooth/kablolu ses rotası;
  kontrollü zayıf Wi-Fi, DHCP/AP geçişi ve IPv6-only/link-local ağı.
- WebRTC pilotunun gerçek H.264/Opus `getStats`, fallback ve ayrı soak koşuları.
  Bu koşular varsayılan legacy medya yolunda yapıldı.
- 2 saatlik release soak; bağımsız akustik/video gecikme ölçümü ve gerçek
  bebek sesiyle algılama doğrulaması.
- Ninni/bas-konuş sırasında ağlama algılama gereksinimi varsa gerçek akustik
  yankı giderme ve eşzamanlı bebek sesiyle cihaz doğrulaması.
- Android upload key / mağaza imzası, iOS sertifikaları; hesap, gizlilik ve
  mağaza politika kontrolleri.
- HTTP/WS taşıması TLS/E2E sağlamıyor. Sunucu olay replay'i RAM'de 128 olay /
  2 dakika ile sınırlı; APNs/FCM veya process ölümünden sonra kalıcı sunucu
  teslimatı yok. Uygulama kapalıyken garantili bildirim iddiası yapılamaz.

Bu nedenle test edilen LG akışları için kanıt vardır; uygulamanın tüm
platformlarda koşulsuz production-ready olduğu sonucu çıkarılamaz.

## Cihazın teslim durumu

Son profile APK LG'ye kuruldu; sunucu rolü ve önizleme kapalı yayın ekranında
bırakıldı. Kamera/mikrofon izinleri açık, ninni/talk/ışık kapalı. Integration
testi uygulama eşleşme durumunu sıfırladığı için ebeveyn telefonu yeni QR ile
eşleştirilmelidir. Testte oluşturulan iki host erişimi uygulama arayüzünden
iptal edildi; yerel geçici credential dosyaları silindi.

Erişim iptali için ayrı negatif testte 30 saniyelik açık akış yaklaşık 26,5
saniyede bilinçli olarak kesildi. `revocation-active-probe.json` içindeki
`fail / stream_ended_before_deadline` bu senaryonun beklenen sonucudur;
`final-access-revocation.json` hem kapanışı hem iki HTTP 401 sonucunu doğrular.

## Kanıtlar ve tekrar çalıştırma

Ham yerel kanıtlar: `build/device_validation/2026-09-05/`. Dosyalar `.gitignore`
kapsamında; kamera/ses içeriği ve eşleşme tokenları rapora eklenmez.
`miucam-lg-profile.apk`, SHA-256, cihaz metadata'sı, test/build logları,
integration JSON'ları, her LAN koşusunun JSON/JSONL'i bu dizindedir.
Kalıcı ve medya içermeyen [sayısal sonuç özeti](lg_h870_validation_2026-09-05.json)
bu raporla birlikte saklanır.

```sh
flutter test
flutter analyze
flutter drive --profile --keep-app-running -d DEVICE_ID \
  --target integration_test/device_audio_notification_smoke_test.dart \
  --driver test_driver/device_audio_notification_smoke_driver.dart
flutter drive --profile --keep-app-running -d DEVICE_ID \
  --target integration_test/ui_frame_time_benchmark_test.dart \
  --driver test_driver/ui_frame_time_benchmark_driver.dart

dart run tool/benchmarks/lan_media_device_probe.dart --self-test true
MIUCAM_PROBE_CREDENTIALS=/private/local-credentials.json \
dart run tool/benchmarks/lan_media_device_probe.dart \
  --base-url http://ROOM_IP:8080 --output /private/soak.json \
  --seconds 1800 --events true
```

LAN aracı, credential dosyası yoksa açık eşleşme modundaki odaya test istemcisi
kaydeder. `--controls true` fiziksel oda seslerini ve ışığı kısa süre çalıştırır;
kontroller varsayılan kapalıdır. Araç raporu, iki fiziksel cihaz ve harici ölçüm
gerektiren [release matrisinin](../physical_device_test_matrix.md) yerine geçmez.
