# BabyCam Flutter

BabyCam Flutter, aynı Flutter/Dart kod tabanını iki farklı rolde çalıştıran yerel ağ tabanlı bir bebek kamera uygulamasıdır:

- **Server modu:** Kamerayı ve mikrofonu açar, aynı LAN üzerindeki cihazlara HTTP/MJPEG video yayını, WAV ses yayını, WebSocket uyarıları ve UDP discovery duyurusu sağlar.
- **Client modu:** LAN üzerinde BabyCam server arar, bulunan ya da elle girilen adrese bağlanır, yayını WebView içinde gösterir ve server uyarılarını yerel bildirim olarak iletir.

Uygulama internet üzerinden yayın yapmak için tasarlanmamıştır. Varsayılan mimari aynı Wi‑Fi/LAN içindeki cihazlar arasında çalışır. Telegram entegrasyonu opsiyoneldir ve sadece uyarı mesajlarını Bot API üzerinden göndermek için kullanılır.

---

## İçindekiler

1. [Öne çıkan özellikler](#öne-çıkan-özellikler)
2. [Teknoloji yığını](#teknoloji-yığını)
3. [Çalışma modeli](#çalışma-modeli)
4. [Mimari genel bakış](#mimari-genel-bakış)
5. [Protokoller ve endpointler](#protokoller-ve-endpointler)
6. [Kod organizasyonu](#kod-organizasyonu)
7. [Ana akışlar](#ana-akışlar)
8. [Ses analizi mimarisi](#ses-analizi-mimarisi)
9. [Hareket analizi mimarisi](#hareket-analizi-mimarisi)
10. [Konfigürasyon](#konfigürasyon)
11. [Bildirimler ve Telegram](#bildirimler-ve-telegram)
12. [Platform izinleri](#platform-izinleri)
13. [Kurulum ve çalıştırma](#kurulum-ve-çalıştırma)
14. [Testler](#testler)
15. [Sorun giderme](#sorun-giderme)
16. [Geliştirici notları](#geliştirici-notları)

---

## Öne çıkan özellikler

- **Server/Client rol seçimi:** İlk açılışta kullanıcı Server veya Client rolünü seçer. Seçim `SharedPreferences` ile saklanır.
- **LAN HTTP server:** Server modunda uygulama `0.0.0.0:8080` üzerinde dinler.
- **MJPEG video yayını:** Kamera frame'leri JPEG'e çevrilir ve `/video` endpointinden `multipart/x-mixed-replace` olarak yayınlanır.
- **WAV/PCM ses yayını:** Mikrofon PCM16 little-endian mono ses üretir; `/audio` endpointi WAV header ile canlı akış verir.
- **WebSocket uyarı kanalı:** `/ws/stream` üzerinden binary paketler yayınlanır. Client tarafı uyarı paketlerini yerel bildirime dönüştürür.
- **UDP discovery:** Server, `255.255.255.255:45678` adresine iki saniyede bir JSON discovery paketi yayınlar. Client aynı portu dinleyerek server adresini otomatik bulur.
- **Ağlama/inleme analizi:** RMS, dBFS, ortam gürültüsü, bant enerjileri, spectral centroid/bandwidth/entropy, zero-cross rate ve temel frekans tahmini ile skor üretir.
- **Hareket algılama:** Luma downsample, adaptif arka plan modeli, gürültü tahmini ve smoothing ile hareket skoru üretir.
- **Bildirim ve cooldown:** Uyarılar hem yerel bildirim olarak gösterilir hem de WebSocket/Telegram üzerinden iletilebilir; tekrar bildirimleri cooldown ile sınırlanır.
- **Çift dil:** Uygulama metinleri Türkçe ve İngilizce için `AppStrings` sınıfında tutulur.

---

## Teknoloji yığını

| Katman | Kullanılan teknoloji/paket | Amaç |
| --- | --- | --- |
| Uygulama çatısı | Flutter, Material 3 | Tek kod tabanlı Android/iOS arayüzü |
| Kamera | `camera` | Server modunda kamera önizleme ve frame stream |
| Mikrofon | `record` | PCM16 ses stream'i alma |
| Kalıcı ayarlar | `shared_preferences` | Rol, server adresi, eşik ve Telegram ayarlarını saklama |
| Client izleme | `webview_flutter` | Server landing page ve MJPEG yayını görüntüleme |
| WebSocket | `web_socket_channel` + Dart `HttpServer` | Uyarı/binary stream bağlantısı |
| Bildirim | `flutter_local_notifications` | Android/iOS yerel uyarı bildirimi |
| Uyku engelleme | `wakelock_plus` | Server açıkken cihazın uyumasını engelleme |
| Görüntü işleme | `image` | Kamera frame'ini JPEG'e encode etme |
| QR kod | `qr_flutter` | Server adresini QR olarak gösterme |
| Test | `flutter_test` | Ses analizörü davranış testleri |

---

## Çalışma modeli

BabyCam aynı uygulamayı iki cihazda farklı rol ile çalıştırmaya dayanır:

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

Server cihaz kamera ve mikrofonu işler. Client cihaz ise server'ın HTTP sayfasını açar ve WebSocket uyarı kanalına bağlanır. İki cihazın aynı yerel ağda olması gerekir.

---

## Mimari genel bakış

Uygulama katmanları bilinçli olarak küçük sınıflara ayrılmıştır:

```text
lib/
├── main.dart
├── core/
│   ├── app_log.dart
│   └── babycam_protocol.dart
├── l10n/
│   └── app_strings.dart
├── services/
│   ├── audio_analyzer.dart
│   ├── babycam_server.dart
│   ├── configuration_service.dart
│   ├── discovery_service.dart
│   ├── motion_analyzer.dart
│   ├── network_address_provider.dart
│   ├── notification_service.dart
│   └── telegram_service.dart
└── ui/
    └── home_page.dart
```

### Katman sorumlulukları

- **`main.dart`**: Flutter binding'i başlatır, `MaterialApp` oluşturur, tema ve localization delegate'lerini bağlar.
- **`ui/home_page.dart`**: Rol seçimi, izin isteme, server/client lifecycle, WebView, QR kod, log paneli ve kullanıcı etkileşimlerini yönetir.
- **`services/babycam_server.dart`**: Server modunun merkezidir. Kamera, mikrofon, HTTP endpointleri, WebSocket client listesi, MJPEG/WAV akışları, hareket/ses uyarıları ve Telegram gönderimi burada koordine edilir.
- **`services/audio_analyzer.dart`**: PCM16 ses parçalarını analiz eder ve ağlama/inleme skorları üretir.
- **`services/motion_analyzer.dart`**: Kamera frame'lerinden hareket skoru ve JPEG çıktısı üretir.
- **`services/discovery_service.dart`**: UDP broadcast yayınlama ve dinleme işini yapar.
- **`services/configuration_service.dart`**: Eşikler, süre pencereleri, cooldown ve Telegram ayarlarını okur/yazar.
- **`services/notification_service.dart`**: Yerel bildirimleri soyutlar.
- **`services/telegram_service.dart`**: Telegram Bot API'ye uyarı mesajı gönderir.
- **`core/babycam_protocol.dart`**: Portlar, packet type değerleri, discovery JSON formatı ve alert frame formatı için tek kaynak görevi görür.
- **`core/app_log.dart`**: UI'da gösterilen zaman damgalı log tamponunu tutar.
- **`l10n/app_strings.dart`**: Türkçe/İngilizce metinleri ve bildirim/uyarı açıklamalarını sağlar.

---

## Protokoller ve endpointler

### Sabit portlar

| Amaç | Değer |
| --- | --- |
| HTTP server | `8080` |
| UDP discovery | `45678` |
| Discovery service adı | `babycam.v1` |

### HTTP endpointleri

| Endpoint | Üreten rol | Açıklama |
| --- | --- | --- |
| `/` | Server | Basit HTML landing page. `/video` görüntüsünü ve `/audio` linkini içerir. |
| `/video` | Server | MJPEG canlı video stream'i. Content-Type: `multipart/x-mixed-replace; boundary=frame`. |
| `/audio` | Server | WAV header + canlı PCM16 mono ses stream'i. |
| `/status` | Server | JSON durum bilgisi: video/audio/WebSocket client sayıları ve frame durumu. |
| `/ws/stream` | Server | WebSocket upgrade endpointi. Binary paketler ve alert mesajları için kullanılır. |

### WebSocket binary paketleri

`BabyCamProtocol` aşağıdaki paket tiplerini tanımlar:

| Paket tipi | Değer | İçerik |
| --- | ---: | --- |
| Metadata | `0` | Ayrılmış/gelecek kullanım |
| Audio PCM16LE | `1` | İlk byte packet type, devamı PCM16 little-endian ses verisi |
| Video MJPEG | `2` | İlk byte packet type, devamı JPEG frame |
| Alert text | `3` | İlk byte packet type, devamı UTF‑8 uyarı metni |

Client arayüzü şu anda özellikle `packetAlertText` paketlerini işler. Mesaj UTF‑8 decode edilir, yerel bildirim gösterilir ve log'a yazılır.

### UDP discovery payload

Server discovery broadcast'ünde JSON taşır:

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

## Kod organizasyonu

### `lib/main.dart`

- `WidgetsFlutterBinding.ensureInitialized()` çağrılır.
- `BabyCamApp` `MaterialApp` döndürür.
- `ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true)` ile Material 3 tema kullanılır.
- Desteklenen locale listesi `AppStrings.supportedLocales` üzerinden gelir.
- Ana ekran `HomePage`'dir.

### `lib/ui/home_page.dart`

`HomePage`, uygulama lifecycle'ının UI tarafındaki koordinatörüdür.

Başlıca durum alanları:

- `_mode`: `server`, `client` veya henüz seçilmemiş durum.
- `_prefs`: `SharedPreferences` instance'ı.
- `_config`: Runtime konfigürasyon servisi.
- `_server`: Server modunda çalışan `BabyCamServer` instance'ı.
- `_discoverySubscription`: Client modunda UDP discovery dinleme aboneliği.
- `_alertChannel`: Client modundaki WebSocket bağlantısı.
- `_webViewController`: Client WebView kontrolcüsü.
- `_logs`: UI log satırları.
- `_serverUrl` ve `_status`: UI'da gösterilen bağlantı/durum bilgileri.

Önemli akışlar:

1. `initState()` log stream'ine abone olur ve `_bootstrap()` çağırır.
2. `_bootstrap()` kayıtlı modu okur ve varsa otomatik olarak aynı moda geçer.
3. `_selectMode()` rolü kaydeder, eski bağlantıları kapatır, ilgili start metodunu çağırır.
4. `_startServerMode()` kamera/mikrofon/bildirim izinlerini ister, wakelock açar ve `BabyCamServer.start()` çalıştırır.
5. `_startClientMode()` varsa server'ı kapatır, wakelock'u devre dışı bırakır, discovery dinler ve kayıtlı server adresine bağlanır.
6. `_connectClient()` adresi normalize eder, HTTP URL'ini WebView'de açar ve `ws://.../ws/stream` WebSocket kanalına bağlanır.
7. `_handleAlertPacket()` alert paketini parse eder, bildirim gösterir ve log'a ekler.
8. `_resetMode()` kayıtlı rolü siler, server/socket/subscription kaynaklarını kapatır ve başlangıç ekranına döner.

### `lib/services/babycam_server.dart`

Server tarafının ana orkestratörüdür. `start()` metodu şu sırayla çalışır:

1. Kameraları listeler; kamera yoksa hata üretir.
2. İlk kamerayı `ResolutionPreset.medium` ile açar.
3. Kamera image stream'ini `_handleCameraFrame()` callback'ine bağlar.
4. Mikrofon ses analizini `_startAudioAnalysis()` ile başlatır.
5. `HttpServer.bind(InternetAddress.anyIPv4, 8080, shared: true)` ile server açar.
6. Yerel IPv4 adresini bulur ve UDP discovery yayını başlatır.
7. Server başlangıcını log'a ve Telegram'a bildirir.

Server'ın tuttuğu önemli koleksiyonlar:

- `_webSockets`: Bağlı WebSocket client'ları.
- `_mjpegClients`: `/video` stream'ine bağlı HTTP response nesneleri.
- `_audioClients`: `/audio` stream'ine bağlı HTTP response nesneleri.

Uyarı üretimi iki kanaldan gelir:

- `_handleMotionScore()` hareket skorunu eşik/süre penceresine göre değerlendirir.
- `_handleAudioResult()` ağlama/inleme skorunu eşik/süre penceresine göre değerlendirir.

Uyarı kesinleştiğinde `_notifyOnce()` çalışır:

- Cooldown kontrolü yapar.
- Log'a mesaj yazar.
- Yerel bildirim callback'ini çağırır.
- WebSocket üzerinden alert frame yayınlar.
- Telegram mesajı göndermeyi dener.

`dispose()` server kaynaklarını temizler: ses aboneliği, recorder, kamera controller, HTTP server, WebSocket'ler, client listeleri ve discovery soketleri kapatılır.

### `lib/services/audio_analyzer.dart`

PCM16 little-endian byte akışını analiz eder. `analyzePcm16()` şu adımları izler:

1. Byte verisi `double` örneklere normalize edilir (`-1.0` ile `1.0` arası).
2. RMS ve dBFS hesaplanır.
3. Ortam RMS seviyesi adaptif takip edilir.
4. Zero-cross rate hesaplanır.
5. Goertzel tabanlı bant enerjileri çıkarılır:
   - düşük bant: 180–420 Hz
   - ağlama bandı: 420–1600 Hz
   - sert/parlak bant: 1600–3600 Hz
6. Spektral şekil metrikleri çıkarılır:
   - spectral centroid
   - bandwidth
   - entropy
7. Temel frekans tahmini yapılır.
8. Ağlama ve inleme skorları hesaplanır.
9. Leaky integrator ile kısa süreli dalgalanmalar yumuşatılır.
10. Cooldown ve süreklilik koşulları sağlanırsa alert sonucu üretilir.

Bu analiz tıbbi teşhis amacı taşımaz; yalnızca pratik bir bebek monitörü uyarı heuristiğidir.

### `lib/services/motion_analyzer.dart`

Kamera frame analizi üç parçaya ayrılır:

- `LumaDownsampler`: Y plane üzerinden belirli adımlarla örnek alır. Varsayılan `sampleStep = 4` olduğu için her piksel değil seyreltilmiş luma örnekleri değerlendirilir.
- `MotionScoreCalculator`: Ham fark skorundan adaptif gürültü tahminini çıkarır, normalize eder ve smoothing uygular.
- `CameraImageJpegEncoder`: Kamera frame'ini JPEG'e dönüştürür. Üç plane varsa YUV420 renk dönüşümü yapar; tek plane varsa luma/grayscale JPEG üretir.

`MotionAnalyzer.analyze()` hem hareket skoru hem de aynı frame'in JPEG karşılığını döndürür. Böylece server tek kamera callback'inden hem yayın hem analiz çıktısı elde eder.

### `lib/services/discovery_service.dart`

- `advertise(address)`: UDP socket açar, broadcast'i etkinleştirir ve discovery payload'ını iki saniyede bir `255.255.255.255:45678` adresine gönderir.
- `listen()`: `0.0.0.0:45678` üzerinde UDP paketlerini dinler, geçerli BabyCam payload'larını parse eder ve address stream'i üretir.
- `dispose()`: Timer ve soketleri kapatır.

### `lib/services/configuration_service.dart`

Konfigürasyon iki kaynaktan gelir:

1. Telegram için build-time environment değişkenleri:
   - `TELEGRAM_BOT_TOKEN`
   - `TELEGRAM_CHAT_ID`
2. Runtime `SharedPreferences` değerleri.

Varsayılan eşikler:

| Ayar | Varsayılan | Açıklama |
| --- | ---: | --- |
| `motion_threshold` | `0.22` | Hareket skor eşiği |
| `motion_window_ms` | `3000` | Hareketin kayboldu sayılması için pencere |
| `motion_min_duration_ms` | `2000` | Uyarı için minimum hareket süresi |
| `cry_score_threshold` | `0.65` | Ağlama/inleme skor eşiği |
| `cry_min_duration_ms` | `1500` | Uyarı için minimum ses süresi |
| `cry_window_ms` | `5000` | Ses skorunun kayboldu sayılması için pencere |
| `notify_cooldown_ms` | `60000` | Bildirimler arası minimum süre |

### `lib/services/notification_service.dart`

`flutter_local_notifications` üstünde ince bir katmandır. `initialize()` platform ayarlarını kurar. `showAlert()` sabit bildirim ID'si ve yüksek öncelikli Android channel ayarları ile uyarı gösterir.

### `lib/services/telegram_service.dart`

Telegram Bot API'ye JSON `POST` isteği gönderir:

```text
POST https://api.telegram.org/bot<token>/sendMessage
Body: { "chat_id": "...", "text": "..." }
```

Token veya chat id boşsa mesaj gönderilmez ve log'a açıklama yazılır. Ağ hatası, timeout ve HTTP hata kodları log'lanır.

### `lib/core/app_log.dart`

UI logları için küçük bir ring buffer mantığı sağlar:

- Varsayılan kapasite: 160 satır.
- Her mesaj `HH:mm:ss  mesaj` formatında saklanır.
- Stream broadcast olduğu için UI canlı güncellenir.

### `lib/l10n/app_strings.dart`

Flutter'ın `LocalizationsDelegate` yapısıyla çalışır. Desteklenen diller:

- `en`
- `tr`

Locale Türkçe değilse İngilizce fallback kullanılır.

---

## Ana akışlar

### Server modu başlatma

```text
Kullanıcı Server seçer
  ↓
Kamera, mikrofon, bildirim izinleri istenir
  ↓
Wakelock açılır
  ↓
BabyCamServer oluşturulur
  ↓
Kamera stream + mikrofon stream başlar
  ↓
HTTP server :8080 üzerinde dinler
  ↓
Yerel IP bulunur
  ↓
UDP discovery yayını başlar
  ↓
UI'da URL ve QR kod gösterilir
```

### Client modu başlatma

```text
Kullanıcı Client seçer
  ↓
Varsa server kaynakları kapatılır
  ↓
Wakelock kapatılır
  ↓
Bildirim izni istenir
  ↓
UDP discovery dinlenir
  ↓
Server adresi bulunursa adres alanına yazılır
  ↓
WebView http://ip:8080/ adresini açar
  ↓
WebSocket ws://ip:8080/ws/stream kanalına bağlanır
  ↓
Alert paketleri yerel bildirime dönüştürülür
```

### Kamera frame akışı

```text
CameraController.startImageStream
  ↓
_handleCameraFrame(CameraImage)
  ↓
MotionAnalyzer.analyze(frame)
  ├─ luma downsample + hareket skoru
  └─ frame -> JPEG
  ↓
WebSocket video paketi yayınlanır
  ↓
/video MJPEG client'larına frame yazılır
  ↓
Hareket skoru eşik/süre/cooldown mantığına girer
```

### Mikrofon chunk akışı

```text
AudioRecorder.startStream(PCM16, 16 kHz, mono)
  ↓
AudioAnalyzer.analyzePcm16(chunk)
  ↓
WebSocket audio paketi yayınlanır
  ↓
/audio WAV client'larına PCM chunk yazılır
  ↓
Ses skoru eşik/süre/cooldown mantığına girer
```

---

## Ses analizi mimarisi

Ses analizörü, tek bir sinyale bakarak karar vermek yerine birkaç özelliği birleştirir:

- **RMS/dBFS:** Sesin genel şiddetini ölçer.
- **Ortam RMS takibi:** Ortam gürültüsünü adaptif izler. Sessizleşmede daha hızlı, yükselmede daha yavaş uyum sağlar.
- **Above ambient skoru:** Anlık sesin ortama göre ne kadar yükseldiğini ölçer.
- **Zero-cross rate:** Sinyalin işaret değiştirme oranı. Daha gürültülü/parlak seslerde artabilir.
- **Bant enerjisi:** Düşük frekans, ağlama bandı ve sert/parlak bantlar ayrı ölçülür.
- **Spektral centroid:** Sesin parlaklık merkezini verir.
- **Spektral bandwidth:** Enerjinin frekans ekseninde ne kadar yayıldığını gösterir.
- **Spektral entropy:** Tonal/sesli yapı ile gürültülü yapı arasında ayrım yapmaya yardımcı olur.
- **Temel frekans:** Bebek vokalizasyonuna benzeyen pitch aralıkları skora katkı sağlar.
- **Leaky integrator:** Tek seferlik anlık patlamaları değil, süreklilik gösteren sesleri öne çıkarır.

Ağlama ve inleme skorları ayrı hesaplanır. Uyarı mesajında baskın ses tipi ve analiz özeti yer alır.

---

## Hareket analizi mimarisi

Hareket analizörü, ham frame farklarını doğrudan uyarıya çevirmek yerine adaptif bir model kullanır:

1. İlk frame arka plan olarak alınır.
2. Sonraki frame'lerde luma örneklerinin arka planla mutlak farkı hesaplanır.
3. Arka plan her frame'de yavaşça güncellenir (`%96` eski, `%4` yeni).
4. Ham fark normalize edilir.
5. `MotionScoreCalculator` ortam/kompresyon/kamera gürültüsüne benzer küçük değişimleri adaptif olarak tahmin eder.
6. Skor smoothing ile yumuşatılır.
7. Server tarafında skor eşik üstünde belirli süre kalırsa uyarı oluşturulur.

---

## Konfigürasyon

### Runtime konfigürasyon

`ConfigurationService`, değerleri `SharedPreferences` içinde saklar. Kod tarafında setter metodları hazırdır; mevcut UI bu ayarlar için ayrı bir ayar ekranı sunmaz. İleride ayar ekranı eklenirse aynı servis kullanılabilir.

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

Uyarı oluştuğunda server şu sırayı izler:

1. Cooldown süresi kontrol edilir.
2. UI log'a mesaj eklenir.
3. Server cihazda yerel bildirim gösterilir.
4. WebSocket client'larına alert text frame gönderilir.
5. Telegram konfigürasyonu varsa Bot API'ye mesaj gönderilir.

Client cihazda WebSocket alert frame alınırsa:

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

Ayrıca cleartext HTTP kullanımı açıktır:

```xml
<application android:usesCleartextTraffic="true" ...>
```

Bu gereklidir çünkü LAN içi yayın varsayılan olarak `http://ip:8080` ile yapılır.

### iOS

`ios/Runner/Info.plist` içinde şu açıklamalar bulunur:

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices`

iOS tarafında yerel ağ izni ve kamera/mikrofon izinleri kullanıcıdan sistem tarafından istenir.

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

### Android APK build

```bash
flutter build apk
```

### iOS build

```bash
flutter build ios
```

### Tipik kullanım

1. Bir cihazda uygulamayı açın ve **Server** seçin.
2. Kamera/mikrofon/bildirim izinlerini verin.
3. Ekranda görünen URL'yi veya QR kodu not edin.
4. İkinci cihazda uygulamayı açın ve **Client** seçin.
5. Client otomatik discovery ile adresi bulamazsa `IP:8080` formatında elle girin.
6. Yayını WebView içinde izleyin.

---

## Testler

Mevcut test kapsamı `test/audio_analyzer_test.dart` dosyasında ses analizörüne odaklanır:

- Orta-yüksek bantta sürdürülen tonun ağlama skorunu artırması.
- Düşük frekanslı sürdürülen tonun inleme skorunu artırması.
- Broadband noise örneğinde güvenilir infant pitch bulunmaması.

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
- Android'de multicast/broadcast davranışı cihaz ve ağ üreticisine göre değişebilir.

### WebView yayın açmıyor

- Server cihazda URL'nin göründüğünden emin olun.
- Client cihaz tarayıcısında `http://IP:8080/` adresini elle deneyin.
- Server ve client arasında VPN, captive portal veya firewall olmadığını kontrol edin.
- Android için cleartext traffic açıktır; iOS tarafında yerel ağ izni verilmelidir.

### Kamera açılmıyor

- Kamera izninin verildiğini kontrol edin.
- Emülatörlerde kamera stream desteği sınırlı olabilir; fiziksel cihazla test edin.
- Başka bir uygulama kamerayı kullanıyorsa kapatın.

### Mikrofon veya ses analizi çalışmıyor

- Mikrofon izninin verildiğini kontrol edin.
- Server loglarında “mikrofon izni yok” benzeri mesaj olup olmadığına bakın.
- Emülatörlerde mikrofon stream davranışı fiziksel cihazdan farklı olabilir.

### Telegram mesajı gitmiyor

- `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID` değerlerini doğru verdiğinizden emin olun.
- Botun ilgili chat'e mesaj atma yetkisi olmalıdır.
- Server loglarında HTTP hata kodu, bağlantı hatası veya timeout mesajı olup olmadığını kontrol edin.

### Çok sık veya çok az uyarı geliyor

- Varsayılan eşikler genel kullanım için heuristiktir.
- Ortam sesi, kamera açısı, ışık değişimleri ve cihaz mikrofon kalitesi sonucu etkileyebilir.
- İleride ayar ekranı eklenirse `ConfigurationService` eşikleri kullanıcı tarafından değiştirilebilir.

---

## Geliştirici notları

### Eski Kotlin uygulamasından port

`docs/kotlin_to_flutter_porting_matrix.md`, eski Kotlin/Android sorumluluklarının Flutter/Dart karşılıklarını listeler. Yeni geliştirme yaparken bu matrisi kontrol etmek, eski davranışların sessizce düşmesini engeller.

### Kaynak yönetimi

Server/client geçişlerinde şu kaynakların kapatılmasına özellikle dikkat edilir:

- WebSocket sink
- UDP discovery subscription/socket
- HTTP server
- CameraController
- AudioRecorder subscription
- Wakelock

Yeni servis eklenirse `dispose()` akışına dahil edilmelidir.

### Güvenlik notu

Uygulama LAN içi kullanım için sade HTTP ve UDP broadcast kullanır. İnternete doğrudan açmak önerilmez. Uzaktan erişim gerekiyorsa VPN veya güvenli tünel gibi ek güvenlik katmanları kullanılmalıdır.

### Bilinen sınırlamalar

- WebSocket üzerinden video/audio paketleri yayınlansa da mevcut client UI görüntü için WebView'deki HTTP/MJPEG sayfasını kullanır.
- Ayar değerleri için servis katmanı hazırdır; kullanıcı arayüzünde ayrıntılı ayar ekranı yoktur.
- Kamera seçimi platformlar arası basitlik için ilk uygun kamerayı kullanır.
- Ağlama/inleme algılama heuristiktir; profesyonel/tıbbi izleme yerine geçmez.

---

## Lisans ve yayınlama

`pubspec.yaml` içinde `publish_to: 'none'` tanımlıdır; paket pub.dev'e yayınlanmak üzere yapılandırılmamıştır. Uygulama proje içi/mobile build çıktısı olarak kullanılmak üzere hazırlanmıştır.
