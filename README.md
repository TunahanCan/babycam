# MimiCam

MimiCam, aynı local Wi‑Fi ağı içindeki telefonları basit bir bebek kamerası sistemine dönüştüren Flutter uygulamasıdır. Tek uygulama iki rolden yalnız birini çalıştırır:

- **Server / Bebek Odası:** Kamera, mikrofon, analiz, pairing ve local HTTP/WS yayınını yönetir.
- **Client / Ebeveyn:** QR veya manuel IP:port ile eşleşir, uyarıları dinler ve canlı izleme oturumu açar.

MVP’de cloud, relay, hesap sistemi, OAuth, UDP discovery, Telegram otomasyonu, HTTPS/WSS ve certificate pinning yoktur. Amaç; iki telefon ya da en fazla 5 local cihaz arasında düşük gecikmeli, zayıf Wi‑Fi’da stabil medya aktarımıdır. Client; RTT yanında video frame gap, audio gap/underrun, WebSocket disconnect/reconnect ve stream timeout sinyallerini raporlar. Server tarafında public API sade tutulur; içeride client lifecycle, auth guard, kalite seçimi ve stream backpressure ayrı küçük policy/registry sınıflarıyla yönetilir.

---

## MVP Kararı

MimiCam MVP, aynı local Wi‑Fi ağı içinde **HTTP/WS + pairing token** modeliyle çalışır. Güvenlik; pairing mode, tek kullanımlık nonce, trusted token, maksimum cihaz sınırı, kısa ömürlü stream token ve local network guard ile sağlanır.

| Alan | Karar |
| --- | --- |
| Transport | Sadece `http` + `ws` |
| Pairing | QR birincil, manuel IP:port fallback |
| Trusted cihaz | En fazla 5 eşleşmiş Client |
| Aktif izleme | En fazla 5 eşzamanlı watch client |
| Video | MJPEG, tek latest JPEG, client başına encode yok |
| Audio | PCM16LE/WAV; yavaş client için flush backlog biriktirmez |
| Kalite raporu | RTT + video/audio gap + WS reconnect + watchActive |
| Güvenlik kapsamı | Aynı Wi‑Fi’daki yetkisiz cihazları pairing token ile engelleme |

---

## Kullanım Akışı

```text
Uygulama açılır
  ↓
Rol seçilir: Server veya Client
  ↓
Server QR/IP ekranında pairing mode açar
  ↓
Client QR tarar veya IP:port girer
  ↓
Server nonce doğrular ve trusted token üretir
  ↓
Client Bearer token ile status/event/session endpointlerine erişir
  ↓
Session start kısa ömürlü streamToken üretir
  ↓
Video/audio sadece Bearer token veya streamToken ile açılır
  ↓
Client health monitor 4 sn aralıkla /quality/report gönderir
  ↓
Server hızlı düşürme / 30 sn stabil sonrası tek kademe yükseltme uygular
```

Rol seçimi cihazda saklanır. Rol değişiminde eski runtime dispose edilir ve karşı role ait graph baştan kurulur.

---

## Ekranlar

### Server

- **Yayın:** Server durumu, medya profili, analiz özeti ve yayın kontrolleri.
- **QR/IP:** QR pairing bileti, IP:port bilgisi, yenileme ve kopyalama.
- **Servis:** Kamera, mikrofon, analiz ve client sayaçları.
- **Ayarlar:** Hareket/ağlama eşikleri, minimum süreler ve cooldown.

Server artık uygulama açılır açılmaz pairing başlatmaz. Pairing mode QR/IP ekranı açıldığında başlar; kamera/mikrofon ise canlı izleme veya analiz ihtiyacı doğduğunda açılır.

### Client

- **İzle:** Eşleşmiş Server için canlı izleme ve kalite göstergeleri.
- **Bul:** QR tarama ve manuel IP:port bağlantı.
- **Bildirim:** Alert dinleme ve geçmiş yüzeyi.
- **Ayarlar:** Client tercih alanı.

Manuel bağlantı yerel HTTP `/status/public` üzerinden yapılır. Watch oturumu health için ayrı medya bağlantısı açmaz; mevcut video/audio/event pipeline callback’leri `ClientStreamHealthState` içine timestamp ve sayaç yazar. Client tarafında HTTPS/WSS fallback veya certificate fingerprint kontrolü yoktur.

---

## Güvenlik Modeli

MimiCam’in MVP güvenliği local ağ için sade tutulur:

1. Server yalnız pairing ekranı açıkken pairing nonce üretir.
2. QR payload token taşımaz; sadece tek kullanımlık `pairingNonce` taşır.
3. Nonce yaklaşık 10 dakika geçerlidir ve tek kullanımda tüketilir.
4. `/pair/confirm` başarılı olursa 256-bit random trusted token üretir.
5. Server token’ın hash’ini saklar; ham token loglanmaz.
6. Private endpointler `Authorization: Bearer <trustedToken>` ister.
7. `/session/start` kısa ömürlü `streamToken` üretir; bu token sadece `/video` ve `/audio` için query’de kullanılabilir.
8. Local network guard sadece private IPv4 blokları ve debug loopback adreslerine izin verir.

Limitler:

- 6. trusted pairing isteği `409` ve `MAX_TRUSTED_CLIENTS_REACHED` döner.
- 6. aktif watch oturumu `429` ve `MAX_ACTIVE_CLIENTS_REACHED` döner.
- Aynı client tekrar `/session/start` çağırırsa slot sayısı artmaz; sadece yeni `streamToken` alır.
- `/session/stop`, stream response disconnect ve streamToken expiry aynı cleanup yolunu kullanır.
- Cleanup aktif slotu, kalite raporunu, stream connection sayacını ve ilgili stream tokenlarını temizler.

---

## QR Payload

QR payload kısa ve local HTTP/WS odaklıdır:

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

Payload içinde certificate fingerprint, TLS mode, `https` veya `wss` alanı bulunmaz.

---

## Medya Kalitesi

Server tek latest JPEG üretir; her Client kendi hızında okur. Client başına frame queue veya ayrı encode yoktur. Yavaş client frame kaçırır, backlog birikmez. Audio stream de aynı prensiple busy/flush guard kullanır; yavaş client için PCM chunk kuyruğu büyütülmez.

| Durum | Çözünürlük | FPS | JPEG | Öncelik |
| --- | ---: | ---: | ---: | --- |
| Normal | 854×480 | 8 | 52 | Video + audio + event |
| Weak | 640×360 | 5 | 42 | Audio/event öncelikli |
| Critical | 426×240 | 2 | 36 | Audio/event öncelikli |
| Survival | 426×240 snapshot | 1 | 36 | Audio/event |

Aktif client sayısı da kaliteyi sınırlar:

- **1 client:** Ağ raporuna göre normal/weak/critical.
- **2–3 client:** En fazla 640×360, 5fps, JPEG 42.
- **4–5 client:** 426×240 veya çok düşük 640×360, 2–4fps, JPEG 36–40.

Client `ClientStreamHealthState` ile video frame gap, audio gap, WebSocket disconnect/reconnect, stream timeout ve watchActive sinyallerini yalnız bellek içi state olarak toplar. Health ölçümü ikinci streamToken, ikinci stream slotu veya ekstra bandwidth oluşturmaz. Payload geriye uyumludur; `skippedFrames`, `skippedVideoFrames` ve `skippedAudioChunks` yoksa `0` kabul edilir.

Server kaliteyi `MediaQualitySelector` + `UtilityBasedProfileSelector` ile seçer. Fayda hesabı görsel kaliteyi; video/audio gap, audio underrun, WS reconnect/failure, backpressure skip ve client load cezalarıyla dengeler. Kötü sinyalde kalite hızlı düşer; yükseliş için en az 30 saniye stabil metrik gerekir ve yalnız tek kademe yükselir.

Ek bant genişliği kontrolü:

- `FrameBudgetManager` motion düşükken FPS’i azaltır; ağ critical veya 4–5 client varsa audio öncelikli 1–2 FPS seçer.
- `JpegByteBudgetController` profil başına byte/s hedefini izler ve profil düşmeden önce JPEG kalitesini 32–58 aralığında P-denetleyiciyle ayarlar.
- Audio flush busy ise aynı client’ın video frame’i skip edilir; audio/event stream video’dan önceliklidir.
- Bildirimler `EpisodeBasedNotificationAggregator` ile kısa ses yükselmesi, doğrulanmış/uzayan ağlama ve hareket bağlamını tek `baby_event` payload’ında toplar.

---

## Endpointler

| Endpoint | Amaç | Auth |
| --- | --- | --- |
| `GET /status/public` | Pairing açıkken public nonce/capability | Local ağ |
| `POST /pair/confirm` | Nonce ile trusted token alma | Local ağ + nonce |
| `POST /auth/renew` | Trusted token yenileme | Bearer token |
| `POST /session/start` | Watch slotu açma, streamToken alma | Bearer token |
| `POST /session/stop` | Watch slotu kapatma | Bearer token |
| `POST /quality/report` | Client kalite raporu | Bearer token |
| `GET /status` | Private server durumu | Bearer token |
| `GET /video` | MJPEG stream | Bearer token veya streamToken |
| `GET /audio` | PCM16LE/WAV stream | Bearer token veya streamToken |
| `GET /ws/events` | Alert/event WebSocket | Bearer token |

`streamToken` yalnız medya endpointlerinde geçerlidir. `/status`, `/quality/report`, `/auth/renew` ve `/ws/events` için Bearer trusted token gerekir; trusted token query parametresi olarak kabul edilmez.

`/quality/report` payload’ı geriye uyumludur: eski `tier/rttMs` alanları kabul edilir, yeni health alanları eksikse güvenli default kullanılır. Server body’deki `clientId` yerine Bearer token’dan çözülen clientId’yi esas alır.

---

## Proje Yapısı

```text
lib/
├── app/                    # bootstrap, role resolver, permission policy
├── core/
│   ├── media/              # adaptive profile, classifier, quality tracker
│   ├── network/            # local network guard
│   ├── protocol/           # pairing payload/session, endpoint builder
│   └── security/           # random token + HTTP/WS transport config
├── analysis/               # audio/video analysis and alert engine
├── features/
│   ├── client/             # pairing, watch, alerts, client UI/runtime
│   ├── server/             # server UI/runtime, pairing token service
│   └── shared/             # shared presentation primitives
└── services/               # MimiCamServer facade, config, server policies, platform adapters
```

`lib/services/server/` altında streaming refactor parçaları bulunur:

- `ActiveClientRegistry`: aktif watch client, streamToken ve kalite raporu lifecycle’ı.
- `RequestAuthGuard`: Bearer trusted token doğrulama.
- `MediaQualitySelector`: cihaz/ağ/client yükünden profil seçimi.
- `UtilityBasedProfileSelector`: kalite raporu + backpressure + client load fayda hesabı.
- `FrameBudgetManager`: motion/cry/network/client yüküne göre hedef FPS.
- `JpegByteBudgetController`: profil başına JPEG byte/s ve kalite denetimi.
- `StreamBackpressureGate`: video/audio stream için busy-skip kontrolü.

Client media tarafında:

- `ClientStreamHealthState`: video/audio/event health snapshot ve quality payload üretimi.
- `NetworkQualityMonitor`: RTT/status probe ile health snapshot birleştirip `/quality/report` gönderimi.
- `StreamSessionController`: session lifecycle, watch active state ve streamToken saklama.

---

## Geliştirme

```bash
flutter pub get
dart format .
flutter analyze
flutter test
```

Odak testler:

- `test/core/security/local_network_guard_test.dart`
- `test/features/server/pairing_mode_test.dart`
- `test/features/server/trusted_client_limit_test.dart`
- `test/features/server/active_client_limit_test.dart`
- `test/features/server/token_auth_test.dart`
- `test/services/server/media_backpressure_test.dart`
- `test/services/server/active_client_registry_test.dart`
- `test/services/server/media_quality_selector_test.dart`
- `test/services/server/stream_backpressure_gate_test.dart`
- `test/features/client/client_stream_health_state_test.dart`
- `test/features/client/network_quality_monitor_test.dart`
- `test/features/client/stream_session_controller_test.dart`
- `test/services/server/backpressure_memory_test.dart`
- `test/services/server/active_client_load_quality_test.dart`
- `test/core/media/adaptive_media_weak_wifi_test.dart`

Manuel cihaz performans kontrolü:

```bash
flutter install -d <device-id> --uninstall-only
flutter run -d <device-id> --profile --trace-startup
```

LG G6 (`LG H870`, Android 9) üzerinde son profile startup kontrolünde first frame `465ms`, rasterized first frame `861ms` ölçüldü. Aynı kontrolde app test için kurulup işlem sonunda tekrar kaldırıldı.

---

## Kapsam Dışı

- HTTPS/WSS, certificate pinning, Keystore/Keychain cert rotation.
- Cloud relay, internet üzerinden erişim, hesap sistemi, OAuth.
- UDP discovery ve otomatik LAN broadcast keşfi.
- Client başına ayrı video encode pipeline’ı.
