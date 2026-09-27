# Kapsamlı kod incelemesi ve mimari düzenleme

Tarih: 27 Eylül 2026. İnceleme tabanı: `3911ce8`.

Amaç; yerel ağdaki bebek izleme, ilgili bildirimler ve ebeveynin ödediği aile
lisansı davranışını korurken kaynak kullanımını azaltmak, sahiplik sınırlarını
netleştirmek ve yeni geliştirmeleri daha okunabilir hale getirmektir. Bu kayıt,
önceki [satın alma uygulama kaydının](purchase_implementation_2026-09-27.md)
üzerindeki değişiklikleri anlatır.

## Kapsam ve yaklaşım

| Alan | İncelenen sınır / davranış |
| --- | --- |
| Uygulama | Bootstrap, rol değişimi, yaşam döngüsü, composition root, satın alma sahibinin ekranlardan bağımsızlığı. |
| Sunucu ve medya | Oturum yönetimi, MJPEG/WAV bağlantı kapanışı, PCM talkback çerçeveleri, sınırlı tamponlar, capture abonelikleri. |
| Analiz ve bildirim | Ses pencereleri, kalibrasyon, video/olay birleştirme, cooldown ve episode politikaları; analiz sonucunun bildirim kararından ayrı olması. |
| İstemci ve UI | Yayın/ses sahipliği, oda değişimi ve eşleştirme iptali, arka plan sayaçları, ikon semantiği, dokuz dil ve iki ekran boyutu. |
| Monetization | Mağaza adaptörü, kalıcı hak teslimi, restore/revoke, oda lisansı aktarımı, başarısız disk yazıları ve geç dönen işler. |
| Native | Android capture/AudioTrack/foreground servis, iOS AVFoundation akışı ve kapanış sahipliği kod üzerinden incelendi. |
| Backend | Google/Apple adaptör sözleşmeleri, HTTP/use-case sınırı, kaynak/durum enumları, SQLite ve imza uyumluluğu. |

Bağımlılık grafiği bütün `lib/` import/export ilişkilerinde denetlendi. İnceleme
bütün dosyaların baştan yazılması anlamına gelmez: mevcut policy, serialized
executor, runtime facade ve composition root yapıları korundu. Yeni katmanlar
somut bir değişim veya test sınırı olduğunda eklendi.

## Düzeltilen bulgular

| Öncelik | Bulgu ve etkisi | Düzeltme / kanıt |
| --- | --- | --- |
| P2 | PCM16 assembler her frame'de kalan büyük HTTP paketini kaydırıyordu; kopyalama maliyeti paket boyutuyla gereksiz büyüyordu. | Her frame bir kez kopyalanıyor; kalan veri tamponu tek frame ile sınırlı. Rastgele parçalama, frame sahipliği ve büyük paket regresyonları. |
| P2 | Ses analizinde her pencere için yeni Int16 ve double çalışma dizileri ayrılıyordu. | Analizöre ait, ihtiyaç halinde ayrılan scratch dizileri tekrar kullanılıyor; ring buffer toplu kopyalama yapıyor. 60 saniyelik sentetik girdide önceki sürümün 237 pencere sonucu birebir korundu. |
| P2 | Geçersiz window/hop değerleri sıfır örnek üreterek ilerlemeyen analiz döngüsüne girebiliyordu. | Constructor sınırında pozitif ve en az bir örnek içeren değerler zorunlu; release modunda da geçerli. |
| P2 | Servis kartı uygulama arka plandayken iki saniyede bir native snapshot sorguluyordu; QR süre dolumu da arka planda yenileme başlatabiliyordu. | Lifecycle observer timer sahipliğini yönetiyor. Geç yanıtlar ve eski QR payload'ları uygulanmıyor. 20 saniye arka plan testinde ilave native çağrı yok. |
| P2 | İkon düğmesinin dış Semantics düğümünde dokunma aksiyonu eksikti. | `Semantics.onTap` eklendi; ekran okuyucu aksiyonu gerçekten çalıştırılarak doğrulandı. |
| P2 | Eşleştirme silinse/iptal edilse de app ömürlü satın alma koordinatörü eski oda kimliğini tutabiliyordu. Geç checkout/HTTP yanıtı eski odaya aktivasyon gönderebilir veya UI durumunu diriltebilirdi. | `forgetRoom` ilk await öncesi hedefi geçersiz kılıyor. Oda generation kontrolü aynı kimlikle yeniden eşleştirmeyi de kapsıyor. Aile satın alımı korunuyor; rol/oda seçimi bu iptal davranışını tetiklemiyor. |
| P2 | Başarılı LAN tesliminden sonraki pending-temizleme yazısı başarısızsa oda kuyruktan çıkıyor, UI beklemede kalıyor ve retry hedefi kayboluyordu. | Odanın doğruladığı erişim sonucu görünür kalıyor; kalıcı temizlik tekrar denenmek üzere kuyrukta tutuluyor. Tekrar ödeme veya gereksiz aktivasyon gerekmiyor. |
| P2 | Pending hedeflerin SharedPreferences cache'i disk onayından önce değişiyordu. Başarısız yazı, repository sahibine kalıcıymış gibi görünebilirdi. | Repository son doğrulanmış snapshot'ı tutuyor; girdiyi await öncesi kopyalıyor. Yazma ve reload birlikte başarısız olduğunda da önceki doğrulanmış değer korunuyor. Checkout'tan önce hedef yazımı başarısızsa mağaza açılmıyor. |
| P2 | Retry policy sabit/yuvarlamada sabit kalan gecikmelerde attempt sayısı kadar hesap yapıyor; çok büyük multiplier `round()` öncesi sonsuz değere taşabiliyordu. | Sabit dizide erken çıkış ve yuvarlamadan önce üst sınır uygulanıyor. Büyük attempt ve overflow regresyonları; önceki gecikme dizisi korunuyor. |

PCM host mikrobenchmark'ı yalnız algoritma karşılaştırmasıdır. Gerçek telefonun
pil tüketiminde belirli bir yüzde iyileşme veya sahada sıfır yanlış alarm iddiası
yapılmıyor. Bildirim eşikleri ve mesaj politikaları bu refactor için değiştirilmedi.

## Kullanılan tasarım desenleri

| Desen / sınır | Kodda yeri | Genişletme faydası |
| --- | --- | --- |
| Dependency inversion + Adapter | `RoomBroadcastAccessGateway`, `PendingRoomActivationRepository`; HTTP ve SharedPreferences uygulamaları | Koordinatör belirli transport veya depolama sınıfını kurmaz. Testler doğrudan sözleşmeleri uygular. |
| Composition root | `BroadcastPurchaseCompositionRoot` ve mevcut client/server composition root'ları | Somut bağımlılık seçimi tek kurulum noktasında; ürün akışı içinde service locator yok. |
| Repository | Bekleyen oda hedeflerinin yüklenmesi, snapshot sahipliği ve kalıcı kaydı | Disk hataları ile uygulama akışı ayrılır; serial yazılar çağrı anındaki hedef setini korur. |
| Strategy | Enjekte edilen `RetryPolicy`, mevcut analiz/bildirim politikaları | Retry zamanlaması koordinatör durumundan ayrı ve deterministik test edilebilir. |
| Ortak transport yaşam döngüsü | `HttpMediaResponseLifecycle` | MJPEG ve WAV flush/connection/deadline kapanış kuralları tek yerde; formatları ayrı kalır. |
| Saf veri modelleri | `broadcast_access_models.dart`, `purchase_verification_result.dart` | Ortak durumlar/sabitler Flutter mağaza SDK'sını ve HTTP doğrulayıcısını yüklemez. Native store sözleşmeleri native adaptör dosyasındadır. |
| Capability protocol | Backend `domain.py`: `StoreAdapter`, `AcknowledgingStore`, `SignedNotificationStore` | Google ack ve Apple notification farklı yeteneklerdir; yeni adaptör ilgisiz bir metodu taklit etmek zorunda kalmaz. |
| Typed domain boundary | Backend `StoreSource`, `PurchaseStatus`, `StoreFailureReason` | Bilinmeyen değerler kayıt/imza sınırına ulaşmadan reddedilir; mevcut JSON ve SQLite değerleri korunur. |

HTTP Apple notification route'u private store seçimine erişmiyor; public servis
use-case'ini çağırıyor. Adaptör kaydı kurulumdan sonra değişmez. Lisans imzası,
SKU, LAN protokolü ve SQLite şeması değiştirilmedi.

Üç mimari regresyon testi; core/analysis yönünü, saf ödeme değerlerini,
koordinatörün adaptör sınırını ve proje import/export döngülerini denetler.
`part` dosyalarının ortak private state erişimini bu testler izole etmez.

## Doğrulama

Son doğrulama sonuçları:

| Kapı | Sonuç |
| --- | --- |
| Dart format | 386 dosya; son kontrolde değişiklik yok. |
| Flutter analyze | Hata veya uyarı yok. |
| Tam Flutter paketi | **1.260 test geçti**; inceleme tabanına göre 39 yeni test. |
| Ön yüz | Tam pakete dahil dokuz dil × iki boyut client/server matrisi, erişilebilirlik ve lifecycle kontrolleri. Hedef UI koşusu 45 test; runtime/satın alma entegrasyonu hedef koşusu 55 test geçti. |
| Python backend | **92 test geçti**; sekiz yeni domain sözleşme testi. |
| Gerçek HTTP sözleşmesi | Python backend → Dart imza doğrulama → gerçek oda aktivasyonu → imzalı iade/kilitleme testi geçti. Sentetik mağaza fixture'ı kullanır. |
| Android native | `:app:testDebugUnitTest -x compileFlutterBuildDebug` başarılı; mevcut 17 native test Gradle tarafından güncel ve hatasız kabul edildi. |
| Android release | `flutter build appbundle --release` başarılı; `build/app/outputs/bundle/release/app-release.aab`, 92,1 MB. |
| Backend Docker | `docker build -t miucam-billing:review backend` başarılı. |
| Belgeler / diff | Yerel Markdown bağlantıları ve `git diff --check` temiz. |

Tekrar çalıştırma (Flutter/Dart PATH içinde; bu workspace'in Python venv yolu):

```bash
dart format --output=none --set-exit-if-changed lib test tool/tests
flutter analyze
flutter test --reporter expanded
MIUCAM_BACKEND_TEST_PYTHON="$PWD/build/purchase_backend_venv/bin/python" \
  flutter test tool/tests/purchase_backend_contract_test.dart
flutter build appbundle --release
cd backend
../build/purchase_backend_venv/bin/python -m pytest -q
```

Birleşik kanıt dosyaları git dışında `build/review_final_*.log` altında tutulur.
Backend test aracında Starlette/httpx deprecation, Android derlemesinde gelecekteki
Built-in Kotlin geçişi uyarısı mevcut. İkisi de bu doğrulamada hata üretmedi;
araç/SDK yükseltmesi sırasında ayrı uyumluluk işi olarak ele alınmalıdır.

## Kalan sınırlar ve geliştirme sırası

1. `MiuCamServer` medya/oturum `part` dosyaları ortak private state kullanıyor.
   Sonraki büyük transport değişikliğinde capture ve oturum sahiplerini açık
   nesnelere ayırmak faydalıdır. Mevcut çalışma davranışını riske atacak geniş
   bir yeniden yazım bu incelemeye eklenmedi.
2. Üretim sunucusu ve Google/Apple erişimleri kullanıcı tarafından henüz hazır
   olmadığı belirtilen dış bağımlılıklardır. Gerçek mağaza sandbox'ı, HTTPS
   dağıtımı ve iade webhook teslimi canlıda doğrulanmış sayılmaz.
3. iOS native build ve AVFoundation davranışı macOS/fiziksel cihaz gerektirir.
   Android release derlemesi gerçek cihazdaki uzun yayın, ısınma, pil ve ses
   yankısı ölçümünün yerine geçmez.
4. Sentetik analiz ve yanlış alarm regresyonları, farklı odalar/telefonlar ve
   bebek seslerinden oluşan saha kabulünü ikame etmez. Yeni algılama eklenirken
   golden senaryolar ve episode/cooldown testleri birlikte genişletilmelidir.

Günlük geliştirme için dosya haritası ve somut genişletme adımları:
[architecture_extension_guide.md](../architecture_extension_guide.md).
