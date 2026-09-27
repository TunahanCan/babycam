# MiuCam kod incelemesi ve test raporu — 27 Eylül 2026

İncelenen çalışma ağacı: `edf2a2f` ve henüz commit edilmemiş altı haneli
eşleştirme kodu değişiklikleri. İncelemede doğrulanan **8 hata düzeltildi**
(7 P2, 1 P3). Her hata, düzeltme öncesinde başarısız olan bir regresyon testiyle
yeniden üretildi. İncelemenin sonunda açık kalan doğrulanmış bulgu yoktur;
bu sonuç fiziksel cihaz veya mağaza kabulünün tamamlandığı anlamına gelmez.

## Düzeltilen bulgular

| Öncelik | Tetikleyici ve etkisi | Düzeltme ve kaynak |
| --- | --- | --- |
| P2 | Yanıtsız oda için durum sorguları zaman aşımına uğrasa da TCP bağlantıları açık kalıyordu. Üç sorgu üç açık soket bırakıyordu. | Başarısız sorgunun bağlantı havuzu kapatılıyor; başarılı sorgularda keep-alive korunuyor. [NetworkQualityMonitor](../../lib/features/client/media/network_quality_monitor.dart) |
| P2 | Kullanıcı uyarıları kapattıktan sonra uygulamaya dönünce dinleme yeniden açılıyordu. | Ön plana dönüş yalnız zaten açık olan uyarı dinlemesinin izinlerini yeniliyor. [ClientHomeScreen](../../lib/features/client/client_home_screen.dart) |
| P2 | İzleme eylemine ilk ekran çizilmeden iki kez basılması iki WatchScreen ve çakışan yayın sahipliği oluşturuyordu. | Ekran açılışı eşzamanlı olarak kilitleniyor; geri dönüşte yeniden açılabiliyor. [ClientHomeScreen](../../lib/features/client/client_home_screen.dart) |
| P2 | Genel eşleştirme denemelerinin kaynak tablosu dolunca geçerli QR da HTTP 429 alıyordu. | QR ve kod denemeleri ayrı, kapasitesi ve süresi sınırlı tablolar kullanıyor. [PairingTokenService](../../lib/features/server/pairing/pairing_token_service.dart) |
| P2 | Başarısız mikrofon akışının geciken temizliği, bu sırada yeniden başlatılmış kaydı durdurabiliyordu. | Bekleyen iptal tamamlandıktan sonra oturum nesli yeniden doğrulanıyor. [MicrophoneCaptureService](../../lib/features/server/media/microphone_capture_service.dart) |
| P2 | Ayrılan MJPEG istemcisinin bekleyen gönderimi tamamlanınca silinen yanıt nesnesi metrik tablosuna yeniden ekleniyordu. | Başarı kaydı yalnız halen bağlı istemci için yazılıyor; ilk kare ve sonraki yayınlar test edildi. [MjpegStreamService](../../lib/features/server/media/mjpeg_stream_service.dart) |
| P2 | Backend gövde okuma süresi her parçada yeniden başlıyordu. Küçük parçaları yavaşça göndermek isteği uzun süre açık tutabiliyordu. | Tüm gövde için tek 10 saniyelik sınır uygulanıyor. ASGI mesaj listesi yerine 128 KiB sınırındaki bayt tamponu kullanılıyor; süre aşımı 408 dönüyor. [BodyLimitMiddleware](../../backend/miucam_billing/app.py) |
| P3 | Son ses dinleyicisi ayrıldığında yarım PCM paketi kalıyor, sonraki oturum eski örneklerle başlayabiliyordu. | Son istemci ayrılınca paket tamponu sıfırlanıyor. [WavAudioStreamService](../../lib/features/server/media/wav_audio_stream_service.dart) |

## İnceleme kapsamı

- PIN/QR eşleştirme, deneme sınırları, süre dolması, güvenilir cihaz tokenları,
  kalıcı saklama, yenileme ve erişim iptali yarışları.
- İstemci ekran geçişleri, keşif, yeniden bağlantı, yayın sahipliği, uyarı
  tercihleri ve yaşam döngüsü.
- Sunucu kamera/mikrofon yaşam döngüsü, MJPEG/WAV, yavaş tüketici kontrolü,
  kaynak temizliği ve Android medya köprüsü.
- Uygulama açılışı ve rol değişimi; satın alma koordinasyonu, lisans doğrulama,
  backend HTTP katmanı ve kalıcı lisans işlemleri.
- Android ve iOS yerel yaşam döngüsü/ses kodu; çok dilli statik web sitesi.

Medya taşıması mevcut HTTP/WS davranışını koruyor. PIN yalnız eşleştirmede
denetleniyor; bu incelemede TLS veya görüntü/ses şifrelemesi eklenmedi.

## Doğrulama sonuçları

| Kontrol | Sonuç |
| --- | --- |
| Flutter testleri | **1.414 geçti**: `test/` altında 1.413 test ve Python → Dart satın alma/lisans HTTP sözleşmesi için 1 test |
| Python backend | **95 geçti** |
| Android Kotlin/JVM | **17 geçti**, `:app:testDebugUnitTest` başarılı |
| Android debug APK | Derlendi: `build/app/outputs/flutter-apk/app-debug.apk` |
| Flutter statik analiz | Sorun yok |
| Dart biçim kontrolü | 402 dosya; değişiklik gerekmiyor |
| Site kaynak ve derleme doğrulaması | 8 dil, 266 anahtar, 16 üretilmiş sayfa başarılı |
| Chrome tarayıcı kontrolü | Masaüstü, tablet, RTL mobil, 320 px, JavaScript kapalı görünüm, dil rotaları, klavye ve taşma kontrolleri başarılı |
| Cihaz matrisi aracının kendi testi | 15 senaryolu plan doğrulaması başarılı; fiziksel cihaz testi değildir |
| `git diff --check` | Temiz |

Temel komutlar (SDK veya Python yolu ortamına göre değiştirilebilir):

```sh
flutter analyze
dart format --output=none --set-exit-if-changed lib test tool/tests
MIUCAM_BACKEND_TEST_PYTHON="$PWD/build/purchase_backend_venv/bin/python" \
  flutter test --no-pub test tool/tests/purchase_backend_contract_test.dart
build/purchase_backend_venv/bin/python -m pytest -q backend/tests
(cd android && ./gradlew :app:testDebugUnitTest --console=plain)
flutter build apk --debug --no-pub
node website/scripts/validate.mjs
node website/scripts/build.mjs /tmp/miucam-review-site
SITE_ROOT=/tmp/miucam-review-site node website/scripts/validate.mjs
# Site loopback HTTP sunucusunda açıkken:
SCREENSHOT_DIR=/tmp/miucam-review-browser-smoke \
  node --experimental-websocket website/scripts/browser-smoke.mjs http://127.0.0.1:8879
dart run tool/device_matrix_runner.dart --self-test
dart run tool/benchmarks/media_pipeline_benchmark.dart
```

Eklenen regresyonlar mevcut istemci/sunucu test dosyalarında, PIN testlerinde
ve [backend gövde testlerinde](../../backend/tests/test_request_body.py) yer alır.
Testler sentetik mağaza kanıtı ve loopback kullanır; gerçek ödeme yapılmadı.

## Host üzerindeki medya ölçümü

`media_pipeline_benchmark.dart` bu Linux geliştirme makinesinde Dart JIT ile
çalıştırıldı. Ses analizi 1.000 parçada ortalama **109,8 µs**, hareket analizi
1.000 karede **799,1 µs**, parçalı MJPEG ayrıştırması 30 karede **490,9 µs**
ölçtü; 30 karenin tamamı ayrıştırıldı. Bunlar telefon FPS, pil, ısı veya
uçtan uca gecikme ölçümü değildir; önce/sonra performans iddiası oluşturmaz.

## Çalıştırılmayan kontroller

- Fiziksel iki telefon arasında uzun yayın, zayıf Wi-Fi, ısınma, kamera/ses
  kesintileri ve arka plan davranışı bu turda çalıştırılmadı. Cihaza APK
  yüklenmedi, kurulu uygulama veya verileri değiştirilmedi.
- Linux ortamında iOS derlemesi, Swift/XCTest, gerçek iPhone ses kesintisi,
  Bluetooth, ekran kilidi ve bildirim dokunuşları çalıştırılmadı. iOS kodu ve
  Flutter tarafındaki yapılandırma/sahte platform kanalı testleri incelendi.
- Google Play/App Store sandbox satın alma, iade ve mağaza teslimat kabulü
  çalıştırılmadı. HTTP sözleşme testi gerçek mağaza kabulünün yerine geçmez.

Backend testleri tek bir Starlette/httpx kullanım dışı bırakma uyarısı veriyor;
testler başarılı. Bu inceleme bağımlılık sürümlerini değiştirmiyor.
