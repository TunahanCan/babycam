# MimiCam Architecture

Bu doküman MimiCam Flutter uygulamasının canlı mimarisini anlatır. Kaynak gerçekliği `lib/` ağacıdır; eski Kotlin yaklaşımı, UDP discovery ve cloud/relay fikirleri bu mimarinin parçası değildir.

---

## 1. Ana Kararlar

1. **Tek uygulama, iki kesin rol:** Server ve Client aynı anda çalışmaz.
2. **Local-first:** Video, ses, event ve token akışları aynı LAN içinde kalır.
3. **QR/IP pairing:** QR birincil güven kaynağıdır; manuel IP fallback kontrollü şekilde korunur.
4. **Pinned local TLS:** Release varsayılanı self-signed HTTPS/WSS + SHA-256 certificate fingerprint pinning’dir.
5. **Kaynaklar ihtiyaç oldukça açılır:** Kamera, mikrofon, analiz ve stream runtime sürekli açık tutulmaz.
6. **Tek encode, çoklu dağıtım:** Server tek JPEG frame üretir, uygun clientlara dağıtır.
7. **Adaptif ama 480p altına düşmeyen medya:** Ağ ve yük değişse de minimum yayın profili 480p’dir.
8. **Ebeveyn odaklı dil:** UI ve uyarılar `AppStrings` ile lokalize edilir.

---

## 2. Üst Seviye Akış

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
│ MimiCamServer                │ Pairing + Watch + Alerts     │
└──────────────────────────────┴──────────────────────────────┘
```

`AppBootstrap` yalnız seçili rolün shell’ini mount eder. Rol değişiminde eski runtime dispose edilir, rol repository güncellenir ve yeni graph kurulur.

---

## 3. Dizin Haritası

```text
lib/
├── app/                    # bootstrap, role resolver, permission policy
├── core/
│   ├── media/              # media profile, network classifier, quality tracker
│   ├── protocol/           # endpoint constants, pairing payload/session, URL builder
│   ├── security/           # TLS config, fingerprint, cert manager, token helpers
│   └── theme/              # app theme primitives
├── analysis/
│   ├── alert/              # AlertEngine, cooldown, event model
│   ├── audio/              # PCM reader, ring buffer, Goertzel, cry analyzer
│   └── video/              # luma frame, downsampler, motion analyzer
├── features/
│   ├── role_selection/     # first-role selection UI/controller
│   ├── server/             # Server shell, runtime, pairing UI, media controls
│   ├── client/             # Client shell, pairing, watch, alerts
│   └── shared/             # design tokens, shell, cards, nav, role badge
├── services/
│   ├── platform/           # foreground service, device capability
│   ├── server/             # media analysis helpers and frame policy
│   ├── mimicam_server.dart # local HTTPS/WSS server and endpoint router
│   └── configuration_service.dart
└── l10n/                   # AppStrings store and localization delegate
```

---

## 4. Rol ve Permission Yaşam Döngüsü

### Role resolution

```text
RoleResolver.resolve
  ↓
role yoksa RoleSelectionScreen
role server ise ServerAppShell
role client ise ClientAppShell
```

### Permission policy

`RolePermissionCoordinator`, rol seçimi sırasında gereken izinleri ister:

| Rol | İzinler |
| --- | --- |
| Client | notification, camera, Android battery optimization |
| Server | notification, camera, microphone, Android battery optimization |

Client kamera izni QR tarama içindir. Server mikrofon izni ses analizi ve audio stream içindir. İzin gateway hataları bootstrap’i kırmayacak şekilde izole edilir.

### Role isolation kuralları

- Client rolündeyken Server camera/microphone runtime kurulmaz.
- Server rolündeyken QR scanner veya Watch graph kurulmaz.
- Server’dan Client’a geçişte aktif Server runtime durdurulur.
- Pairing session rol değişiminde temizlenir.

---

## 5. UI Mimarisi

Ortak görsel yapı `features/shared/presentation` altındadır:

- `MimiCamGradientShell`
- `MimiCamCard`
- `MimiCamRoleBadge`
- `MimiCamBottomNav`
- `MimiCamDesignTokens`

### Server shell

Bottom nav:

```text
Yayın | QR/IP | Servis | Ayarlar
```

Sorumluluklar:

- Yayın önizleme ve runtime durumu.
- QR/IP bileti üretme, yenileme, kopyalama.
- Kamera/mikrofon/analiz/connection status gösterme.
- Analiz eşiklerini ve cooldown ayarlarını değiştirme.

QR paneli responsive çalışır. Kompakt ekranlarda beyaz QR panelinin toplam boyutu sınırlandırılır, uzun HTTPS payload metni gizlenir ve kopyalama aksiyonu korunur.

### Client shell

Bottom nav:

```text
İzle | Bul | Bildirim | Ayarlar
```

Sorumluluklar:

- QR scan veya manuel IP ile Server bulma.
- Pairing tamamlanınca alert listener başlatma.
- Watch ekranında stream session start/stop.
- Network quality ölçümü ve Server’a raporlama.

---

## 6. Composition Root’lar

### ServerCompositionRoot

```text
ServerCompositionRoot.create
  ↓
PairingTokenService
  ↓
MimiCamServer
  ↓
ServerQrPayloadBuilder
  ↓
MediaRuntimeController
  ↓
ServerRuntime
```

Injection noktaları:

- `TransportSecurityConfig`
- `LocalTlsCertificateManager`
- `PairingTokenService`
- `ConfigurationService`
- `AppStrings`

### ClientCompositionRoot

```text
ClientCompositionRoot.create
  ↓
QRPairingClient
  ↓
TrustedTokenRenewalClient
  ↓
PairingSessionStore
  ↓
StreamSessionController
  ↓
NetworkQualityMonitor
  ↓
ClientAlertListener + ClientNotificationService
  ↓
ClientRuntime
```

Client tarafı HTTP(S)/WS(S) istekleri session içindeki host, port, scheme ve certificate fingerprint bilgileriyle çalışır.

---

## 7. Transport Security

### Modlar

`TransportSecurityConfig` iki mod taşır:

| Mod | Kullanım |
| --- | --- |
| `localTlsPinned` | Varsayılan. HTTPS/WSS + self-signed certificate pinning. |
| `insecureHttpDevOnly` | Sadece debug geliştirme. HTTP/WS. |

Profile/release benzeri modda insecure config `StateError` fırlatır.

### Server TLS

```text
MimiCamServer.startPairingMode
  ↓
LocalTlsCertificateManager.loadOrCreate
  ↓
SecurityContext TLS 1.2+
  ↓
HttpServer.bindSecure
```

`LocalTlsCertificateManager`:

- RSA 2048 keypair üretir.
- SHA-256 imzalı self-signed certificate üretir.
- SAN içine `localhost`, `127.0.0.1` ve mevcut LAN IP’lerini koyar.
- Certificate PEM, private key PEM ve metadata’yı `mimicam_tls/` altında saklar.
- Fingerprint’i certificate DER üzerinden SHA-256 olarak hesaplar.
- Metadata fingerprint’i certificate ile uyuşmazsa cert’i geçersiz sayıp yeniden üretir.

### Client pinning

`PinnedHttpClientFactory`:

- `SecurityContext(withTrustedRoots: false)` kullanır.
- `badCertificateCallback` içinde host, port ve SHA-256 fingerprint kontrol eder.
- Genel amaçlı `(_, __, ___) => true` kabulü yapmaz.

WSS için aynı pinned `HttpClient`, `WebSocket.connect(... customClient: client)` ile kullanılır.

---

## 8. Pairing ve Session Modeli

### QR URI

```text
mimicam://pair?payload=<base64url-json>
```

### Payload

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
  "certificateFingerprintSha256": "sha256_hex",
  "transport": {
    "httpScheme": "https",
    "wsScheme": "wss",
    "tlsMode": "selfSignedPinned"
  },
  "capabilities": {
    "video": "mjpeg",
    "audio": "pcm16le",
    "events": "json",
    "transport": "https",
    "mediaProfile": {}
  }
}
```

### Pairing flow

```text
ServerRuntime.startPairingMode
  ↓
MimiCamServer.startPairingMode
  ↓
ServerQrPayloadBuilder.build
  ↓
Client QR parse veya manual IP public status
  ↓
QRPairingClient.pair
  ↓
POST /pair/confirm
  ↓
PairingTokenService.validateAndConsumeNonce
  ↓
trustedClientToken/sessionToken
  ↓
PairingSessionStore.save
```

Kurallar:

- Pairing nonce 10 dakika yaşar ve tek kullanımlıktır.
- QR payload expired ise parse edilmez.
- Pairing response trusted token döndürür.
- Pairing session host, port, device identity, token, fingerprint, scheme ve pairedAt bilgisini saklar.
- Certificate fingerprint değişirse Client yeniden eşleşmelidir.

### Manuel IP

Manual IP fallback production’da şu şekilde çalışır:

```text
Client IP:port girer
  ↓
HTTPS /status/public
  ↓
PublicStatusCertificateDiscoveryClient cert fingerprint yakalar
  ↓
JSON fingerprint ile cert fingerprint karşılaştırılır
  ↓
PairingPayload oluşturulur
  ↓
QRPairingClient pinned HTTPS ile /pair/confirm çağırır
```

HTTP fallback yalnızca debug modda denenir.

---

## 9. Endpointler

Endpoint sabitleri `MimiCamProtocolV2` içindedir.

| Endpoint | Amaç | Yetki |
| --- | --- | --- |
| `/status/public` | Manual IP pairing metadata | Public, token yok |
| `/pair/confirm` | İlk pairing confirm | Pairing nonce |
| `/auth/renew` | Trusted token yenileme | Bearer token |
| `/session/start` | Watch oturumu başlatma | Bearer token |
| `/session/stop` | Watch oturumu durdurma | Bearer token |
| `/quality/report` | Client RTT/failure kalitesi gönderme | Bearer token |
| `/status` | Server status ve media profile | Bearer token |
| `/video` | MJPEG stream | Bearer token |
| `/audio` | WAV/PCM stream | Bearer token |
| `/ws/events` | Alert/status event websocket | Bearer token |

Streamlerde native viewer geçişi tamamlanana kadar query token desteği korunur; yeni HTTP(S)/WS(S) client kodu Authorization header’ı öncelikli kullanır.

---

## 10. Server Runtime ve Medya Lifecycle

`ServerRuntime` UI state’i yönetir. Gerçek network/media işi `MimiCamServer` içindedir.

### Start pairing

```text
ServerRuntime.startPairingMode
  ↓
onStartPairing
  ↓
MimiCamServer.startPairingMode
  ↓
HTTPS/WSS server hazır
  ↓
QR payload UI state’e yazılır
```

### Start media

```text
MimiCamServer.startMediaRuntime
  ↓
availableCameras
  ↓
CameraController initialize + image stream
  ↓
AudioRecorder startStream
  ↓
MediaAnalysisCoordinator
  ↓
ForegroundServiceController.startServer
```

### Stop media

Kamera controller, audio subscription, alert subscription, analysis coordinator, wakelock ve foreground service kapatılır. Runtime idempotent olacak şekilde tasarlanır.

---

## 11. Client Runtime ve Watch Lifecycle

`ClientRuntime` phase ve session state’i taşır:

```text
unpaired
scanningQr
pairing
pairedIdle
renewingToken
watching
alertOnly
reconnecting
offline
revoked
error
```

### Pairing sonrası

- Session store’a yazılır.
- Media profile payload capabilities içinden okunur.
- Network quality monitor başlar.
- Alert listener `ClientPairingFlow.pairAndArmAlerts` ile başlatılabilir.

### Watch

```text
WatchScreen.initState
  ↓
ClientRuntime.startWatching
  ↓
StreamSessionController.start
  ↓
POST /session/start
```

Dispose sırasında `/session/stop` çağrılır. Stop sonrası cached `HttpClient` kapatılır.

---

## 12. Adaptif Medya

Ana tipler:

- `DeviceCapabilityTier`: `legacy`, `balanced`, `modern`
- `NetworkQualityTier`: `unknown`, `excellent`, `good`, `weak`, `critical`, `offline`
- `MediaQualityProfile`: çözünürlük, FPS, JPEG kalite, codec tercihi
- `ClientQualityTracker`: aktif client raporlarını toplar

Varsayılan profiller:

| Tier | Profil |
| --- | --- |
| `legacy` | 854x480, 8 fps, audio-first |
| `balanced` | 854x480, 10 fps |
| `modern` | 1280x720, 15 fps |

Ağ ve yük adaptasyonu:

- Weak/critical ağda 480p korunur, FPS/JPEG düşer.
- Offline/critical durumlarda audio-first survival profil seçilebilir.
- 2+ client modern profili daha stabil hale getirir.
- 4+ aktif video client ortak yayını 854x480, en fazla 8 fps ve JPEG 52 civarına indirir.
- Aktif olmayan client raporları kaliteyi düşürmez.

`MimiCamServer._applyMediaProfileForCurrentDemand`, device tier + active client quality + client load sinyallerini birleştirir. Camera preset değişirse controller kontrollü yeniden başlatılır.

---

## 13. Frame, Audio ve Backpressure

`MediaEncodingPolicy` JPEG encode gerekip gerekmediğini belirler:

- MJPEG client varsa encode yapılır.
- Legacy websocket media packet açıksa encode yapılır.
- İkisi de yoksa video JPEG encode edilmez.

Frame akışı:

```text
CameraImage
  ↓
MediaFrameBudget
  ↓
CameraImageJpegEncoder
  ↓
latestJpeg + MJPEG clients
  ↓
LumaFrame + MotionAnalyzerV2
```

Backpressure:

- `_busyMjpegClients` bir client’a önceki frame yazımı sürerken yeni frame göndermeyi atlar.
- Server tarafında sınırsız frame kuyruğu tutulmaz.
- Audio stream uzun yaşayan response olarak tutulur.

---

## 14. Analiz ve Alert Pipeline

```text
CameraImage → LumaFrame → MotionAnalyzerV2
PCM audio  → AudioChunk → CryAudioAnalyzerV2
Motion/Cry result → AlertEngine → AlertEvent
```

`MediaAnalysisCoordinator`, motion analyzer, cry analyzer ve alert engine’i birleştirir. `AlertEngine`:

- Threshold kontrolü yapar.
- Cooldown uygular.
- Severity/type üretir.
- Lokalize ebeveyn mesajı üretir.
- Broadcast stream ile event yayınlar.

Alert eventleri legacy websocket packet formatına `AlertProtocolAdapter` ile dönüştürülebilir.

---

## 15. Kalıcı Veri

| Veri | Katman |
| --- | --- |
| Seçili rol | `SharedPreferencesRoleRepository` |
| Ayarlar | `ConfigurationService` |
| Pairing session | `PairingSessionStore` |
| Trusted client token kayıtları | `PairingTokenService` runtime memory |
| Local TLS cert/key | `FileLocalCertificateStore` application support directory |

Not: TLS private key şu anda file store arkasındadır; hedef secure storage arkasına taşımaktır.

---

## 16. Lokalizasyon

`AppStrings` desteklenen locale listesini, UI metinlerini ve alert mesajlarını taşır.

Desteklenen diller:

- `en`
- `tr`
- `zh`
- `hi`
- `es`
- `fr`

Flutter localization delegates ile bağlanır. Desteklenmeyen locale İngilizce fallback kullanır.

---

## 17. Test Stratejisi

Standart doğrulama:

```bash
dart format .
flutter analyze
flutter test
```

Test haritası:

| Alan | Testler |
| --- | --- |
| Role isolation | `test/app/role_isolation_test.dart` |
| Permission policy | `test/app/role_permission_coordinator_test.dart` |
| Navigation split | `test/features/hard_split_navigation_test.dart` |
| Compact UI / QR bounds | `test/features/performance/screen_render_budget_test.dart` |
| Pairing payload | `test/core/pairing_payload_test.dart` |
| Transport security | `test/core/security/*` |
| Client pairing | `test/features/client/qr_pairing_client_test.dart` |
| Runtime lifecycle | `test/features/server/server_runtime_lifecycle_test.dart`, `test/features/client/client_runtime_lifecycle_test.dart` |
| Network quality | `test/features/client/network_quality_monitor_test.dart` |
| Adaptive media | `test/core/media/adaptive_media_profile_test.dart`, `test/core/media/client_quality_tracker_test.dart` |
| Analysis | `test/analysis/audio/*`, `test/analysis/video/*`, `test/analysis/alert/*` |
| Localization | `test/l10n/app_strings_test.dart` |

---

## 18. Platform Notları

### Android

- Role-based camera/microphone/notification/battery optimization izinleri istenir.
- Server runtime wakelock ve foreground service controller çağırır.
- Native foreground service kanalının üretim kalitesi ayrıca tamamlanmalıdır.

### iOS

- Kamera/mikrofon ve local network izin metinleri açık olmalıdır.
- Background camera/audio davranışı iOS kurallarıyla sınırlıdır.
- Production öncesi lifecycle davranışı cihaz üzerinde doğrulanmalıdır.

---

## 19. Bilinçli Kapsam Dışı

Mimari şunları içermez:

- Cloud backend
- İnternet relay
- UDP discovery/broadcast
- Telegram otomasyonu
- Hesap/OAuth zorunluluğu
- STUN/TURN relay zorunluluğu
- Otomatik internet paylaşımı

---

## 20. Yakın Teknik İşler

- TLS private key store’unu secure storage arkasına taşımak.
- Token revoke/renew yönetim ekranlarını eklemek.
- Native video/audio player entegrasyonunu tamamlamak.
- Android foreground service kanalını üretim seviyesine taşımak.
- iOS lifecycle ve local network izin davranışlarını cihaz testleriyle netleştirmek.
- Alert history filtreleme ve kalıcı geçmiş modelini genişletmek.
- WebRTC/H264 opsiyonunu uzun vadeli yayın katmanı olarak değerlendirmek.
