# BabyCam Flutter

BabyCam, tek Flutter/Dart kod tabanından çalışan **LAN odaklı bebek kamera** uygulamasıdır. Uygulama ilk açılışta **Server** veya **Client** rolünü seçtirir; Server cihaz kamera/mikrofon yayınını ve analiz pipeline'ını çalıştırır, Client cihaz ise QR ile eşleşip aynı yerel ağ üzerinden görüntü, ses ve uyarı akışlarını tüketir.

> **Güvenlik notu:** BabyCam internet yayını için tasarlanmamıştır. Varsayılan kurgu aynı Wi‑Fi/LAN içindeki cihazlardır. Doğrudan internete açmak yerine VPN veya güvenli tünel kullanın.

---

## İçindekiler

1. [Kapsam ve özellikler](#kapsam-ve-özellikler)
2. [Mimari özet](#mimari-özet)
3. [Dizin mimarisi](#dizin-mimarisi)
4. [Uygulama açılış akışı](#uygulama-açılış-akışı)
5. [Server mimarisi](#server-mimarisi)
6. [Client mimarisi](#client-mimarisi)
7. [Eşleşme, oturum ve yetkilendirme](#eşleşme-oturum-ve-yetkilendirme)
8. [Medya akışları](#medya-akışları)
9. [Analiz pipeline'ı](#analiz-pipelineı)
10. [Uyarılar ve bildirimler](#uyarılar-ve-bildirimler)
11. [Protokoller ve endpointler](#protokoller-ve-endpointler)
12. [Konfigürasyon](#konfigürasyon)
13. [Platform izinleri](#platform-izinleri)
14. [Kurulum ve çalıştırma](#kurulum-ve-çalıştırma)
15. [Test ve kalite kontrolleri](#test-ve-kalite-kontrolleri)
16. [Sorun giderme](#sorun-giderme)
17. [Geliştirici notları](#geliştirici-notları)

---

## Kapsam ve özellikler

- **Tek kod tabanı, iki rol:** Aynı Flutter uygulaması Server veya Client olarak çalışır.
- **Kalıcı rol seçimi:** Seçilen rol `SharedPreferences` içinde saklanır; kullanıcı rolü sıfırlayabilir.
- **Feature tabanlı yapı:** Server, Client ve Role Selection ekranları ayrı feature klasörlerinde tutulur.
- **QR tabanlı eşleşme:** Server kısa ömürlü nonce içeren `babycam://pair?...` payload'ı üretir; Client bu payload ile oturum token'ı alır.
- **Token korumalı endpointler:** Medya, durum ve event akışları session token doğrulaması ister.
- **LAN HTTP server:** Server `0.0.0.0:8080` üzerinde HTTP endpointleri sunar.
- **MJPEG video:** Kamera frame'leri JPEG'e dönüştürülür ve `/video` üzerinden `multipart/x-mixed-replace` olarak yayınlanır.
- **WAV/PCM ses:** Mikrofon PCM16 mono ses üretir; `/audio` WAV header + canlı PCM chunk stream'i verir.
- **WebSocket event kanalı:** `/ws/events` ve legacy `/ws/stream` endpointleri uyarı/event iletimi için kullanılır.
- **UDP discovery desteği:** Server LAN broadcast ile kendini duyurabilir; legacy/yardımcı servis olarak korunur.
- **V2 medya analizi:** Hareket ve ağlama algılama `MediaAnalysisCoordinator`, `MotionAnalyzerV2`, `CryAudioAnalyzerV2` ve `AlertEngine` ile yürütülür.
- **Cooldown'lu uyarılar:** Ağlama ve hareket uyarıları tip bazlı cooldown ile spam'e karşı korunur.
- **Telegram opsiyonu:** Build-time veya kaydedilmiş ayarlar varsa uyarılar Telegram Bot API'ye gönderilebilir.
- **TR/EN yerelleştirme:** UI metinleri `AppStrings` üzerinden Türkçe ve İngilizce destekler.

---

## Mimari özet

```text
+----------------------+         QR / Pair Confirm          +----------------------+
| Server cihaz         | <------------------------------->  | Client cihaz         |
|----------------------|                                    |----------------------|
| Role: server         |                                    | Role: client         |
| AppBootstrap         |                                    | AppBootstrap         |
| ServerRuntime        |                                    | ClientRuntime        |
| BabyCamServer        |                                    | QRPairingClient      |
| HTTP :8080           | ---- /video MJPEG -------------->  | Watch/Viewer katmanı |
| Camera + Microphone  | ---- /audio WAV/PCM ------------>  | Audio katmanı        |
| Analysis pipeline    | ---- /ws/events alert ---------->  | Alert listener       |
| Alert + Telegram     |                                    | Local notification   |
+----------------------+                                    +----------------------+
```

Uygulama mimarisi üç ana katmana ayrılır:

1. **App katmanı:** Bootstrap, tema, lifecycle, rol çözümleme ve rol repository işlemleri.
2. **Feature katmanı:** Server, Client ve Role Selection akışlarının UI, runtime ve composition root bileşenleri.
3. **Servis/Domain katmanı:** HTTP server, protokol modelleri, analiz algoritmaları, konfigürasyon, discovery, Telegram ve platform servisleri.

---

## Dizin mimarisi

```text
lib/
├── app/                         # Bootstrap, role resolver/repository, lifecycle yardımcıları
├── analysis/
│   ├── alert/                   # AlertEngine, AlertEvent, AlertConfig, cooldown policy
│   ├── audio/                   # CryAudioAnalyzerV2, PCM reader, ring buffer, Goertzel analizleri
│   └── video/                   # MotionAnalyzerV2, luma frame/downsample, FPS gate
├── core/
│   ├── protocol/                # V2 endpoint sabitleri, PairingPayload, PairingSession, alert DTO
│   ├── theme/                   # BabyCam renkleri ve temaları
│   └── app_log.dart             # Uygulama log tamponu
├── features/
│   ├── role_selection/          # Rol seçimi ekranı ve controller
│   ├── server/                  # Server shell, runtime, pairing, media, alerts, status
│   └── client/                  # Client shell, runtime, pairing, media, alerts
├── l10n/                        # TR/EN AppStrings
├── services/                    # BabyCamServer, config, discovery, notification, Telegram, adapters
└── main.dart                    # Flutter entrypoint
```

### Önemli bileşenler

| Bileşen | Sorumluluk |
| --- | --- |
| `BabyCamApp` | MaterialApp, locale delegate'leri ve `AppBootstrap` başlangıcı. |
| `AppBootstrap` | SharedPreferences yükler, rolü çözer, doğru app shell'i ve runtime'ı oluşturur. |
| `ServerCompositionRoot` | Server tarafı dependency graph'ını kurar: token service, `BabyCamServer`, QR builder, media controller, runtime. |
| `ClientCompositionRoot` | Client tarafı pairing, stream session, alert listener, notification ve runtime bağlantılarını kurar. |
| `BabyCamServer` | HTTP endpointleri, kamera/mikrofon runtime'ı, analiz pipeline'ı, WebSocket broadcast, Telegram ve discovery orkestrasyonu. |
| `ServerRuntime` | Server ekranının durum makinesi: pairing, client paired, media starting/active/idle. |
| `ClientRuntime` | Client ekranının durum makinesi: unpaired, pairing, paired idle, watching, alert only. |
| `MediaAnalysisCoordinator` | Kamera ve ses girdilerini analizörlere dağıtır, FPS gate uygular, metrik tutar, alert stream üretir. |
| `AlertProtocolAdapter` | V2 `AlertEvent` modelini legacy binary WebSocket alert paketine dönüştürür. |

---

## Uygulama açılış akışı

```text
main()
  ↓
BabyCamApp
  ↓
AppBootstrap
  ├─ SharedPreferences.getInstance()
  ├─ SharedPreferencesRoleRepository
  ├─ RoleResolver.resolve()
  └─ role switch
      ├─ null          → RoleSelectionScreen
      ├─ AppRole.server → ServerAppShell + ServerRuntime
      └─ AppRole.client → ClientAppShell + ClientRuntime
```

- Rol yoksa kullanıcı Server/Client seçer.
- Rol seçilince repository'ye kaydedilir ve ilgili composition root runtime üretir.
- Rol sıfırlanınca aktif runtime dispose edilir ve rol seçimi ekranına dönülür.
- Server ve Client runtime'ları UI'dan bağımsız durum makineleri olarak test edilebilir.

---

## Server mimarisi

Server tarafı iki parçadan oluşur:

1. **Feature/runtime kabuğu**
   - `ServerAppShell`: Server UI için MaterialApp/tema kabuğu.
   - `ServerHomeScreen`: Pairing QR ve runtime durumunu kullanıcıya gösterir.
   - `ServerRuntime`: Pairing ve medya yaşam döngüsünü state stream ile yönetir.
   - `MediaRuntimeController`: Start/stop çağrılarını soyutlar.

2. **Servis orkestrasyonu**
   - `BabyCamServer.startPairingMode()` HTTP server'ı açar ve pairing adresini üretir.
   - `BabyCamServer.startMediaRuntime()` kamera, mikrofon, analiz pipeline'ı, discovery ve Telegram başlangıç mesajını başlatır.
   - `BabyCamServer.stopMediaRuntime()` medya kaynaklarını ve analiz pipeline'ını kapatır.
   - `BabyCamServer.dispose()` token'ları revoke eder, HTTP/WebSocket/UDP/kamera/mikrofon kaynaklarını temizler.

Server runtime fazları:

| Faz | Anlamı |
| --- | --- |
| `stopped` | Server kaynakları kapalı. |
| `pairingActive` | QR payload üretildi ve eşleşme bekleniyor. |
| `clientPaired` | Client eşleşti, medya henüz aktif olmayabilir. |
| `mediaStarting` | Kamera/mikrofon başlatılıyor. |
| `mediaActive` | En az bir aktif session için medya runtime çalışıyor. |
| `mediaIdle` | Aktif client kalmadığı için medya durduruldu. |
| `error` | UI tarafından hata göstermek için ayrılmış faz. |

---

## Client mimarisi

Client tarafı QR eşleşme, oturum saklama, izleme ve uyarı dinleme akışlarını ayırır:

- `ClientAppShell`: Client UI için MaterialApp/tema kabuğu.
- `ClientHomeScreen`: Eşleşme, izleme ve uyarı modlarını sunar.
- `QRPairingClient`: QR payload içindeki host/port/nonce ile `/pair/confirm` çağrısı yapar ve session token alır.
- `PairingSessionStore`: Session bilgisini `SharedPreferences` ile saklamak/temizlemek için kullanılır.
- `StreamSessionController`: İzleme session'ının aktif/pasif durumunu yönetir.
- `ClientAlertListener`: Alert WebSocket akışı için client tarafı giriş noktasıdır.
- `ClientNotificationService`: Client cihazda yerel bildirim altyapısını hazırlar.
- `AlertShareService`: Alert paylaşımı gibi client yardımcı davranışları için ayrılmıştır.

Client runtime fazları:

| Faz | Anlamı |
| --- | --- |
| `unpaired` | Henüz server session'ı yok. |
| `scanningQr` | QR tarama akışı için ayrılmış faz. |
| `pairing` | `/pair/confirm` isteği sürüyor. |
| `pairedIdle` | Session var; izleme veya alert-only mod başlamadı. |
| `watching` | Medya izleme modu aktif. |
| `alertOnly` | Sadece uyarı dinleme modu aktif. |
| `reconnecting`, `offline`, `error` | Dayanıklılık ve hata UI'ları için ayrılmış fazlar. |

---

## Eşleşme, oturum ve yetkilendirme

### QR payload

Server pairing başlatınca `ServerQrPayloadBuilder` kısa ömürlü bir payload üretir:

```json
{
  "schemaVersion": 1,
  "host": "192.168.1.20",
  "port": 8080,
  "deviceId": "server_local",
  "deviceName": "Bebek Odası",
  "pairingNonce": "...",
  "expiresAtMs": 1710000000000,
  "capabilities": {
    "video": "mjpeg",
    "audio": "pcm16le",
    "events": "json"
  }
}
```

Payload, `babycam://pair?payload=<base64url-json>` URI formatına çevrilir. Client bu URI'yi parse eder; schema, süre ve zorunlu alanlar geçerliyse eşleşme isteği yapar.

### Pair confirm

```text
Client QRPairingClient
  ↓ POST /pair/confirm
     { pairingNonce, clientName, deviceId }
  ↓
Server PairingTokenService
  ├─ nonce geçerli mi?
  ├─ nonce tek kullanımlık olarak tüketilir
  └─ sessionToken üretilir
```

Nonce varsayılan olarak 2 dakika geçerlidir ve tek kullanımlıktır. Session token bellekte tutulur; server dispose olduğunda tüm token'lar revoke edilir.

### Yetkilendirme

Korumalı endpointler session token ister:

- Tercih edilen yöntem: `Authorization: Bearer <sessionToken>`
- Geçiş/legacy stream yöntemi: `?token=<sessionToken>` query parametresi

---

## Medya akışları

### Video

```text
CameraController.startImageStream
  ↓
BabyCamServer._handleCameraFrame
  ├─ CameraImageJpegEncoder.encode(frame)
  ├─ _latestJpeg güncellenir
  ├─ /video MJPEG client'larına frame yazılır
  ├─ legacy WebSocket media açıksa binary video paketi yayınlanır
  └─ Y plane → LumaFrame → analiz pipeline'ı
```

Video endpointi `multipart/x-mixed-replace; boundary=frame` döndürür. Her parça `Content-Type: image/jpeg` ve `Content-Length` başlıklarıyla yazılır.

### Ses

```text
AudioRecorder.startStream(PCM16, 16 kHz, mono)
  ↓
BabyCamServer._startAudioAnalysis listener
  ├─ AudioChunk → analiz pipeline'ı
  ├─ /audio WAV client'larına PCM chunk yazılır
  ├─ legacy WebSocket media açıksa binary audio paketi yayınlanır
  └─ periyodik audio diagnostics log'u
```

Audio endpointi önce WAV header yazar, sonra canlı PCM16 little-endian mono chunk'ları stream eder.

---

## Analiz pipeline'ı

Server medya runtime başlarken V2 analiz pipeline'ı kurulur:

```text
MotionAnalysisConfig        AudioAnalysisConfig        AlertConfig
        ↓                           ↓                      ↓
MotionAnalyzerV2       CryAudioAnalyzerV2          AlertEngine
        \                     |                       /
         \                    |                      /
          +--------- MediaAnalysisCoordinator -------+
                              ↓
                    Stream<AlertEvent>
                              ↓
                       BabyCamServer
```

### Hareket analizi

- Kamera frame'lerinin Y plane verisi `LumaFrame` olarak taşınır.
- `FrameRateGate` hedef analiz FPS'ini uygular.
- Coordinator meşgulse frame düşürür ve metriklere yazar.
- `MotionAnalyzerV2` downsample edilmiş luma görüntüsüyle adaptif arka plan, aktif alan oranı, global ışık değişimi ve smoothing uygular.
- Sonuç `AlertEngine.onMotionResult` ile uyarı kararına girer.

### Ağlama/ses analizi

- Mikrofon PCM16LE stream'i `AudioChunk` olarak analizöre verilir.
- `CryAudioAnalyzerV2` ring buffer üzerinde 1000 ms pencere ve 250 ms hop mantığıyla çalışır.
- Enerji, ağlama bandı, zero-cross rate, spectral centroid, spectral flux ve ortam dBFS özellikleri kullanılır.
- Otomatik kalibrasyon açıksa başlangıçta ambient seviye öğrenilir.
- Sonuç `AlertEngine.onAudioResult` ile uyarı kararına girer.

### Metrikler ve diagnostics

`MediaAnalysisMetrics` şu bilgileri tutar:

- Alınan, analiz edilen, skipped ve dropped frame sayıları.
- Audio chunk ve analiz penceresi sayıları.
- Son hareket/ağlama skorları ve son dBFS değeri.
- Ortalama işlem süreleri ve hata sayaçları.
- Son alert tipi ve zamanı.

Bu bilgiler `/status` cevabına analizör diagnostics çıktılarıyla birlikte eklenir.

---

## Uyarılar ve bildirimler

Alert akışı:

```text
MotionAnalyzerV2 / CryAudioAnalyzerV2
  ↓
AlertEngine
  ├─ threshold kontrolü
  ├─ minimum süre kontrolü
  ├─ tip bazlı cooldown kontrolü
  └─ AlertEvent
       ↓
BabyCamServer._handleAlertEvent
  ├─ metrics.recordAlert
  ├─ server log
  ├─ server local alert callback
  ├─ WebSocket binary alert packet
  └─ TelegramService.sendMessage
```

Client tarafında WebSocket alert paketi alındığında paket tipi doğrulanır, payload UTF‑8 mesaja çevrilir ve yerel bildirim/alert geçmişi katmanlarına aktarılır.

---

## Protokoller ve endpointler

### Portlar

| Amaç | Değer |
| --- | ---: |
| HTTP server | `8080` |
| UDP discovery | `45678` |
| Discovery service adı | `babycam.v1` |

### V2 endpointleri

| Endpoint | Auth | Açıklama |
| --- | --- | --- |
| `/status/public` | Hayır | Pairing/servis canlılığı için halka açık minimal JSON. |
| `/pair/confirm` | Hayır, nonce ister | QR nonce doğrular ve session token üretir. |
| `/session/start` | Evet | Medya runtime'ı başlatır. |
| `/session/stop` | Evet | Medya runtime'ı durdurur. |
| `/video` | Evet | MJPEG canlı video stream'i. |
| `/audio` | Evet | WAV header + PCM16 canlı ses stream'i. |
| `/ws/events` | Evet | V2 event WebSocket endpointi. |
| `/status` | Evet | Server bağlantı, medya ve analiz diagnostics JSON çıktısı. |

### Legacy/uyumluluk endpointleri

| Endpoint | Açıklama |
| --- | --- |
| `/` | Basit HTML landing page; video ve audio linklerini içerir. |
| `/ws/stream` | Legacy WebSocket alert endpointi; `/ws/events` ile aynı auth kontrolünü kullanır. |

### Legacy binary WebSocket paketleri

| Paket tipi | Değer | İçerik |
| --- | ---: | --- |
| Metadata | `0` | Ayrılmış/gelecek kullanım. |
| Audio PCM16LE | `1` | Legacy medya paketi; varsayılan olarak kapalıdır. |
| Video MJPEG | `2` | Legacy medya paketi; varsayılan olarak kapalıdır. |
| Alert text | `3` | İlk byte paket tipi, devamı UTF‑8 uyarı metni. |

Legacy video/ses WebSocket medya paketleri `enableLegacyWebSocketMediaPackets` ile açılabilir. Güncel ana medya yolu HTTP/MJPEG ve HTTP/WAV stream'dir.

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

Discovery, QR pairing akışının yanında ağ içi adres bulmayı kolaylaştıran yardımcı mekanizmadır.

---

## Konfigürasyon

`ConfigurationService`, runtime ayarlarını `SharedPreferences` üzerinden okur/yazar.

| Ayar | Varsayılan | Kullanım |
| --- | ---: | --- |
| `motion_threshold` | `0.22` | `MotionAnalysisConfig.motionOnThreshold` ve `AlertConfig.motionAlertThreshold`. |
| `motion_min_duration_ms` | `2000` | Hareket alert'i için minimum süre. |
| `cry_score_threshold` | `0.65` | `AudioAnalysisConfig.cryOnThreshold` ve `AlertConfig.cryAlertThreshold`. |
| `cry_min_duration_ms` | `1500` | Ağlama alert'i için minimum süre. |
| `notify_cooldown_ms` | `60000` | Ağlama ve hareket alert cooldown süresi. |
| `motion_window_ms` | `3000` | Eski/uyumluluk ayarı. |
| `cry_window_ms` | `5000` | Eski/uyumluluk ayarı. |

### Telegram Dart define değerleri

```bash
flutter run \
  --dart-define=TELEGRAM_BOT_TOKEN=123456:ABCDEF \
  --dart-define=TELEGRAM_CHAT_ID=123456789
```

```bash
flutter build apk \
  --dart-define=TELEGRAM_BOT_TOKEN=123456:ABCDEF \
  --dart-define=TELEGRAM_CHAT_ID=123456789
```

Build-time değerler boş değilse kaydedilmiş runtime değerlerinin önüne geçer.

---

## Platform izinleri

### Android

`android/app/src/main/AndroidManifest.xml` içinde kullanılan temel izinler:

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

`ios/Runner/Info.plist` kamera, mikrofon, yerel ağ ve Bonjour açıklamalarını içerir. iOS tarafında kamera/mikrofon/yerel ağ izinleri sistem izin akışıyla kullanıcıdan istenir.

---

## Kurulum ve çalıştırma

### Gereksinimler

- Flutter SDK ve Dart SDK (`pubspec.yaml` ortamı: `>=3.4.0 <4.0.0`)
- Android Studio/Android SDK veya iOS için macOS + Xcode
- Aynı LAN/Wi‑Fi üzerinde en az bir Server ve bir Client cihaz

### Bağımlılıkları yükleme

```bash
flutter pub get
```

### Android

```bash
flutter run -d <android-device-id>
```

### iOS

```bash
flutter run -d <ios-device-id>
```

### Tipik kullanım

1. Bebek odasındaki cihazda uygulamayı açın ve **Server** rolünü seçin.
2. Kamera, mikrofon ve bildirim izinlerini verin.
3. Server ekranındaki QR kodu açık bırakın.
4. Ebeveyn cihazında uygulamayı açın ve **Client** rolünü seçin.
5. QR kodu okutun; Client `/pair/confirm` ile session token alır.
6. İzleme modunu başlatın; Client `/video`, `/audio` ve `/ws/events` akışlarını token ile tüketir.
7. Uyarılar local notification ve opsiyonel Telegram mesajı olarak iletilir.

---

## Test ve kalite kontrolleri

Ana test grupları:

- `test/app/*`: Rol izolasyonu ve bootstrap davranışları.
- `test/features/server/*`: Server runtime lifecycle ve pairing token servis davranışları.
- `test/features/client/*`: Client runtime lifecycle davranışları.
- `test/features/role_selection/*`: Rol seçim ekranı testleri.
- `test/core/*`: Pairing payload parse/serialize testleri.
- `test/analysis/audio/*`: PCM reader, ring buffer, Goertzel ve `CryAudioAnalyzerV2` testleri.
- `test/analysis/video/*`: Luma downsample, frame-rate gate ve `MotionAnalyzerV2` testleri.
- `test/analysis/alert/*`: Alert engine ve cooldown policy testleri.
- `test/services_media_analysis_metrics_test.dart`: Server analiz metriklerinin JSON/record/reset davranışları.
- `test/audio_analyzer_test.dart`: Legacy audio analyzer regresyon testleri.

Çalıştırma:

```bash
flutter test
```

Statik analiz:

```bash
flutter analyze
```

---

## Sorun giderme

### Client QR ile eşleşemiyor

- Server ve Client cihazların aynı LAN/Wi‑Fi üzerinde olduğundan emin olun.
- QR payload süresi varsayılan 2 dakikadır; süre dolduysa yeni QR üretin.
- Server IP'sinin Client tarafından erişilebilir olduğunu kontrol edin.
- Modem/client isolation özelliği LAN cihazlarının birbirini görmesini engelleyebilir.

### 401 Unauthorized alıyorum

- `/video`, `/audio`, `/status`, `/session/*` ve WebSocket event endpointleri session token ister.
- QR eşleşmesi tamamlanmadan medya endpointlerine doğrudan girmek beklenen şekilde 401 döndürür.
- Server yeniden başlatıldıysa bellek içi session token'lar silinir; yeniden eşleşin.

### Video açılmıyor

- Server'da medya runtime'ın başladığından emin olun.
- Kamera iznini kontrol edin.
- Fiziksel cihazla test edin; emülatör kamera stream desteği sınırlı olabilir.
- Client cihazdan `http://SERVER_IP:8080/status/public` adresini deneyerek server erişimini doğrulayın.

### Ses veya ağlama analizi çalışmıyor

- Mikrofon izni verildi mi kontrol edin.
- Server loglarında mikrofon izni veya recorder hatası olup olmadığına bakın.
- İlk çalıştırmada otomatik kalibrasyon nedeniyle birkaç saniye bekleyin.
- `/status` çıktısındaki `analysis.audio` ve `audioAnalyzer` diagnostics alanlarını inceleyin.

### Hareket uyarısı beklenenden farklı

- Düşük ışık, otomatik pozlama ve ani ışık değişimleri skorları etkileyebilir.
- `/status` içindeki `analysis.motion` alanında skipped/dropped frame sayılarını kontrol edin.
- Kamera açısını ve hareket eşiği konfigürasyonunu gözden geçirin.

### Telegram mesajı gitmiyor

- `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID` değerlerini doğru verdiğinizden emin olun.
- Botun ilgili chat'e mesaj atma yetkisi olmalıdır.
- Server loglarında HTTP hata kodu veya timeout var mı kontrol edin.

---

## Geliştirici notları

### Porting matrisi

`docs/kotlin_to_flutter_porting_matrix.md`, eski Kotlin/Android uygulamasındaki sorumlulukların Flutter/Dart karşılıklarını listeler. Yeni geliştirmelerde davranış parity kontrolü için bu matrisi gözden geçirin.

### Legacy servisler

`lib/services/audio_analyzer.dart` ve `lib/services/motion_analyzer.dart` geçmiş servis katmanı ve yardımcı kodları içerir. Güncel alert kararı V2 analiz pipeline'ından gelir; `CameraImageJpegEncoder` ise MJPEG yayınında aktif olarak kullanılmaya devam eder.

### Kaynak yönetimi

Yeni servis eklenirken şu kaynakların lifecycle'a dahil edildiğinden emin olun:

- HTTP server ve WebSocket bağlantıları
- UDP discovery soketleri/subscription'ları
- CameraController
- AudioRecorder stream subscription
- MediaAnalysisCoordinator, AlertEngine ve analizör state'leri
- SharedPreferences-backed runtime state
- Notification ve Telegram yardımcıları

### Sınırlar

- Algılama heuristiktir; profesyonel/tıbbi bebek izleme sistemi yerine geçmez.
- Varsayılan mimari LAN içi sade HTTP kullanır.
- Token'lar bellek içidir; server dispose/restart sonrası yeniden eşleşme gerekir.
- Ayrıntılı ayar UI'ı sınırlıdır; servis katmanı ayarları okumaya/yazmaya hazırdır.

---

## Lisans ve yayınlama

`pubspec.yaml` içinde `publish_to: 'none'` tanımlıdır. Proje pub.dev paketi olarak değil, mobil uygulama build çıktısı olarak kullanılmak üzere yapılandırılmıştır.
