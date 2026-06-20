# MimiCam Architecture

Bu doküman MimiCam Flutter uygulamasının güncel mimarisini anlatır. Kaynak gerçekliği `lib/` ağacıdır; eski Kotlin yaklaşımı, UDP discovery, cloud/relay fikirleri ve pinned TLS denemesi MVP kapsamı dışındadır.

---

## 1. Karar Özeti

MimiCam MVP, aynı local Wi‑Fi ağı içinde HTTP/WS + pairing token modeliyle çalışır. HTTPS/WSS ve certificate pinning MVP kapsamından çıkarılmıştır. Ürün hedefi iki telefon veya en fazla 5 local cihaz arasında düşük gecikmeli ve zayıf Wi-Fi’da stabil medya aktarımıdır. Güvenlik; pairing mode, tek kullanımlık nonce, trusted token, max device limit ve local network guard ile sağlanır.

Ana kararlar:

1. Tek uygulama iki rol taşır; Server ve Client graph’ları aynı anda kurulmaz.
2. Default ve tek MVP transport `http` + `ws` modelidir.
3. Pairing QR birincil, manuel IP:port kontrollü fallback’tir.
4. Pairing token QR içinde taşınmaz; nonce tek kullanımlıdır.
5. En fazla 5 trusted Client ve 5 aktif watch Client desteklenir.
6. Medya pipeline audio/event öncelikli, video ise adaptif ve düşürülebilirdir.
7. Server tek latest JPEG üretir; client başına encode veya backlog yoktur.
8. `MimiCamServer` public facade olarak kalır; client lifecycle, auth, kalite seçimi ve backpressure küçük server policy sınıflarına ayrılır.

---

## 2. Runtime Topolojisi

```text
main.dart
  ↓
MimiCamApp
  ↓
AppBootstrap
  ↓
SharedPreferencesRoleRepository
  ↓
RoleResolver
  ↓
┌──────────────────────────────┬──────────────────────────────┐
│ AppRole.server               │ AppRole.client               │
│ ServerCompositionRoot        │ ClientCompositionRoot        │
│ ServerRuntime                │ ClientRuntime                │
│ MimiCamServer                │ Pairing / Watch / Alerts     │
└──────────────────────────────┴──────────────────────────────┘
```

`AppBootstrap` yalnız seçili rolün shell’ini mount eder. Rol değişiminde eski runtime dispose edilir, rol repository güncellenir ve yeni graph kurulur.

---

## 3. Dizin Haritası

```text
lib/
├── app/                    # bootstrap, role resolver, permission coordinator
├── core/
│   ├── media/              # MediaQualityProfile, NetworkQualityTier, tracker
│   ├── network/            # LocalNetworkGuard
│   ├── protocol/           # PairingPayload, PairingSession, endpoint builder
│   └── security/           # TransportConfig, token primitives
├── analysis/
│   ├── alert/              # AlertEngine, cooldown policy, event model
│   ├── audio/              # PCM reader, ring buffer, Goertzel, cry analyzer
│   └── video/              # luma frame, downsampler, motion analyzer
├── features/
│   ├── client/             # Client UI/runtime, pairing, stream/session clients
│   ├── server/             # Server UI/runtime, pairing token service
│   └── shared/             # design tokens and shell widgets
└── services/
    ├── mimicam_server.dart # local HTTP server and media pipeline
    ├── server/             # client registry, auth guard, quality/backpressure policies
    └── platform/           # device capability and foreground service adapters
```

`services/server/` altındaki ana parçalar:

| Sınıf | Sorumluluk |
| --- | --- |
| `ActiveClientRegistry` | Aktif watch slotları, stream attach/detach, streamToken prune ve kalite tracker lifecycle’ı |
| `RequestAuthGuard` | Bearer trusted token doğrulama ve `clientId` çözümleme |
| `MediaQualitySelector` | Device tier + network tier + client load zincirinden medya profili seçimi |
| `StreamBackpressureGate` | MJPEG/audio stream için busy-skip ve cleanup |
| `MediaFrameBudget` | Encode/analyze frame aralığı |
| `MediaEncodingPolicy` | MJPEG encode gerekip gerekmediği |

Client media tarafındaki ana parçalar:

| Sınıf | Sorumluluk |
| --- | --- |
| `ClientStreamHealthMonitor` | Video/audio/event health snapshot ve quality payload sinyalleri |
| `NetworkQualityMonitor` | RTT/status probe ile health snapshot birleştirme ve `/quality/report` gönderimi |
| `StreamSessionController` | Session start/stop ve lightweight `/video`/`/audio` health reader lifecycle’ı |
| `ClientAlertListener` | WS connect/disconnect/reconnect sinyallerini health monitöre aktarma |

---

## 4. Transport Model

MVP transport tek moddur:

```dart
enum TransportMode { localHttpWs }

class TransportConfig {
  const TransportConfig();
  String get httpScheme => 'http';
  String get wsScheme => 'ws';
}
```

Server her zaman `HttpServer.bind(...)` kullanır. `HttpServer.bindSecure`, `SecurityContext`, runtime certificate manager ve pinned HTTP client yoktur.

Client URL kuralları:

- HTTP endpointler: `http://host:port/path`
- Event socket: `ws://host:port/ws/events`
- Manuel IP fallback: `http://host:port/status/public`

---

## 5. Pairing Payload

`PairingPayload` QR içinde base64url JSON olarak taşınır:

```json
{
  "schemaVersion": 1,
  "scheme": "mimicam",
  "host": "192.168.1.20",
  "port": 8080,
  "deviceId": "server_local",
  "deviceName": "Bebek Odası",
  "pairingNonce": "one_time_nonce",
  "expiresAtMs": 1710000000000,
  "transport": "http_ws",
  "capabilities": {
    "video": "mjpeg",
    "audio": "pcm16le",
    "events": "json",
    "maxClients": 5
  }
}
```

Alan kararları:

- `certificateFingerprintSha256` yoktur.
- `tlsMode`, `https`, `wss`, `httpScheme`, `wsScheme` yoktur.
- `transport` string değeri `http_ws` olur.
- Token QR içinde asla taşınmaz.

---

## 6. Pairing ve Token Modeli

### Pairing Mode

Server pairing mode’a QR/IP ekranı açıldığında girer. Bu mod:

- Local HTTP server’ı başlatır.
- `/status/public` ve `/pair/confirm` için nonce üretimini mümkün kılar.
- Kamera/mikrofonu otomatik başlatmaz.

### Nonce

- `PairingTokenService.createPairingNonce()` 256-bit random nonce üretir.
- Nonce TTL varsayılan 10 dakikadır.
- `validateAndConsumeNonce()` nonce’u tek kullanımda tüketir.

### Trusted Client

Trusted client modeli:

```text
clientId
clientName
tokenHash
pairedAt / createdAtMs
lastSeenAt / lastSeenAtMs
expiresAtMs
revoked
```

Ham trusted token yalnız Client’a döner. Server `sha256` hash saklar. Revoked client sayılmaz ve slot açar.

Limit:

- `maxTrustedClients = 5`
- 6. pairing: `409`, `MAX_TRUSTED_CLIENTS_REACHED`
- Kullanıcı mesajı: “En fazla 5 cihaz eşleştirilebilir. Önce eski bir cihazı kaldırın.”

### Stream Token

`/session/start` Bearer trusted token ile çağrılır ve 60–120 saniye aralığında kısa ömürlü stream token üretir. Mevcut uygulama varsayılanı 90 saniyedir.

Stream token:

- Sadece `/video` ve `/audio` için query parametresi olarak kabul edilir.
- `/status`, `/quality/report`, `/auth/renew`, `/ws/events` için geçerli değildir.
- Trusted token’ın query parametresi olarak kullanılmasına izin verilmez.
- `ActiveClientRegistry` tarafından `clientId` ile ilişkilendirilir.
- Expire olduğunda prune edilir; aktif stream bağlantısı yoksa client slotu da temizlenir.

---

## 7. Endpoint Matrisi

| Endpoint | Amaç | Auth | Not |
| --- | --- | --- | --- |
| `GET /status/public` | Pairing public bilgisi | Local ağ | Pairing mode aktifken nonce döner |
| `POST /pair/confirm` | Trusted token üretimi | Nonce | Nonce tek kullanımlıdır |
| `POST /auth/renew` | Trusted token yenileme | Bearer token | Revoked/expired token reddedilir |
| `POST /session/start` | Watch slot açma | Bearer token | Aynı client için idempotent, streamToken döner |
| `POST /session/stop` | Watch slot kapatma | Bearer token | Registry cleanup yapar |
| `POST /quality/report` | Client kalite raporu | Bearer token | TTL 15 saniye |
| `GET /status` | Private server durumu | Bearer token | Medya profili ve sayaçlar |
| `GET /video` | MJPEG stream | Bearer veya streamToken | Query trusted token kabul edilmez |
| `GET /audio` | PCM16LE/WAV stream | Bearer veya streamToken | Audio öncelikli |
| `GET /ws/events` | Alert/event WebSocket | Bearer token | Normal `WebSocketTransformer.upgrade` |

Tüm endpointlerden önce `LocalNetworkGuard` çalışır. Guard private IPv4 bloklarını ve debug loopback’i kabul eder; public IP’leri reddeder. Bu firewall değildir, yanlışlıkla dış ağa açılma riskini azaltır.

---

## 8. Client Limitleri

### Trusted Client

`PairingTokenService` revoked olmayan trusted kayıtları sayar. Yeni bir cihaz 5 slot doluyken eşleşemez.

### Active Watch Client

`MimiCamServer` aktif watch client yönetimini `ActiveClientRegistry` üzerinden yapar. Server facade endpointleri ve media runtime’ı taşır; slot, streamToken ve kalite report lifecycle’ı registry’de toplanır.

- `maxActiveWatchClients = 5`
- 6. aktif watch isteği: `429`, `MAX_ACTIVE_CLIENTS_REACHED`
- `/session/start` aynı client için idempotenttir; slot sayısı artmaz, yeni `streamToken` döner.
- `/video` ve `/audio` auth sonucu sadece boolean değildir; trusted token veya streamToken’dan `clientId` çözülür ve stream attach edilir.
- Aynı client video ve audio stream açarsa tek aktif slot kullanır; connection count ikisi de kapanana kadar client’ı canlı tutar.
- `/session/stop`, stream response disconnect ve streamToken expiry aynı cleanup yolunu kullanır.
- Cleanup slotu, stream connection sayacını, kalite raporunu ve client’a ait stream tokenları temizler.

---

## 9. Medya Pipeline

```text
CameraImage
  ↓
MediaFrameBudget
  ↓
CameraImageJpegEncoder
  ↓
_latestJpeg
  ↓
MJPEG clients
```

Kurallar:

- Client başına kamera frame encode edilmez.
- Server yalnız tek latest JPEG’i tutar.
- MJPEG client response busy ise yeni frame atlanır.
- Audio client flush busy ise yeni PCM chunk atlanır.
- Frame queue/backlog yoktur.
- Response kapanınca MJPEG/audio client listelerinden temizlenir.
- Response kapanınca `ActiveClientRegistry.detachStream()` çağrılır; slot orphan kalmaz.
- Audio ve event akışı video düşse bile önceliklidir.

Backpressure davranışı `StreamBackpressureGate` ile ortaktır:

```text
stream response idle
  ↓
chunk/frame yazılır
  ↓
flush future tamamlanana kadar busy
  ↓
busy iken gelen frame/chunk skip
  ↓
flush tamamlanınca idle veya hata varsa cleanup
```

---

## 10. Adaptif Kalite

Temel profiller:

| Profil | Çözünürlük | FPS | JPEG | Kullanım |
| --- | ---: | ---: | ---: | --- |
| Normal | 854×480 | 8 | 52 | Tek/iyi ağ |
| Weak | 640×360 | 5 | 42 | Zayıf ağ |
| Critical | 426×240 | 2 | 36 | Kritik ağ |
| Survival | 426×240 | 1 | 36 | Snapshot/audio-first |

Client yükü:

- 1 aktif: ağ kalitesi normal/weak/critical seçer.
- 2–3 aktif: en fazla 640×360, 5fps, JPEG 42.
- 4–5 aktif: 426×240 veya düşük 640×360, 2–4fps, JPEG 36–40.

Kalite seçimi `MediaQualitySelector` içinde tek policy olarak tutulur:

```text
MediaQualityProfile.forDeviceTier(deviceTier)
  .adaptForNetwork(effectiveNetworkTier)
  .adaptForClientLoad(activeClientCount)
```

Server kalite seçimi şu sinyallerle ilerler:

- Aktif watch client sayısı.
- Aktif clientların en kötü kalite raporu.
- `NetworkQualityTier` değerleri.
- Frame budget/backpressure.
- Reconnect/failure davranışı.

`ClientQualityTracker` raporları TTL ile tutar; süresi geçen rapor bilinmeyen sayılır. Tracker lifecycle’ı registry içinde olduğu için stop/disconnect/expiry sonrası kalite raporu aktif talebi düşürmez. Selector kötü sinyalde hızlı degrade eder; upgrade için en az 30 saniye stabil metrik ve tek kademelik yükseliş gerekir.

---

## 11. Client Kalite Raporu

Client tarafı kalite raporu artık şu sinyalleri birlikte taşır:

- RTT ve ardışık failure sayısı.
- Video frame gap ve stream timeout.
- Audio gap ve audio underrun.
- WebSocket disconnect/reconnect sayısı.
- Reconnect sonrası ilk 10 saniyede düşük kalite tercihi.
- Watch ekranının aktif olup olmadığı.

`ClientStreamHealthMonitor` video/audio/event gözlemlerini toplar. Canonical frame/chunk sinyali HTTP `/video` ve `/audio` reader’dan gelir; mevcut veya gelecekteki UI callbackleri aynı monitöre ek sinyal besleyebilir.

Data flow:

```text
WatchScreen / ClientRuntime.startWatching
  ↓
StreamSessionController.start
  ↓
/session/start → streamToken
  ↓
lightweight /video + /audio readers
  ↓
ClientStreamHealthMonitor.snapshot
  ↓
NetworkQualityMonitor + RTT/status probe
  ↓
POST /quality/report with Bearer trusted token
  ↓
ActiveClientRegistry + ClientQualityTracker
  ↓
MediaQualitySelector hysteresis
```

Raporlama kuralları:

- Watch aktifken yaklaşık 4 saniyede bir `/quality/report` gönderilir.
- Watch aktif değilken iyi ağda agresif raporlama yapılmaz.
- Video frame gap 2 saniyeye çıkarsa en az weak, 5 saniyeye çıkarsa critical sinyal oluşur.
- Audio underrun veya `audioGapMs >= 1500` critical sinyal üretir.
- WS disconnect/reconnect en az weak sinyal üretir; ardışık kopmalar critical’a kadar düşebilir.
- Server body’deki `clientId` yerine Bearer token’dan çözülen clientId’yi kullanır.
- Stream token bu endpointte geçerli değildir.

Backpressure metrikleri queue üretmeden tutulur:

- MJPEG busy ise yeni frame skip edilir ve `skippedVideoFrames` artar.
- Audio flush busy ise yeni chunk skip edilir ve `skippedAudioChunks` artar.
- Başarılı write timestamp/duration ve ardışık write failure sayısı sayaç olarak tutulur.
- Bu metrikler frame/chunk saklamaz; latest-frame modeli korunur.

---

## 12. UI ve Rol İzolasyonu

Server UI:

- QR/IP tabı pairing mode başlatır.
- Pairing mode medya başlatmaz.
- Yayın ve analiz kartları runtime state’ten beslenir.
- QR panel kompakt ekranlarda taşmayacak şekilde responsive ölçülür.

Client UI:

- QR scan ve manuel IP aynı `PairingPayload` modeline iner.
- Manuel IP yalnız HTTP `/status/public` çağırır.
- Eşleşme sonrası alert listener `ws://.../ws/events` ile açılır.
- Watch ekranı session lifecycle ve network quality state’ini izler.

---

## 13. Test Stratejisi

Ana test kümeleri:

- Role isolation ve lifecycle testleri.
- Pairing payload ve token service testleri.
- Local network guard testleri.
- Trusted/active client limit testleri.
- Token auth ve stream token testleri.
- Adaptive media ve backpressure testleri.
- QR/UI overflow ve render budget testleri.

Refactor sonrası özellikle korunan senaryolar:

- `ActiveClientRegistry` idempotent start, disconnect cleanup, expiry prune ve çoklu stream count.
- `MediaQualitySelector` 1, 2–3, 4–5 client ve weak/critical ağ kombinasyonları.
- `MediaQualitySelector` hızlı degrade, 30 saniye stabil olmadan upgrade etmeme ve tek kademe upgrade hysteresis’i.
- `ClientStreamHealthMonitor` video/audio gap, WS disconnect/reconnect ve watchActive sinyalleri.
- `StreamBackpressureGate` busy-skip ve cleanup davranışı.
- HTTP auth guard: private endpointlerde query trusted token reddi, streamToken’ın yalnız media endpointlerinde kabulü.

Önerilen doğrulama:

```bash
dart format .
flutter analyze
flutter test
```

Manuel cihaz performans kontrolü:

```bash
flutter install -d <device-id> --uninstall-only
flutter run -d <device-id> --profile --trace-startup
```

LG G6 (`LG H870`, Android 9) üzerinde son profile startup trace sonucu: first frame `465ms`, rasterized first frame `861ms`, framework init `447ms`. Startup sırasında `Skipped 38 frames` ve Impeller/Kotlin Gradle Plugin uyarıları görüldü; testleri fail etmedi ama performans/teknik borç olarak takip edilmelidir.

---

## 14. Kapsam Dışı ve Gelecek

MVP kapsamı dışında:

- HTTPS/WSS ve certificate pinning.
- Keystore/Keychain certificate rotation.
- Cloud relay, hesap sistemi, OAuth.
- UDP discovery.
- Client başına ayrı encode pipeline’ı.

Gelecek araştırma alanları:

- WebRTC/H.264 transport.
- Daha zengin client kalite raporları.
- Pairing mode otomatik kapanma UX’i.
- Trusted device yönetim ekranı.
