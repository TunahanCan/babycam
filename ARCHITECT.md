# MimiCam Mimari Dokümantasyonu

Bu doküman MimiCam’in güncel Flutter mimarisini anlatır. Ana hedef, projeye giren bir geliştiricinin rol ayrımını, pairing güven modelini, medya/analiz boru hatlarını, adaptif kalite kararlarını, lokalizasyonu ve test yaklaşımını hızlıca kavramasıdır.

---

## 1. Mimari Prensipler

1. **Strict role isolation:** Server ve Client aynı anda çalışmaz; sadece seçilen rolün composition root’u kurulur.
2. **Local-first:** Video, ses, status ve event akışları aynı Wi‑Fi/LAN içinde kalır; cloud relay yoktur.
3. **QR/IP-first pairing:** İlk güven QR payload’daki sertifika fingerprint’i ve nonce ile kurulur; manuel IP fallback HTTPS `/status/public` keşfiyle aynı pairing endpointine bağlanır.
4. **Token continuity:** Pairing sonrası Client süreli trusted token ile oturumunu sürdürür.
5. **Resource on demand:** Kamera, mikrofon, encoder ve analyzer ihtiyaç oldukça açılır.
6. **Adaptive media:** Cihaz kapasitesi, aktif Client ağ ölçümleri ve izleyici sayısı yayın profilini belirler.
7. **Localized parent language:** UI ve uyarı metinleri telefon locale değerine göre gelir; fallback İngilizcedir.
8. **No hidden relay:** UDP discovery, Telegram otomasyonu ve cloud relay mimarinin parçası değildir.

---

## 2. Üst Seviye Sistem

```text
main.dart
  ↓
MimiCamApp
  ↓
AppBootstrap
  ↓
RoleResolver + RoleRepository
  ↓
┌────────────────────────────────┬────────────────────────────────┐
│ AppRole.server                 │ AppRole.client                 │
│ ServerCompositionRoot.create   │ ClientCompositionRoot.create   │
│ ServerRuntime                  │ ClientRuntime                  │
│ Pairing + Media + Alerts       │ Pairing + Watch + Notifications│
└────────────────────────────────┴────────────────────────────────┘
```

`AppBootstrap` rolü çözer ve yalnızca ilgili shell’i mount eder. Rol değişiminde eski runtime önce dispose edilir; sonra yeni rol kaydedilir ve yeni graph kurulur.

---

## 3. Dizin Yapısı

```text
lib/
├── app/                    # bootstrap, role resolver, permission policy
├── core/
│   ├── media/              # adaptive media profile, client quality tracker, network classifier
│   ├── protocol/           # pairing/session/protocol DTO sabitleri
│   ├── security/           # token, fingerprint, local TLS soyutlamaları
│   └── theme/              # global tema
├── analysis/
│   ├── alert/              # AlertEngine, cooldown, severity/type
│   ├── audio/              # PCM, ring buffer, Goertzel, cry analyzer
│   └── video/              # luma frame, downsample, motion analyzer
├── features/
│   ├── role_selection/     # ilk rol seçimi
│   ├── server/             # Server UI/runtime/pairing/media/status
│   ├── client/             # Client UI/runtime/pairing/watch/alerts
│   └── shared/             # design tokens, shell, nav, role badge
├── services/               # platform, server integration, config
└── l10n/                   # AppStrings localization store
```

---

## 4. Açılış ve Rol Yaşam Döngüsü

```text
AppBootstrap._load
  ↓
SharedPreferencesRoleRepository
  ↓
RoleResolver.resolve
  ↓
role == null    → RoleSelectionScreen
role == server  → ServerAppShell + ServerCompositionRoot
role == client  → ClientAppShell + ClientCompositionRoot
```

Rol seçim kuralları:

- İlk açılışta cihaz rolü seçilir ve kalıcı saklanır.
- Rol değiştirme sağ üstteki küçük `MimiCamRoleBadge` ile yapılır.
- Server’dan Client’a geçişte onay sheet’i gösterilir.
- Geçişte `_runtime` null yapılır, eski runtime dispose edilir, pairing session temizlenir.
- Client seçiliyken server kamera/mikrofon runtime’ı kurulmaz.
- Server seçiliyken QR scanner veya watch graph’ı kurulmaz.

---

## 5. Permission Policy

`RolePermissionCoordinator` rol seçimi sırasında izinleri ister.

| Rol | İzinler |
| --- | --- |
| Client | Bildirim, kamera, Android battery optimization |
| Server | Bildirim, kamera, mikrofon, Android battery optimization |

Client kamera izni QR tarama içindir. Server mikrofon izni ses analizi ve audio stream içindir. İzin isteği hata verirse bootstrap kırılmaz; uygulama ilgili runtime hatasını UI’da gösterebilir.

---

## 6. UI ve Navigasyon Mimarisi

Ortak yüzeyler `features/shared/presentation` altında toplanır:

- `MimiCamGradientShell`
- `MimiCamCard`
- `MimiCamRoleBadge`
- `MimiCamBottomNav`
- `MimiCamDesignTokens`

Güncel görsel sistem anne odaklı, sıcak krem/blush/mint renkleri ile Server tarafında koyu plum yüzeyleri birleştirir. Geçişler 220 ms hard wipe animasyonuyla yapılır. Ağır yüzeyler `RepaintBoundary` ile izole edilir ve kompakt ekranlar overflow testleriyle korunur.

### 6.1 Server Shell

Bottom nav:

```text
Yayın | QR/IP | Servis | Ayarlar
```

- **Yayın:** Kamera preview, medya profili, active client sayıları, analiz özeti.
- **QR/IP:** QR payload, büyük responsive QR, yenile/kopyala aksiyonları.
- **Servis:** Kamera, mikrofon, analyzer ve bağlantı durumları.
- **Ayarlar:** Hareket/ağlama threshold, minimum duration ve cooldown.

Server ekranlarında Client’a özel QR tarama, bildirim geçmişi ve watch kontrolleri bulunmaz.

### 6.2 Client Shell

Bottom nav:

```text
İzle | Bul | Bildirim | Ayarlar
```

- **İzle:** Eşleşmiş Server için canlı izleme oturumu, kalite durumu ve ebeveyn aksiyonları.
- **Bul:** QR scanner ve manuel IP:port fallback.
- **Bildirim:** Ebeveyne bebeğin son durumunu öne çıkaran alan.
- **Ayarlar:** Client bildirim tercihleri için ayrılmış yüzey.

Client ekranlarında yayın durdurma, QR üretme veya server kamera/mikrofon yönetimi bulunmaz.

---

## 7. Composition Root’lar

### 7.1 ServerCompositionRoot

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

Sorumluluklar:

- Pairing nonce ve trusted token üretimi.
- HTTPS/WSS endpointlerini başlatma.
- QR payload üretme.
- Kamera/mikrofon runtime lifecycle.
- Aktif medya profilini UI’a taşıma.
- Ayar değişince analysis pipeline reload.

### 7.2 ClientCompositionRoot

```text
ClientCompositionRoot.create
  ↓
QRPairingClient
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

Sorumluluklar:

- QR/manual payload ile pair confirm.
- Pairing session saklama.
- Watch stream start/stop.
- Ağ kalite ölçümü ve Server’a quality report gönderme.
- Bildirim altyapısını başlatma.

---

## 8. Pairing ve Token Modeli

Pairing akışı:

```text
Server startPairingMode
  ↓
ServerQrPayloadBuilder.build
  ↓
Client QRScanScreen veya manual IP status/public
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

QR URI formatı:

```text
mimicam://pair?payload=<base64url-json>
```

Payload ana alanları:

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

Kurallar:

- Nonce 10 dakika yaşar ve tek kullanımlıktır.
- Expired veya parse edilemeyen payload reddedilir.
- Pairing sonrası 32 byte / 256-bit token üretilir.
- Server token hash saklar; düz metin token saklamaz.
- Token lifetime 60 gündür, renew window 7 gündür.
- Runtime dispose olduğunda tokenlar revoke edilir.
- Sertifika fingerprint’i değişirse mevcut pairing güven bağı geçersiz kabul edilir ve Client’ın yeniden eşleşmesi gerekir.

---

## 9. Endpoint ve Transport

Release/runtime varsayılan transport `localTlsPinned` modudur:

```text
MimiCamServer.startPairingMode
  ↓
LocalTlsCertificateManager.loadOrCreate
  ↓
SecurityContext TLS 1.2+
  ↓
HttpServer.bindSecure
  ↓
HTTPS endpoints + aynı server üstünde WSS /ws/events
```

`TransportSecurityConfig.insecureHttpDevOnly` sadece debug build’de HTTP/WS açabilir. Profile/release benzeri modda insecure transport `StateError` ile durdurulur.

Client tarafı merkezi URL ve pinned client katmanlarını kullanır:

- `ServerEndpointBuilder` session’daki `httpScheme/wsScheme` ile URL üretir.
- `PinnedHttpClientFactory` `SecurityContext(withTrustedRoots: false)` kullanır ve sadece beklenen host, port ve SHA-256 certificate fingerprint eşleşirse self-signed sertifikayı kabul eder.
- `QRPairingClient`, `TrustedTokenRenewalClient`, `StreamSessionController`, `NetworkQualityMonitor` ve `ClientAlertListener` secure session’da pinned client kullanır.
- Manuel IP fallback production’da önce HTTPS `/status/public` çağırır, token göndermez ve keşfedilen fingerprint’i pairing payload’a bağlar. HTTP fallback yalnızca debug’da denenir.

| Endpoint | Amaç | Yetki |
| --- | --- | --- |
| `/status/public` | Manual IP fallback için pairing payload bilgisi | Public / pairing-only |
| `/pair/confirm` | İlk eşleşme | QR nonce |
| `/auth/renew` | Token yenileme | Bearer token |
| `/session/start` | Watch oturumu başlatma, aktif Client sayısını güncelleme | Bearer token |
| `/session/stop` | Watch oturumu durdurma, Client kalite raporunu temizleme | Bearer token |
| `/quality/report` | Client ağ ölçümünü gönderme; ortak medya profilini güncelleme | Bearer token |
| `/video` | MJPEG video stream | Bearer token |
| `/audio` | WAV/PCM audio stream | Bearer token |
| `/ws/events` | Alert/status event akışı | Bearer token |
| `/status` | Server status ve media profile | Bearer token |

Native viewer tamamlanana kadar streamlerde query token desteği korunur; yeni runtime HTTP ve WSS çağrılarında Authorization header’ı önceliklidir.

---

## 10. Adaptif Medya Mimarisi

`core/media/adaptive_media_profile.dart` ve `core/media/client_quality_tracker.dart` medya kararını şu yapılarla verir:

- `DeviceCapabilityTier`: `legacy`, `balanced`, `modern`
- `NetworkQualityTier`: `unknown`, `excellent`, `good`, `weak`, `critical`, `offline`
- `MediaQualityProfile`: çözünürlük, FPS, JPEG kalitesi, codec tercihleri
- `ClientQualityTracker`: aktif Client raporları arasındaki en zayıf güncel tier

Cihaz profilleri:

| Tier | Varsayılan profil |
| --- | --- |
| `legacy` | 854x480, 8 fps, düşük JPEG, ses öncelikli |
| `balanced` | 854x480, 10 fps |
| `modern` | 1280x720, 15 fps |

Ağ adaptasyonu:

- `excellent`: legacy cihazda kontrollü 480p denemesi yapabilir.
- `good`: stabil FPS/JPEG aralığına iner.
- `weak`: 480p, 7 fps, JPG 50, ses öncelikli profil.
- `critical/offline`: 480p, 4 fps, JPG 42, ses öncelikli survival profil.

Yayın profili 480p altına düşmez. `NetworkQualityMonitor` Client tarafında `/status` RTT ölçer, `/quality/report` gönderir. Server her aktif Client için kalite raporunu tutar; aktif izleyenler arasındaki en zayıf tier ortak yayın profilini belirler. Raporlar kısa TTL ile temizlenir ve session stop olduğunda ilgili Client’ın raporu düşer.

Aktif izleyici adaptasyonu:

- 2+ aktif izleyicide modern profil 720p kalabilir ama FPS/JPEG daha stabil aralığa çekilir.
- 4+ aktif izleyicide `adaptForClientLoad` ortak yayını 854x480, en fazla 8 fps ve JPG 52 seviyesine indirir.
- Kritik/offline ağ raporu varsa 480p korunur; FPS 4’e kadar düşebilir.

Server profil değiştirir, gerekiyorsa camera preset değişimi için controller’ı yeniden başlatır ve UI’a yeni profili bildirir.

---

## 11. Server Medya ve Güç Modu

Server runtime kaynakları `MediaResourceCounter` ile hesaplar:

```text
activeVideoClients
activeAudioClients
activeEventClients
wantsCryDetection
wantsMotionDetection
localPreviewActive
```

HTTP session tarafında `MimiCamServer` ayrıca `_activeStreamClients` listesini tutar. Bu liste kalite kararında aktif izleyici sayısını ve hangi Client kalite raporlarının dikkate alınacağını belirler.

Power mode:

| Mod | Anlam |
| --- | --- |
| `pairingOnly` | Pairing ve hafif status; canlı stream ihtiyacı yok. |
| `notificationArmed` | Alert listener açık; seçili analiz kaynakları çalışabilir. |
| `liveWatch` | Canlı video/ses ve event stream aktif. |

Performans kuralları:

- `MediaFrameBudget` hedef FPS’e göre frame işleme aralığını ayarlar.
- `MediaEncodingPolicy` sadece MJPEG client veya legacy WS gerekirse JPEG encode eder.
- Kamera frame’i Client başına encode edilmez; tek JPEG üretilir ve tüm MJPEG response’larına dağıtılır.
- `_busyMjpegClients` yavaş client için önceki frame yazımı bitmeden yeni frame göndermeyi atlar; bellek/kuyruk şişmesi engellenir.
- `response.done` kapanan MJPEG/WAV clientları listeden temizler.
- Audio stream client yoksa audio data yalnız analiz pipeline’ında kullanılır.
- `ForegroundServiceController` Android native service kanalını çağırır; kanal yoksa sessiz no-op yapar.
- `wakelock_plus` server medya runtime açıkken ekran uyumasını azaltmak için kullanılır.

---

## 12. Analiz ve Alert Mimarisi

Video:

```text
CameraImage
  ↓
LumaFrame
  ↓
MotionAnalyzerV2
  ↓
MotionAnalysisResult
  ↓
AlertEngine
```

Ses:

```text
PCM16LE chunk
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

`MediaAnalysisCoordinator` motion/audio sonuçlarını `AlertEngine`e taşır. `AlertEngine` cooldown uygular, severity seçer ve parent-friendly localized mesaj üretir. Mesajlar tıbbi tanı değildir; ebeveyne kontrol için bağlam verir.

---

## 13. Client Watch Lifecycle

```text
WatchScreen açılır
  ↓
ClientRuntime.startWatching
  ↓
StreamSessionController.start
  ↓
/session/start
  ↓
Server medya runtime açık kalır
  ↓
Viewer katmanı /video + /audio + /ws/events endpointlerini tüketebilir
  ↓
Watch dispose / durdur
  ↓
StreamSessionController.stop
  ↓
/session/stop
```

Kurallar:

- Session yokken `startWatching` no-op döner.
- Pairing başarıyla tamamlanınca network quality monitor başlar.
- Yenilenen WatchScreen session başlatır/durdurur ve kalite durumunu gösterir; native video/audio viewer entegrasyonu endpointler hazır tutularak ilerletilir.
- Watch dispose olduğunda stream stop çağrılır; Server yalnız ilgili Client oturumunu düşürür, diğer aktif izleyiciler varsa medya runtime açık kalır.
- Alert listening streamden bağımsız yönetilebilir.
- Pairing temizlenirse watch, alert ve network subscription kapatılır.

---

## 14. Lokalizasyon Mimarisi

`AppStrings` desteklenen locale listesini ve tüm UI metinlerini taşır:

```dart
en, tr, zh, hi, es, fr
```

Uygulama `AppStrings.delegate` ile Flutter localization zincirine bağlanır. `AppStrings.of(context)` locale bulamazsa İngilizce fallback kullanır. Uyarı mesajları da aynı katmandan üretilir; böylece ekran dili ve bildirim dili birlikte ilerler.

---

## 15. Kalıcı Veri

| Veri | Katman | Amaç |
| --- | --- | --- |
| App role | `RoleRepository` | Açılışta doğru graph seçimi |
| Pairing session | `PairingSessionStore` | Server identity ve session token saklama |
| Config | `ConfigurationService` | Eşikler, süreler, cooldown ayarları |
| Trusted clients | `PairingTokenService` | Token hash ve client kaydı |

Rol değişiminde pairing session temizlenir. Server dispose olduğunda tokenlar revoke edilir.

---

## 16. Test Mimarisi

Test katmanları:

- **Role isolation:** `test/app/role_isolation_test.dart`
- **Permission policy:** `test/app/role_permission_coordinator_test.dart`
- **Hard split UI:** `test/features/hard_split_navigation_test.dart`
- **Performance/overflow:** `test/features/performance/screen_render_budget_test.dart`
- **Adaptive media:** `test/core/media/adaptive_media_profile_test.dart`
- **Client quality aggregation:** `test/core/media/client_quality_tracker_test.dart`
- **Network quality:** `test/features/client/network_quality_monitor_test.dart`
- **Pairing:** `test/core/pairing_payload_test.dart`, `test/features/client/qr_pairing_client_test.dart`
- **Transport security:** `test/core/security/*`
- **Runtime lifecycle:** `test/features/server/server_runtime_lifecycle_test.dart`, `test/features/client/client_runtime_lifecycle_test.dart`
- **Analysis:** `test/analysis/audio/*`, `test/analysis/video/*`, `test/analysis/alert/*`
- **Localization:** `test/l10n/app_strings_test.dart`
- **Frame policy:** `test/services/server/media_frame_policy_test.dart`

Standart doğrulama:

```bash
dart format .
flutter analyze
flutter test
```

---

## 17. Platform Notları

### Android

- Kamera, mikrofon, bildirim ve battery optimization izinleri rol bazlı istenir.
- Server medya runtime `wakelock_plus` ve `ForegroundServiceController` çağırır.
- Native foreground service MethodChannel implementasyonu production için tamamlanmalıdır.

### iOS

- Kamera/mikrofon izin metinleri açık olmalıdır.
- Yerel ağ erişim açıklamaları production öncesi tamamlanmalıdır.
- Background kamera/mikrofon davranışı iOS platform kurallarıyla sınırlıdır.

---

## 18. Bilinçli Kapsam Dışı

Mimari şu parçaları özellikle içermez:

- Cloud backend
- İnternete yayın
- UDP discovery/broadcast
- Telegram otomatik paylaşımı
- STUN/TURN relay zorunluluğu
- İnternet üzerinden otomatik üçüncü kişi paylaşımı
- Hesap/OAuth zorunluluğu

---

## 19. Gelecek Mimari İşler

- Local TLS private key saklamasını secure storage arkasına taşıma.
- Certificate fingerprint pinning UI ve hata akışı.
- Token revoke/renew ekranları.
- Native Android foreground service implementasyonu.
- Native video/audio player ile stream auth modelini güçlendirme.
- WebRTC/H264 yayın katmanı ile ileride per-client kalite veya simulcast seçenekleri.
- Daha ayrıntılı alert history, filtre ve manuel paylaşım.
- iOS lifecycle/background açıklamalarının ürün kararıyla netleştirilmesi.

---

## 20. Karar Özeti

MimiCam’in ana kararı: **tek uygulama iki rolü taşıyabilir, ama aynı anda iki rol gibi davranamaz.**

Bu karar güvenlik yüzeyini küçültür, medya kaynaklarını gereksiz açmaz, UI’ı sadeleştirir ve test edilebilirliği artırır.
