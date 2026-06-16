# BabyCam Mimari Dokümantasyonu

Bu doküman BabyCam uygulamasının teknik mimarisini uçtan uca anlatır. Amaç, projeye yeni giren bir geliştiricinin uygulamanın rol modelini, güvenlik yaklaşımını, runtime yaşam döngüsünü, medya/analiz boru hatlarını ve dizin yapısını adım adım anlayabilmesidir.

---

## 1. Mimari prensipler

BabyCam mimarisi şu prensiplerle tasarlanır:

1. **Strict role isolation:** Uygulama açılışında yalnızca seçilen rolün graph'ı kurulur.
2. **Local-first çalışma:** Video, ses, status ve event akışları aynı Wi‑Fi/LAN içinde kalır.
3. **QR-first trust:** İlk güven kurulumu QR payload üzerinden yapılır.
4. **Token tabanlı devamlılık:** Eşleşme sonrası client, süreli trusted token ile çalışır.
5. **Kaynakların geç açılması:** Kamera, mikrofon, encoder ve analyzer sadece ihtiyaç olduğunda açılır.
6. **Cloud bağımsızlığı:** Backend, relay, OAuth, STUN/TURN veya uzak erişim varsayılmaz.
7. **Kullanıcı odaklı akış:** UI, teknik endpointlerden çok “eşleştir, izle, durdur” aksiyonlarını öne çıkarır.

---

## 2. Üst seviye sistem görünümü

```text
Flutter App
  ↓
AppBootstrap
  ↓
RoleResolver + RoleRepository
  ↓
┌───────────────────────────┬───────────────────────────┐
│ Server role               │ Client role               │
│ ServerCompositionRoot     │ ClientCompositionRoot     │
│ ServerRuntime             │ ClientRuntime             │
│ Pairing + Media + Alerts  │ Pairing + Watch + Alerts  │
└───────────────────────────┴───────────────────────────┘
```

Uygulama tek Flutter projesidir; ancak iki ürün davranışı vardır:

- **Server:** Bebek odasındaki cihazdır.
- **Client:** Ebeveynin kullandığı cihazdır.

Bu iki rol aynı anda aktif olmaz. UI içinde gizlenmiş pasif servisler yerine runtime seviyesinde ayrılmış composition root kullanılır.

---

## 3. Dizin yapısı

```text
lib/
├── main.dart
├── app/
│   ├── app_bootstrap.dart
│   ├── app_role.dart
│   ├── babycam_app.dart
│   ├── role_repository.dart
│   ├── role_resolver.dart
│   └── app_lifecycle_observer.dart
├── core/
│   ├── protocol/
│   ├── security/
│   ├── theme/
│   ├── app_log.dart
│   └── babycam_protocol.dart
├── analysis/
│   ├── audio/
│   ├── video/
│   └── alert/
├── features/
│   ├── role_selection/
│   ├── server/
│   ├── client/
│   └── shared/
├── services/
└── l10n/
```

### 3.1 `app/`

Uygulama başlangıcı, rol çözümleme ve rol saklama burada bulunur.

- `AppBootstrap`: SharedPreferences yükler, rolü çözer ve doğru shell'i açar.
- `AppRole`: `server` ve `client` rollerini tanımlar.
- `RoleRepository`: Rol bilgisini kalıcı saklama arayüzüdür.
- `RoleResolver`: Kaydedilmiş rolü okuyup açılış kararını verir.

### 3.2 `core/`

Rol bağımsız temel katmandır.

- `protocol/`: Pairing payload, pairing session, endpoint sabitleri ve alert DTO'ları.
- `security/`: Certificate fingerprint, token üretimi ve local TLS soyutlamaları.
- `theme/`: BabyCam renkleri ve rol bazlı tema üretimi.

### 3.3 `analysis/`

Medya analiz algoritmaları burada toplanır.

- `video/`: Luma frame, downsampling, frame-rate gate ve motion analyzer.
- `audio/`: PCM16LE reader, ring buffer, Goertzel band analyzer ve cry analyzer.
- `alert/`: Alert type, severity, cooldown policy ve alert engine.

### 3.4 `features/server/`

Server rolünün UI, runtime, pairing, medya ve alert bileşenlerini içerir.

- `server_composition_root.dart`: Server graph'ını kurar.
- `server_runtime.dart`: Server ekranlarının çağırdığı operasyonları temsil eder.
- `pairing/`: QR payload, pairing listener ve trusted client registry.
- `media/`: Kamera, mikrofon, MJPEG, WAV/PCM stream ve güç modu kontrolü.
- `alerts/`: Alert broadcast ve WebSocket event gateway.
- `status/`: Server durum sağlayıcıları.

### 3.5 `features/client/`

Client rolünün UI, runtime, pairing, stream ve alert bileşenlerini içerir.

- `client_composition_root.dart`: Client graph'ını kurar.
- `client_runtime.dart`: Client ekranlarının çağırdığı operasyonları temsil eder.
- `pairing/`: QR scanner, QR pairing client ve session store.
- `media/`: Watch screen, video viewer, audio player ve stream session controller.
- `alerts/`: Alert listener, local notification, history ve share service.

### 3.6 `services/`

Mevcut entegrasyon ve legacy servisler burada durur.

- `BabyCamServer`: Server entegrasyon merkezi.
- `ConfigurationService`: Kalıcı ayarlar.
- `DiscoveryService`: Ağ keşfi yardımcıları.
- `TelegramService`: Manuel paylaşım/entegrasyon hedefleri için ayrılmış servis.
- `MediaAnalysisCoordinator`: Medya analiz metriklerini koordine eder.

---

## 4. Uygulama açılış akışı

```text
main.dart
  ↓
runApp(...)
  ↓
AppBootstrap.initState
  ↓
SharedPreferences.getInstance
  ↓
SharedPreferencesRoleRepository oluşturulur
  ↓
RoleResolver.resolve
  ↓
role == null    → RoleSelectionScreen
role == server  → ServerAppShell + ServerCompositionRoot.create
role == client  → ClientAppShell + ClientCompositionRoot.create
```

Adımlar:

1. Flutter uygulaması `main.dart` ile başlar.
2. `AppBootstrap` kalıcı tercihleri yükler.
3. `RoleResolver` daha önce seçilen rolü okur.
4. Rol yoksa kullanıcı rol seçim ekranına yönlendirilir.
5. Rol server ise `ServerCompositionRoot` çağrılır.
6. Rol client ise `ClientCompositionRoot` çağrılır.
7. Rol sıfırlanırsa mevcut runtime dispose edilir ve rol seçimine dönülür.

---

## 5. Rol izolasyonu

Yanlış mimari şudur:

```text
BabyCamServer oluştur
BabyCamClient oluştur
UI'da birini gizle
```

BabyCam bunu yapmaz. Doğru yaklaşım:

```text
role == server → sadece server graph
role == client → sadece client graph
```

Bunun faydaları:

- Client cihazında server kamera/mikrofon capture servisleri oluşmaz.
- Server cihazında QR scanner veya watch viewer graph'ı kurulmaz.
- Testler hangi composition root'un kaç kez oluştuğunu doğrulayabilir.
- Bellek, izin ve güvenlik yüzeyi küçülür.

---

## 6. Server composition root

Server graph'ı şu sorumlulukları bir araya getirir:

```text
ServerCompositionRoot.create
  ↓
PairingTokenService
  ↓
BabyCamServer
  ↓
ServerQrPayloadBuilder
  ↓
MediaRuntimeController
  ↓
ServerRuntime
```

Detaylı adımlar:

1. `PairingTokenService` nonce ve trusted token üretiminden sorumludur.
2. `BabyCamServer` server entegrasyon merkezidir.
3. `ServerQrPayloadBuilder` QR payload üretir.
4. `MediaRuntimeController` medya runtime start/stop davranışını sarar.
5. `ServerRuntime`, UI'nın kullanacağı sade komutları sunar.

Server runtime tipik operasyonları:

- Pairing modunu başlat.
- QR payload döndür.
- Medya runtime'ı başlat.
- Medya runtime'ı durdur.
- Runtime dispose et.

---

## 7. Client composition root

Client graph'ı şu sorumlulukları bir araya getirir:

```text
ClientCompositionRoot.create
  ↓
QRPairingClient
  ↓
PairingSessionStore
  ↓
StreamSessionController
  ↓
ClientAlertListener
  ↓
ClientNotificationService
  ↓
AlertShareService
  ↓
ClientRuntime
```

Detaylı adımlar:

1. `QRPairingClient` QR payload ile pairing isteği yapar.
2. `PairingSessionStore` pairing sonucunu kalıcı saklar.
3. `StreamSessionController` watch oturumunu başlatır/durdurur.
4. `ClientAlertListener` server event kanalını dinler.
5. `ClientNotificationService` yerel bildirim altyapısını hazırlar.
6. `AlertShareService` manuel paylaşım işlemlerini temsil eder.
7. `ClientRuntime`, UI için sade client operasyonlarını sunar.

---

## 8. Pairing mimarisi

Pairing, BabyCam güven modelinin ilk adımıdır.

```text
Server
  ↓ QR payload üretir
Client
  ↓ QR okur
Client
  ↓ /pair/confirm çağırır
Server
  ↓ nonce doğrular
Server
  ↓ trusted client token üretir
Client
  ↓ session store'a kaydeder
```

QR URI formatı:

```text
babycam://pair?payload=<base64url-json>
```

Payload alanları:

```json
{
  "schemaVersion": 1,
  "scheme": "babycam",
  "host": "192.168.1.20",
  "port": 8443,
  "deviceId": "server_local",
  "deviceName": "Bebek Odası",
  "pairingNonce": "one_time_nonce",
  "expiresAtMs": 1710000000000,
  "certificateFingerprintSha256": "sha256_hex",
  "capabilities": {
    "video": "mjpeg",
    "audio": "pcm16le",
    "events": "json",
    "transport": "https"
  }
}
```

Pairing kuralları:

1. Nonce yalnızca ilk eşleşme içindir.
2. Nonce tek kullanımlıdır.
3. Varsayılan TTL 10 dakikadır.
4. Expired payload reddedilir.
5. Parse edilemeyen payload uygulamayı crash ettirmez.
6. Nonce stream token olarak kullanılmaz.

---

## 9. Trusted client token mimarisi

Pairing başarılı olduğunda server client'a süreli token verir.

```json
{
  "serverDeviceId": "server_local",
  "serverName": "Bebek Odası",
  "clientId": "client_local",
  "trustedClientToken": "random_256_bit_hex",
  "trustedClientTokenExpiresAtMs": 1710000000000,
  "capabilities": {
    "video": "mjpeg",
    "audio": "pcm16le",
    "events": "json"
  }
}
```

Kurallar:

1. Token en az 128-bit entropy içermelidir.
2. Mevcut üretici 32 byte / 256-bit random hex üretir.
3. Server token düz metnini saklamaz; SHA-256 hash saklar.
4. Token varsayılan olarak 60 gün geçerlidir.
5. Son 7 güne girince token renew edilebilir.
6. Token revoke veya expire olursa tekrar QR gerekir.
7. Token loglara yazılmaz.

Renew endpoint hedefi:

```http
POST /auth/renew
Authorization: Bearer <trusted-client-token>
```

---

## 10. Transport ve endpoint mimarisi

Production hedefi HTTPS/WSS yerel transporttur.

```text
https://<server-ip>:<port>/pair/confirm
https://<server-ip>:<port>/auth/renew
https://<server-ip>:<port>/session/start
https://<server-ip>:<port>/session/stop
https://<server-ip>:<port>/video
https://<server-ip>:<port>/audio
wss://<server-ip>:<port>/ws/events
https://<server-ip>:<port>/status
```

Endpoint yetkilendirme:

| Endpoint | Amaç | Yetki |
| --- | --- | --- |
| `/pair/confirm` | İlk eşleşme | QR nonce |
| `/auth/renew` | Token yenileme | Bearer token |
| `/session/start` | Watch oturumu başlatma | Bearer token |
| `/session/stop` | Watch oturumu durdurma | Bearer token |
| `/video` | MJPEG video akışı | Bearer token |
| `/audio` | PCM/WAV ses akışı | Bearer token |
| `/ws/events` | Alert/status event akışı | Bearer token |
| `/status` | Cihaz durumu | Public sınırlı / full tokenlı |

TLS notları:

- `LocalTlsCertificateManager` kalıcı self-signed identity için ayrılmıştır.
- `CertificateFingerprint` client tarafında pinning kararında kullanılır.
- Uygulama sessizce HTTP fallback'e düşmemelidir.
- Debug fallback gerekirse açık flag ile, kapalı varsayılan olarak uygulanmalıdır.

---

## 11. Server medya mimarisi

Server tarafı medya akışı üç kaynaktan oluşur:

```text
CameraCaptureService ──→ MjpegStreamService ──→ /video
MicrophoneCaptureService ──→ WavAudioStreamService ──→ /audio
Camera/Microphone samples ──→ Analysis pipeline ──→ AlertEngine
```

Adımlar:

1. Client `/session/start` çağırır.
2. Server aktif client sayısını artırır.
3. Video isteniyorsa kamera açılır.
4. Ses isteniyorsa mikrofon açılır.
5. Kamera kareleri MJPEG stream servisine gider.
6. Mikrofon örnekleri WAV/PCM stream servisine gider.
7. Aynı medya örnekleri analiz pipeline'ına verilebilir.
8. Client `/session/stop` çağırınca sayaçlar azaltılır.
9. Aktif ihtiyaç kalmadıysa kaynaklar kapatılır.

---

## 12. Güç modu mimarisi

Server tek sabit modda çalışmaz. `MediaResourceCounter` ve `ServerPowerMode` kaynak kararını yönetir.

| Mod | Aktif kaynaklar | Kapalı kaynaklar |
| --- | --- | --- |
| `pairingOnly` | UI, QR, hafif pairing/auth endpointleri | Kamera, mikrofon, analyzer, stream encoder |
| `notificationArmed` | Seçili uyarıya göre mikrofon veya düşük FPS kamera, events | Canlı MJPEG/audio stream |
| `liveWatch` | Kamera, mikrofon, video/audio stream, analysis, events | Gereksiz encoder/stream yazımları |

Karar alanları:

- `activeVideoClients`
- `activeAudioClients`
- `activeEventClients`
- `wantsCryDetection`
- `wantsMotionDetection`

Kurallar:

1. Video client yoksa JPEG encode yapılmaz.
2. Audio client yoksa audio stream yazılmaz.
3. Sadece ağlama bildirimi için kamera açılmaz.
4. Sadece hareket bildirimi için mikrofon açılmaz.
5. Hiçbir aktif ihtiyaç kalmadığında kaynaklar kapatılır.

---

## 13. Video analiz mimarisi

Hareket algılama pipeline'ı:

```text
Camera frame
  ↓
LumaDownsampler
  ↓
LumaFrame
  ↓
FrameRateGate
  ↓
MotionAnalyzerV2
  ↓
MotionAnalysisResult
  ↓
AlertEngine
```

Bileşenler:

- `LumaDownsampler`: Görüntüyü luma yoğunluk verisine indirger.
- `FrameRateGate`: Analiz frekansını kontrol eder.
- `MotionAnalyzerV2`: Kareler arası değişimi skorlar.
- `MotionAnalysisConfig`: Eşik ve bölge ayarlarını taşır.
- `MotionAnalysisResult`: Skor, eşik ve algılama sonucunu temsil eder.

---

## 14. Ses analiz mimarisi

Ağlama algılama pipeline'ı:

```text
Microphone samples
  ↓
Pcm16leReader
  ↓
AudioRingBuffer
  ↓
GoertzelBandAnalyzer
  ↓
CryAudioAnalyzerV2
  ↓
AudioAnalysisResult
  ↓
AlertEngine
```

Bileşenler:

- `Pcm16leReader`: PCM16LE örneklerini okur.
- `AudioRingBuffer`: Kısa süreli ses penceresini tutar.
- `GoertzelBandAnalyzer`: Frekans bant enerjilerini hesaplar.
- `CryAudioAnalyzerV2`: Ağlama skorunu üretir.
- `AudioCalibrationState`: Ortam ses seviyesi kalibrasyonunu temsil eder.
- `AudioAnalysisResult`: Skor, dBFS ve ambient ölçümleri taşır.

---

## 15. Alert mimarisi

Alert üretim ve tüketim akışı:

```text
MotionAnalyzerV2 / CryAudioAnalyzerV2
  ↓
AlertEngine
  ↓
ServerAlertBroadcaster
  ↓
WebSocketEventGateway
  ↓
ClientAlertListener
  ↓
ClientNotificationService
  ↓
ClientAlertHistory
  ↓
AlertShareService
```

Alert engine sorumlulukları:

1. Analiz sonuçlarını eşiklerle değerlendirir.
2. Cooldown politikasını uygular.
3. Alert type ve severity belirler.
4. JSON DTO'ya çevrilecek domain event üretir.

Örnek event:

```json
{
  "schemaVersion": 1,
  "id": "evt_01HV...",
  "type": "cryDetected",
  "severity": "warning",
  "messageKey": "alert.cryDetected",
  "message": "Ağlama algılandı",
  "score": 0.82,
  "timestampMs": 1710000000000,
  "sourceDeviceId": "server_local",
  "metadata": {
    "cryScore": 0.82,
    "dbfs": -23.4,
    "ambientDbfs": -48.1
  }
}
```

Paylaşım kuralı: Client otomatik relay yapmaz; paylaşım manuel kullanıcı aksiyonudur.

---

## 16. Client watch lifecycle

```text
WatchScreen açılır
  ↓
StreamSessionController.start
  ↓
/session/start
  ↓
/video bağlanır
  ↓
/audio bağlanır
  ↓
/ws/events bağlanır
  ↓
Kullanıcı izlemeyi durdurur veya ekran kapanır
  ↓
/video, /audio, /ws/events dispose
  ↓
/session/stop
```

Kurallar:

1. QR scanner yalnızca pairing sırasında kamera açar.
2. Pairing başarılı olunca scanner dispose edilir.
3. Watch ekranı açılınca stream session başlar.
4. Watch dispose olunca video/audio stream kapanır.
5. Background'a geçildiğinde canlı medya kapatılmalıdır.
6. Alert listener kullanıcı ayarına göre açık kalabilir.

---

## 17. UI mimarisi

UI dört ana akıştan oluşur:

### 17.1 Rol seçimi

Kullanıcıya “Bu cihaz ne olarak çalışacak?” sorulur.

- Bebek odası cihazı
- Ebeveyn cihazı

Seçim `RoleRepository` ile kaydedilir.

### 17.2 Server home

Server ekranı şu bilgileri gösterir:

- QR pairing kartı
- Pairing nonce süresi
- Client eşleşme durumu
- Medya runtime durumu
- Analiz özeti
- Son uyarı
- Yayını durdur aksiyonu

### 17.3 Client home

Client ekranı şu durumlara göre değişir:

- Eşleşme yok: “QR tara”
- Eşleşme var: “İzle + dinle”
- Bildirim modu: alert listener durumu

### 17.4 Watch screen

Watch ekranı şunları birleştirir:

- Video alanı
- Ses bağlantı rozeti
- WebSocket/event rozeti
- Son uyarı kartı
- İzlemeyi durdur butonu

---

## 18. Tema ve tasarım sistemi

Tema katmanı `core/theme` ve `features/shared/presentation` altında toplanır.

- Server tarafı pembe ağırlıklı marka tonlarını kullanır.
- Client tarafı mavi ağırlıklı marka tonlarını kullanır.
- Neutral tema rol seçimi ve genel durumlar içindir.
- Tasarım tokenları spacing, radius, metin ve kart davranışlarını standartlaştırır.

Amaç, teknik olarak farklı iki rolün kullanıcı tarafından da hızlı ayırt edilmesidir.

---

## 19. Kalıcı veri mimarisi

Kalıcı veri küçük tutulur.

| Veri | Katman | Amaç |
| --- | --- | --- |
| App role | `RoleRepository` | Açılışta doğru graph'ı seçmek |
| Pairing session | `PairingSessionStore` | Server identity ve trusted token saklamak |
| Config | `ConfigurationService` | Server/client ayarlarını saklamak |
| Trusted clients | `PairedClientRegistry` | Server tarafında token hash ve client bilgisi tutmak |

Güvenlik notu: Token düz metni loglanmamalı ve server tarafında düz metin saklanmamalıdır.

---

## 20. Test mimarisi

Testler rol izolasyonu, pairing, lifecycle, analiz ve alert davranışlarını kapsar.

Örnek test alanları:

- `test/app/role_isolation_test.dart`: Role göre doğru composition root oluşur.
- `test/core/pairing_payload_test.dart`: QR payload parse/serialize ve expiry davranışları.
- `test/features/server/pairing_token_service_test.dart`: Token/nonce üretimi ve süreleri.
- `test/features/server/server_runtime_lifecycle_test.dart`: Server runtime start/stop/dispose.
- `test/features/client/client_runtime_lifecycle_test.dart`: Client stream/alert lifecycle.
- `test/analysis/video/*`: Motion analyzer ve frame gate testleri.
- `test/analysis/audio/*`: PCM, ring buffer, Goertzel ve cry analyzer testleri.
- `test/analysis/alert/*`: Alert engine ve cooldown policy testleri.

Çalıştırma:

```bash
dart format .
flutter analyze
flutter test
```

---

## 21. Platform mimarisi notları

### Android

Server modu uzun süre çalışacaksa şu platform parçaları gerekir:

1. Foreground service
2. Kalıcı bildirim
3. Kamera/mikrofon izinleri
4. Battery optimization uyarısı
5. Kontrollü wakelock
6. Background kısıtlarına uyumlu medya durdurma

### iOS

iOS'ta server kullanımının foreground olması beklenmelidir.

1. Kamera/mikrofon izinleri açıkça istenir.
2. Background'a geçildiğinde stream ve analysis kaynakları kapatılır.
3. Yerel ağ erişim izinleri ve açıklamaları doğru yapılandırılır.

---

## 22. Geliştirme adımları

Yeni özellik eklerken önerilen sıra:

1. Özelliğin hangi role ait olduğunu belirle.
2. Ortak protocol/security ihtiyacı varsa `core/` altında modelle.
3. Server'a aitse `features/server/` altında graph'a ekle.
4. Client'a aitse `features/client/` altında graph'a ekle.
5. Composition root'a yalnızca ilgili rol için bağla.
6. Runtime API'sini UI için sade tut.
7. Lifecycle dispose davranışını ekle.
8. Token veya medya kaynağı kullanılıyorsa güvenlik ve kaynak kapanış testleri yaz.
9. `flutter analyze` ve `flutter test` çalıştır.
10. README ürün dilini, ARCHITECT teknik dili koruyacak şekilde güncelle.

---

## 23. Gelecek mimari işler

- Kalıcı self-signed certificate üretimi ve güvenli saklama.
- `HttpServer.bindSecure` ile production HTTPS/WSS entegrasyonu.
- Token renew/revoke UI ve server endpointlerinin tamamlanması.
- Manual IP/discovery fallback ekranlarının netleştirilmesi.
- Android foreground service implementasyonu.
- iOS lifecycle ve permission metinlerinin olgunlaştırılması.
- Daha ayrıntılı alert history ve manuel paylaşım akışı.
- Medya resource counter'ın gerçek client bağlantı sayılarıyla entegre edilmesi.

---

## 24. Mimari karar özeti

BabyCam'in temel kararı şudur: **aynı uygulama iki rolü taşıyabilir, ancak aynı anda iki rol gibi davranmamalıdır.**

Bu karar sayesinde:

- Güvenlik yüzeyi küçülür.
- Medya kaynakları gereksiz açılmaz.
- UI daha anlaşılır olur.
- Test edilebilirlik artar.
- Cloud bağımsız yerel bebek kamerası deneyimi korunur.
