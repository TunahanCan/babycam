# BabyCam

BabyCam, aynı Flutter kod tabanından iki kesin ayrılmış rolde çalışan yerel ağ bebek kamerası uygulamasıdır:

- **Bebek Odası Cihazı / Server:** QR gösterir, pairing kabul eder, yerel HTTPS/WSS medya ve uyarı endpointlerini yönetir, kamera/mikrofon ve analiz kaynaklarını sadece gerektiğinde açar.
- **Ebeveyn Cihazı / Client:** İlk kurulumda QR okutur, 60 günlük trusted client token saklar, canlı izleme/ses/uyarı akışlarını tüketir ve uyarıları manuel paylaşır.

Uygulama internet relay, cloud backend, STUN/TURN, OAuth veya uzak erişim hedeflemez. Güven modeli aynı Wi‑Fi/LAN içinde **QR ile ilk güven kurma + certificate fingerprint pinning + bearer trusted client token** üzerine kuruludur.

---

## Mimari hedef

Açılışta yalnızca seçilen rolün dependency graph'ı kurulur. Seçilmeyen role ait runtime, medya servisi, scanner, WebView veya analiz sınıfları instantiate edilmez.

```text
main.dart
  ↓
AppBootstrap
  ↓
RoleResolver
  ↓
Role yoksa       → RoleSelectionScreen
Role = server    → ServerAppShell + ServerCompositionRoot.create()
Role = client    → ClientAppShell + ClientCompositionRoot.create()
```

Yanlış model `BabyCamServer` ve `BabyCamClient` nesnelerini beraber üretip UI'da gizlemek olur. Bu repo bunun yerine rol switch'i üzerinden yalnızca ilgili composition root'u oluşturur.

---

## Dizin yapısı

```text
lib/
├── app/                    # AppBootstrap, RoleResolver, RoleRepository, lifecycle observer
├── analysis/               # MotionAnalyzerV2, CryAudioAnalyzerV2, AlertEngine ve analiz modelleri
├── core/
│   ├── protocol/           # PairingPayload, PairingSession, endpoint sabitleri, alert DTO
│   ├── security/           # TLS identity abstraction, fingerprint, secure token generator
│   └── theme/              # BabyCamColors ve BabyCamTheme
├── features/
│   ├── role_selection/     # İlk rol seçimi UI/controller
│   ├── server/             # Server shell, runtime, pairing, media, alerts, status
│   └── client/             # Client shell, runtime, pairing, media, alerts
├── services/               # Legacy/entegrasyon servisleri: BabyCamServer, discovery, config, Telegram
└── main.dart
```

---

## Roller

### Server / Bebek Odası Cihazı

Server modunda oluşturulabilen bileşenler:

- Pairing QR payload üretimi
- Pairing listener
- Trusted client registry/token service
- Local HTTPS/WSS server abstraction
- Kamera/mikrofon capture servisleri
- Motion/Cry analyzer ve AlertEngine
- MJPEG/PCM stream servisleri
- WebSocket event gateway
- Pembe ağırlıklı Server UI

Server modunda client scanner/viewer/share/listener graph'ı kurulmaz.

### Client / Ebeveyn Cihazı

Client modunda oluşturulabilen bileşenler:

- QR pairing client/scanner
- Pairing session store
- Stream session controller
- Client video/audio tüketim katmanı
- Alert listener, local notification, alert history/share service
- Mavi ağırlıklı Client UI

Client modunda `BabyCamServer`, server camera/microphone capture, analyzer pipeline, MJPEG encoder veya discovery broadcaster oluşturulmaz.

---

## Rol saklama ve sıfırlama

`RoleRepository` arayüzü rol bilgisini soyutlar:

```dart
abstract class RoleRepository {
  Future<AppRole?> loadRole();
  Future<void> saveRole(AppRole role);
  Future<void> clearRole();
}
```

Varsayılan implementasyon `SharedPreferencesRoleRepository` kullanır. Rol sıfırlanınca aktif runtime dispose edilir ve rol seçim ekranına dönülür.

---

## Tema ve UI

Merkezi tema dosyaları:

- `BabyCamColors`: mavi/pembe marka renkleri, success/danger ve metin renkleri.
- `BabyCamTheme`: server, client ve neutral tema üreticileri.

Role selection ekranı iki büyük kart gösterir:

1. **Ebeveyn Cihazı** — QR okut, canlı izle, bildirim al — mavi tema.
2. **Bebek Odası Cihazı** — QR göster, kamera/mikrofon yayını başlat, ağlama ve hareket algıla — pembe tema.

---

## Pairing modeli

İlk eşleşme QR ile yapılır. QR payload URI formatı:

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

Kurallar:

- Pairing nonce yalnızca ilk eşleşme içindir.
- Nonce tek kullanımlıdır.
- Varsayılan nonce TTL 10 dakikadır.
- Expired veya parse edilemeyen payload crash ettirmez; reddedilir.
- Nonce stream/access token değildir.

---

## Trusted client token

Pairing başarılı olunca server client'a 60 gün geçerli trusted client token verir.

Server response:

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

Token kuralları:

- Token en az 128-bit entropy içerir; mevcut üretici 32 byte / 256-bit random hex üretir.
- Server token'ın düz metnini saklamaz, SHA-256 hash saklar.
- Token süresi 60 gündür.
- Son 7 güne girince client renew edebilir.
- Revoke/expire durumunda tekrar QR gerekir.
- Token loglara yazılmamalıdır.

Renew endpoint:

```http
POST /auth/renew
Authorization: Bearer <trusted-client-token>
```

Response:

```json
{
  "clientId": "client_local",
  "trustedClientToken": "new_random_256_bit_hex",
  "expiresAtMs": 1710000000000
}
```

---

## Yerel şifreli transport

Hedef production transport:

- `https://<server-ip>:<port>/pair/confirm`
- `https://<server-ip>:<port>/auth/renew`
- `https://<server-ip>:<port>/session/start`
- `https://<server-ip>:<port>/session/stop`
- `https://<server-ip>:<port>/video`
- `https://<server-ip>:<port>/audio`
- `wss://<server-ip>:<port>/ws/events`
- `https://<server-ip>:<port>/status`

`LocalTlsCertificateManager` ve `CertificateFingerprint` katmanı self-signed certificate/fingerprint pinning için ayrılmıştır. Mevcut Dart server entegrasyonu güvenli kimliği kalıcı saklayacak abstraction'ı içerir; platform uyumlu gerçek PEM üretimi `HttpServer.bindSecure` ile tamamlanmalıdır. Uygulama sessizce HTTP fallback'e düşmemelidir; debug fallback gerekiyorsa açık flag ile kapalı varsayılan olarak tutulmalıdır.

Güvenin temeli IP değildir:

```text
serverDeviceId + certificateFingerprintSha256 + trustedClientToken
```

Server IP değişirse client son bilinen IP'yi dener, olmazsa discovery/manual fallback ile aynı deviceId ve fingerprint'i arar.

---

## Endpoint yetkilendirme

Pairing dışındaki korumalı endpointler bearer token ister:

- `/video`
- `/audio`
- `/ws/events`
- `/status`
- `/session/start`
- `/session/stop`
- `/auth/renew`

Public status sadece sınırlı bilgi dönebilir:

```json
{
  "app": "BabyCam",
  "deviceId": "server_local",
  "pairingAvailable": true,
  "transport": "https"
}
```

Full diagnostics token istemelidir.

---

## Server güç modları

Server runtime tek seviyede çalışmaz. Kaynak tüketimini azaltmak için üç güç modu hedeflenir:

| Mod | Aktif kaynaklar | Kapalı kaynaklar |
| --- | --- | --- |
| `pairingOnly` | UI, QR, lightweight pairing/auth endpoints | Kamera, mikrofon, analyzer, stream encoder |
| `notificationArmed` | İstenen uyarıya göre mic+cry analyzer veya düşük FPS camera+motion analyzer, events | Canlı MJPEG/audio stream |
| `liveWatch` | Kamera, gerektiğinde mikrofon, video/audio stream, analysis, events | İhtiyaç olmayan encoder/stream yazımları |

`MediaResourceCounter` karar alanları:

- `activeVideoClients`
- `activeAudioClients`
- `activeEventClients`
- `wantsCryDetection`
- `wantsMotionDetection`

Kural: video client yoksa JPEG encode yapılmaz; audio client yoksa audio stream yazılmaz; sadece cry notification için kamera açılmaz.

---

## Client lifecycle

- QR scanner yalnızca pairing sırasında kamera açar ve başarılı pairing sonrası dispose edilir.
- Watch ekranı açılınca `/session/start`, kapanınca `/session/stop` çağrılır.
- Watch dispose olduğunda video/audio stream kapanır.
- Background'a geçince video/audio kapanmalıdır.
- Alert listener kullanıcı ayarına göre açık kalabilir veya kapatılabilir.

---

## Alert modeli

Alert server'da üretilir:

```text
MotionAnalyzerV2 / CryAudioAnalyzerV2
  ↓
AlertEngine
  ↓
WebSocketEventGateway
  ↓
ClientAlertListener
  ↓
Local notification
  ↓
Manual share
```

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

Client başka cihazlara otomatik relay yapmaz; paylaşım manuel kullanıcı aksiyonudur.

---

## Kurulum

Gereksinimler:

- Flutter SDK
- Android Studio veya Xcode hedef platforma göre
- Aynı Wi‑Fi/LAN üzerinde iki cihaz
- Kamera ve mikrofon izinleri

Komutlar:

```bash
flutter pub get
flutter run
```

Kalite kontrolleri:

```bash
dart format .
flutter analyze
flutter test
```

---

## Platform notları

### Android

Server modu uzun süre aktif kalacaksa foreground service, kalıcı bildirim, battery optimization uyarısı ve kontrollü wakelock planlanmalıdır.

### iOS

Server modu pratikte foreground kullanım gerektirebilir. Background'a gidildiğinde stream/analysis kaynaklarının kesilmesi beklenmelidir.

---

## Bu repo ne yapmaz?

- WebRTC'ye geçmez.
- Cloud backend eklemez.
- İnternete yayın açmaz.
- Client cihazı relay/server gibi kullanmaz.
- Enterprise OAuth/security eklemez.
- Motion/Cry analyzer algoritmasını baştan yazmaz.

Odak: strict role isolation, QR first pairing, local encrypted transport mimarisi, 60 günlük auto-renew token, server power modes ve kontrollü medya lifecycle'dır.
