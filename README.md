# BabyCam Flutter

BabyCam Flutter, aynı Flutter/Dart kod tabanını **Server** ve **Client** rollerinde çalıştıran LAN tabanlı bebek kamera uygulamasıdır. Server cihaz kamera ve mikrofon verisini işler; Client cihaz aynı yerel ağ üzerinden canlı yayını izler ve uyarıları yerel bildirim olarak alır.

Uygulama internet yayını için tasarlanmamıştır. Varsayılan kurgu aynı Wi‑Fi/LAN içindeki cihazlar arasındadır. Telegram entegrasyonu opsiyoneldir ve yalnızca uyarı mesajlarını Bot API üzerinden göndermek için kullanılır.

---

## İçindekiler

1. [Öne çıkan özellikler](#öne-çıkan-özellikler)
2. [Güncel mimari](#güncel-mimari)
3. [Çalışma modeli](#çalışma-modeli)
4. [Protokoller ve endpointler](#protokoller-ve-endpointler)
5. [Analiz pipeline'ı](#analiz-pipelineı)
6. [Uyarı motoru ve cooldown](#uyarı-motoru-ve-cooldown)
7. [Konfigürasyon](#konfigürasyon)
8. [Bildirimler ve Telegram](#bildirimler-ve-telegram)
9. [Platform izinleri](#platform-izinleri)
10. [Kurulum ve çalıştırma](#kurulum-ve-çalıştırma)
11. [Testler](#testler)
12. [Sorun giderme](#sorun-giderme)
13. [Geliştirici notları](#geliştirici-notları)

---

## Öne çıkan özellikler

- **Server/Client rol seçimi:** İlk açılışta rol seçilir; seçim `SharedPreferences` ile saklanır.
- **LAN HTTP server:** Server modunda uygulama `0.0.0.0:8080` üzerinde dinler.
- **MJPEG video yayını:** Kamera frame'leri JPEG'e çevrilir ve `/video` endpointinden `multipart/x-mixed-replace` olarak yayınlanır.
- **WAV/PCM ses yayını:** Mikrofon PCM16 little-endian mono ses üretir; `/audio` endpointi canlı WAV akışı verir.
- **WebSocket uyarı kanalı:** `/ws/stream` üzerinden uyarı paketleri yayınlanır; Client tarafı bu paketleri yerel bildirime dönüştürür.
- **UDP discovery:** Server, `255.255.255.255:45678` adresine BabyCam discovery paketi yayınlar; Client aynı porttan server adresini otomatik bulur.
- **V2 medya analizi:** Hareket ve ses analizi artık `MediaAnalysisCoordinator` üzerinden `MotionAnalyzerV2`, `CryAudioAnalyzerV2` ve `AlertEngine` bileşenleriyle yürütülür.
- **FPS gate ve yoğunluk koruması:** Hareket analizi hedef FPS ile sınırlandırılır; analiz meşgulse frame düşürülür ve metriklere yazılır.
- **Otomatik ses kalibrasyonu:** Server başlarken ses analizörü ortam seviyesini kalibre etmeye başlar.
- **Tanılama metrikleri:** `/status` endpointi video, ses, hareket, alert ve analiz motoru tanı verilerini döndürür.
- **Cooldown'lu uyarılar:** Ağlama ve hareket uyarıları tip bazlı cooldown ile tekrar spam'ine karşı korunur.
- **Çift dil:** Uygulama metinleri Türkçe ve İngilizce için `AppStrings` sınıfında tutulur.

---

## Güncel mimari

```text
lib/
├── analysis/
│   ├── alert/                  # AlertEngine, AlertEvent, cooldown ve tip modelleri
│   ├── audio/                  # CryAudioAnalyzerV2, ring buffer, PCM reader, Goertzel band analizi
│   └── video/                  # MotionAnalyzerV2, luma frame/downsample, frame-rate gate
├── core/                       # Protokol sabitleri ve uygulama log tamponu
├── l10n/                       # TR/EN metinler
├── services/
│   ├── babycam_server.dart     # Server orkestrasyonu, HTTP/MJPEG/WAV/WebSocket
│   ├── server/                 # Medya analiz koordinasyonu, metrikler, protocol adapter
│   ├── configuration_service.dart
│   ├── discovery_service.dart
│   ├── network_address_provider.dart
│   ├── notification_service.dart
│   └── telegram_service.dart
└── ui/
    └── home_page.dart          # Rol seçimi, lifecycle, WebView, QR ve log paneli
```

### Ana sorumluluklar

- **`lib/services/babycam_server.dart`**: Kamera, mikrofon, HTTP endpointleri, WebSocket client listesi, MJPEG/WAV akışları, discovery, Telegram ve analiz pipeline'ını başlatan ana orkestratördür.
- **`lib/services/server/media_analysis_coordinator.dart`**: Kamera luma frame'lerini ve ses chunk'larını V2 analizörlere taşır, FPS gate uygular, hataları throttled log'lar ve alert stream'ini dışarı açar.
- **`lib/services/server/media_analysis_metrics.dart`**: Alınan/analyzed/dropped frame sayıları, ses pencereleri, son skorlar, hata sayıları, ortalama işlem süreleri ve son alert bilgilerini tutar.
- **`lib/services/server/alert_protocol_adapter.dart`**: Yeni `AlertEvent` modelini mevcut WebSocket alert frame formatına dönüştürür.
- **`lib/analysis/video/motion_analyzer_v2.dart`**: Luma tabanlı downsample, adaptif arka plan, aktif alan oranı, global ışık değişimi ve skor üretimi yapar.
- **`lib/analysis/audio/cry_audio_analyzer_v2.dart`**: PCM16LE ses stream'ini ring buffer üzerinden pencereler, ortam kalibrasyonu ve spektral özelliklerle ağlama olasılığı üretir.
- **`lib/analysis/alert/alert_engine.dart`**: Ses/hareket analiz sonuçlarını alert kararlarına dönüştürür ve tip bazlı cooldown uygular.

---

## Çalışma modeli

```text
+----------------------+                         +----------------------+
| Server cihaz         |                         | Client cihaz         |
|----------------------|                         |----------------------|
| Kamera + mikrofon    |                         | WebView              |
| HTTP :8080           | <---- HTTP/MJPEG ----   | / adresini açar      |
| /video MJPEG         | <---- /video ---------- | yayını izler         |
| /audio WAV           | <---- /audio ---------- | opsiyonel ses        |
| /ws/stream           | ---- alert paketleri -> | yerel bildirim       |
| UDP broadcast :45678 | ---- discovery -------> | otomatik keşif       |
+----------------------+                         +----------------------+
```

Server cihaz canlı yayın üretirken aynı anda medya analizini çalıştırır. Client cihaz server'ın HTTP sayfasını WebView içinde açar ve WebSocket üzerinden gelen alert paketlerini yerel bildirime çevirir.

---

## Protokoller ve endpointler

### Sabit portlar

| Amaç | Değer |
| --- | --- |
| HTTP server | `8080` |
| UDP discovery | `45678` |
| Discovery service adı | `babycam.v1` |

### HTTP endpointleri

| Endpoint | Açıklama |
| --- | --- |
| `/` | Basit HTML landing page; `/video` görüntüsünü ve `/audio` linkini içerir. |
| `/video` | MJPEG canlı video stream'i. |
| `/audio` | WAV header + canlı PCM16 mono ses stream'i. |
| `/status` | JSON durum ve tanılama bilgileri. Video/audio/WebSocket client sayıları, frame varlığı, analiz metrikleri ve analizör diagnostics alanlarını içerir. |
| `/ws/stream` | WebSocket upgrade endpointi. Alert frame'leri için kullanılır. |

### WebSocket paketleri

`BabyCamProtocol` hâlâ legacy binary paket tiplerini tanımlar:

| Paket tipi | Değer | İçerik |
| --- | ---: | --- |
| Metadata | `0` | Ayrılmış/gelecek kullanım |
| Audio PCM16LE | `1` | Legacy medya paketi; varsayılan olarak kapalıdır. |
| Video MJPEG | `2` | Legacy medya paketi; varsayılan olarak kapalıdır. |
| Alert text | `3` | İlk byte packet type, devamı UTF‑8 uyarı metni |

Yeni server entegrasyonunda WebSocket üzerinden varsayılan olarak alert paketleri yayınlanır. Legacy video/ses WebSocket medya paketleri `enableLegacyWebSocketMediaPackets` ile açılabilir; görüntü için ana yol HTTP/MJPEG'dir.

### UDP discovery payload

```json
{
  "service": "babycam.v1",
  "version": 2,
  "address": "192.168.1.20:8080",
  "video": "mjpeg",
  "audio": "pcm16le"
}
```

Client yalnızca `service` alanı `babycam.v1` olan paketleri kabul eder ve `address` alanını bağlantı adresi olarak kullanır.

---

## Analiz pipeline'ı

Server başlarken `BabyCamServer` V2 analiz pipeline'ını kurar:

1. `MotionAnalysisConfig`, runtime hareket eşiği ve minimum hareket süresiyle oluşturulur.
2. `AudioAnalysisConfig`, 16 kHz mono PCM ayarları, ağlama eşiği ve minimum ağlama süresiyle oluşturulur.
3. `AlertConfig`, ağlama/hareket cooldown ve eşikleriyle oluşturulur.
4. `CryAudioAnalyzerV2` başlatılır ve otomatik kalibrasyon aktifse ortam kalibrasyonuna girer.
5. `MediaAnalysisCoordinator`, `MotionAnalyzerV2`, `CryAudioAnalyzerV2`, `AlertEngine` ve `MediaAnalysisMetrics` bileşenlerini bağlar.
6. Coordinator alert stream'i server tarafından dinlenir; alert oluşunca WebSocket, yerel bildirim callback'i ve Telegram akışı tetiklenir.

### Kamera frame akışı

```text
CameraController.startImageStream
  ↓
BabyCamServer._handleCameraFrame
  ├─ CameraImageJpegEncoder.encode(frame) → /video MJPEG
  └─ frame Y plane → LumaFrame
       ↓
     MediaAnalysisCoordinator.onCameraFrame
       ├─ FrameRateGate hedef FPS kontrolü
       ├─ meşgulse drop metriği
       ├─ MotionAnalyzerV2.analyze
       ├─ MediaAnalysisMetrics.recordMotion
       └─ AlertEngine.onMotionResult
```

`MotionAnalyzerV2` downsample edilmiş luma verisiyle çalışır. Varsayılan yapı 80×60 çözünürlükte, 3 FPS hedef analiz hızıyla arka plan modeli, piksel farkı, aktif alan oranı, global ışık değişimi ve smoothing kullanır.

### Mikrofon chunk akışı

```text
AudioRecorder.startStream(PCM16, 16 kHz, mono)
  ↓
BabyCamServer._startAudioAnalysis listener
  ├─ AudioChunk oluşturulur
  ├─ MediaAnalysisCoordinator.onAudioChunk
  │   ├─ CryAudioAnalyzerV2.addChunk
  │   ├─ MediaAnalysisMetrics.recordAudio
  │   └─ AlertEngine.onAudioResult
  └─ /audio WAV client'larına PCM chunk yazılır
```

`CryAudioAnalyzerV2` 1000 ms pencere ve 250 ms hop ile çalışır. Enerji, ağlama bandı, zero-cross rate, spectral centroid, spectral flux, ortam dBFS ve kalibrasyon durumunu kullanarak ağlama skorunu üretir.

### `/status` tanılama alanları

`/status` endpointi temel bağlantı bilgilerine ek olarak şu başlıkları döndürür:

- `analysis.motion`: hedef FPS, alınan/analyzed/skipped/dropped frame sayıları, hata sayısı, son hareket skoru ve işlem süresi.
- `analysis.audio`: alınan chunk sayısı, analiz edilen pencere sayısı, son ağlama skoru, son dBFS, ambient dBFS, kalibrasyon durumu ve işlem süresi.
- `analysis.alerts`: üretilen alert sayısı, son alert tipi ve zamanı.
- `motionAnalyzer`, `audioAnalyzer`, `alertEngine`: ilgili bileşenlerin diagnostics çıktıları.

---

## Uyarı motoru ve cooldown

`AlertEngine`, analiz sonuçlarını tek noktada değerlendirir:

- **Ağlama uyarısı:** `CryAudioAnalyzerV2` skoru `cryAlertThreshold` değerini geçip minimum süre koşulunu sağladığında üretilir.
- **Hareket uyarısı:** `MotionAnalyzerV2` sonucu `motionAlertThreshold` değerini geçip minimum süre koşulunu sağladığında üretilir.
- **Cooldown:** Ağlama ve hareket için ayrı cooldown alanları vardır; server entegrasyonunda ikisi de `ConfigurationService.notifyCooldownMs` değerinden beslenir.
- **Opsiyonel uyarılar:** `AlertConfig` loud sound ve global light change için alanlar içerir; varsayılan entegrasyonda bunlar bilgi/alert olarak kapalıdır.

Alert oluştuğunda sırasıyla log'a yazılır, server cihazda yerel bildirim callback'i tetiklenir, WebSocket alert frame yayınlanır ve Telegram yapılandırıldıysa mesaj gönderilir.

---

## Konfigürasyon

`ConfigurationService`, runtime değerleri `SharedPreferences` içinde saklar. Mevcut UI ayrıntılı ayar ekranı sunmasa da servis katmanı bu değerleri okumaya/yazmaya hazırdır.

| Ayar | Varsayılan | Kullanım |
| --- | ---: | --- |
| `motion_threshold` | `0.22` | Server entegrasyonunda `MotionAnalysisConfig.motionOnThreshold` ve `AlertConfig.motionAlertThreshold` değerlerini besler. |
| `motion_min_duration_ms` | `2000` | Minimum hareket süresi. |
| `cry_score_threshold` | `0.65` | `AudioAnalysisConfig.cryOnThreshold` ve `AlertConfig.cryAlertThreshold` değerlerini besler. |
| `cry_min_duration_ms` | `1500` | Minimum ağlama süresi. |
| `notify_cooldown_ms` | `60000` | Ağlama ve hareket alert cooldown süresi. |
| `motion_window_ms` | `3000` | Eski/uyumluluk ayarı; V2 pipeline ana kararını analizör + alert engine üzerinden verir. |
| `cry_window_ms` | `5000` | Eski/uyumluluk ayarı; V2 pipeline ana kararını analizör + alert engine üzerinden verir. |

### Telegram build-time konfigürasyonu

Telegram token ve chat id uygulama derlenirken Dart define ile verilebilir:

```bash
flutter run \
  --dart-define=TELEGRAM_BOT_TOKEN=123456:ABCDEF \
  --dart-define=TELEGRAM_CHAT_ID=123456789
```

APK build örneği:

```bash
flutter build apk \
  --dart-define=TELEGRAM_BOT_TOKEN=123456:ABCDEF \
  --dart-define=TELEGRAM_CHAT_ID=123456789
```

Build-time değerler boş değilse `SharedPreferences` değerlerinin önüne geçer.

---

## Bildirimler ve Telegram

Server tarafında alert oluştuğunda:

1. `AlertEngine` cooldown kararını verir.
2. `BabyCamServer` alert mesajını log'a yazar.
3. Server cihaz için yerel bildirim callback'i çağrılır.
4. `AlertProtocolAdapter.toLegacyAlertPacket()` ile WebSocket alert frame yayınlanır.
5. Telegram token/chat id varsa Bot API'ye mesaj gönderilir.

Client tarafında WebSocket alert frame alınırsa:

1. Paket tipinin `packetAlertText` olduğu doğrulanır.
2. Payload UTF‑8 metne çevrilir.
3. Client cihazda yerel bildirim gösterilir.
4. Mesaj log'a eklenir.

---

## Platform izinleri

### Android

`android/app/src/main/AndroidManifest.xml` içinde şu izinler bulunur:

- `CAMERA`
- `RECORD_AUDIO`
- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE`
- `WAKE_LOCK`
- `POST_NOTIFICATIONS`

LAN içi `http://ip:8080` kullanımı için cleartext traffic açıktır.

### iOS

`ios/Runner/Info.plist` içinde kamera, mikrofon, yerel ağ ve Bonjour açıklamaları bulunur. iOS tarafında yerel ağ ve kamera/mikrofon izinleri sistem tarafından kullanıcıdan istenir.

---

## Kurulum ve çalıştırma

### Gereksinimler

- Flutter SDK (`>=3.4.0` ile uyumlu Dart SDK)
- Android Studio/Android SDK veya Xcode
- Aynı LAN/Wi‑Fi üzerinde en az bir server ve bir client cihaz

### Bağımlılıkları yükleme

```bash
flutter pub get
```

### Android çalıştırma

```bash
flutter run -d <android-device-id>
```

### iOS çalıştırma

```bash
flutter run -d <ios-device-id>
```

> iOS build için macOS ve Xcode gerekir.

### Tipik kullanım

1. Bir cihazda uygulamayı açın ve **Server** seçin.
2. Kamera/mikrofon/bildirim izinlerini verin.
3. Ekranda görünen URL'yi veya QR kodu not edin.
4. İkinci cihazda uygulamayı açın ve **Client** seçin.
5. Client otomatik discovery ile adresi bulamazsa `IP:8080` formatında elle girin.
6. Yayını WebView içinde izleyin ve uyarıları yerel bildirim olarak alın.

---

## Testler

Test kapsamı V2 analiz bileşenlerini ve server metriklerini içerir:

- `test/analysis/audio/*`: PCM reader, ring buffer, Goertzel band analizi ve `CryAudioAnalyzerV2` davranışları.
- `test/analysis/video/*`: Luma downsample, frame-rate gate ve `MotionAnalyzerV2` davranışları.
- `test/analysis/alert/*`: `AlertEngine` ve cooldown policy davranışları.
- `test/services_media_analysis_metrics_test.dart`: Server analiz metriklerinin JSON/record/reset davranışları.
- `test/audio_analyzer_test.dart`: Eski servis analizörünün regresyon testleri.

Çalıştırmak için:

```bash
flutter test
```

Statik analiz için:

```bash
flutter analyze
```

---

## Sorun giderme

### Client server'ı otomatik bulamıyor

- İki cihazın aynı Wi‑Fi/LAN üzerinde olduğundan emin olun.
- Bazı modemler UDP broadcast veya client isolation nedeniyle discovery paketlerini engelleyebilir.
- Client adres alanına server ekranındaki `IP:8080` değerini elle girin.

### WebView yayın açmıyor

- Server cihazda URL'nin göründüğünden emin olun.
- Client cihaz tarayıcısında `http://IP:8080/` adresini elle deneyin.
- VPN, captive portal veya firewall olmadığını kontrol edin.
- Android için cleartext traffic açıktır; iOS tarafında yerel ağ izni verilmelidir.

### Kamera açılmıyor

- Kamera izninin verildiğini kontrol edin.
- Emülatörlerde kamera stream desteği sınırlı olabilir; fiziksel cihazla test edin.
- Başka bir uygulama kamerayı kullanıyorsa kapatın.

### Mikrofon veya ses analizi çalışmıyor

- Mikrofon izninin verildiğini kontrol edin.
- Server loglarında “mikrofon izni yok” benzeri mesaj olup olmadığına bakın.
- `/status` çıktısındaki `analysis.audio` ve `audioAnalyzer` alanlarını kontrol edin.
- İlk çalıştırmada otomatik kalibrasyon nedeniyle skorların oturması için kısa süre bekleyin.

### Hareket uyarısı beklenenden farklı çalışıyor

- `/status` çıktısındaki `analysis.motion` alanında skipped/dropped frame sayılarını kontrol edin.
- Ani ışık değişimleri global light change olarak sınıflanabilir ve hareket skorunu etkileyebilir.
- Kamera açısı, düşük ışık ve otomatik pozlama hareket skorlarını değiştirebilir.

### Telegram mesajı gitmiyor

- `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID` değerlerini doğru verdiğinizden emin olun.
- Botun ilgili chat'e mesaj atma yetkisi olmalıdır.
- Server loglarında HTTP hata kodu, bağlantı hatası veya timeout mesajı olup olmadığını kontrol edin.

---

## Geliştirici notları

### Eski Kotlin uygulamasından port

`docs/kotlin_to_flutter_porting_matrix.md`, eski Kotlin/Android sorumluluklarının Flutter/Dart karşılıklarını listeler. Yeni geliştirme yaparken bu matrisi kontrol etmek, eski davranışların sessizce düşmesini engeller.

### Legacy servisler

`lib/services/audio_analyzer.dart` ve `lib/services/motion_analyzer.dart` geçmiş servis katmanlarını ve JPEG encode yardımcılarını içerir. Güncel server alert kararı V2 analiz pipeline'ından gelir; `CameraImageJpegEncoder` ise MJPEG yayın için kullanılmaya devam eder.

### Kaynak yönetimi

Server/client geçişlerinde şu kaynakların kapatılmasına özellikle dikkat edilir:

- WebSocket sink/socket
- UDP discovery subscription/socket
- HTTP server
- CameraController
- AudioRecorder subscription
- MediaAnalysisCoordinator, AlertEngine ve analizör durumları
- Wakelock

Yeni servis eklenirse `dispose()` akışına dahil edilmelidir.

### Güvenlik notu

Uygulama LAN içi kullanım için sade HTTP ve UDP broadcast kullanır. İnternete doğrudan açmak önerilmez. Uzaktan erişim gerekiyorsa VPN veya güvenli tünel gibi ek güvenlik katmanları kullanılmalıdır.

### Bilinen sınırlamalar

- WebSocket üzerinden legacy video/audio paketleri opsiyonel olarak desteklenir; mevcut client UI görüntü için WebView'deki HTTP/MJPEG sayfasını kullanır.
- Ayar değerleri için servis katmanı hazırdır; kullanıcı arayüzünde ayrıntılı ayar ekranı yoktur.
- Kamera seçimi platformlar arası basitlik için ilk uygun kamerayı kullanır.
- Ağlama/hareket algılama heuristiktir; profesyonel veya tıbbi izleme yerine geçmez.

---

## Lisans ve yayınlama

`pubspec.yaml` içinde `publish_to: 'none'` tanımlıdır; paket pub.dev'e yayınlanmak üzere yapılandırılmamıştır. Uygulama proje içi/mobile build çıktısı olarak kullanılmak üzere hazırlanmıştır.
