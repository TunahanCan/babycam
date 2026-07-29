# MiuCam Full Code Review — 2026-07-10

## Kapsam ve yöntem

Bu inceleme `lib/`, native Android/iOS media köprüleri, HTTP/WS/WebRTC signaling
protokolü ve `test/` ağacını kapsar. Doküman güncellenirken kaynak boyutu:

- 241 Dart dosyası
- `lib/`: 33.824 satır
- `test/`: 12.373 satır
- `lib/ + test/`: 46.197 satır

Statik analiz, unit/widget/integration testleri, sentetik AOT/JIT benchmark,
socket yaşam döngüsü testleri ve medya hot-path incelemesi birlikte
kullanılmıştır. Benchmark gerçek cihaz kamera decode/render gecikmesi değildir;
macOS üzerinde algoritmik CPU ve bellek tabanı verir.

Bu sayılar docs satırlarını içermez ve uygulama değişmeye devam ederse yeniden
üretilmelidir.

## Sonuç özeti

En kritik veri doğruluğu, auth bypass, sınırsız kuyruk/buffer ve hot-path bellek
sorunları giderildi. Mimariyi bir defada yeniden yazmak yerine davranışı koruyan
küçük pattern sınırları eklendi.

İkinci uygulama geçişi background/media ownership, WebRTC pilotu, discovery,
thermal policy, room audio ve purchase verification yüzeylerini ekledi:

| Alan | Uygulanan sınır | Dürüst kapsam |
| --- | --- | --- |
| Kamera/mikrofon | `MediaRuntimeController` video/audio demand'i bağımsız ve serialized reconcile ediyor | Legacy MJPEG/WAV ve analyzer yolu; WebRTC track'leri gateway'e ait |
| Android background | Mevcut Flutter engine foreground service tarafından sahipleniliyor; exact camera/mic demand notification ve Wi-Fi lock'a gidiyor | Service `START_NOT_STICKY`; process death sonrası görünmez capture recovery yok |
| iOS background | Background'da controlled media pause, foreground-active'de retained-demand recovery | iOS background camera destekleniyor iddiası yok |
| Native audio | Android focus/noisy/device events; iOS interruption/route/media-reset handling | Fiziksel call/route test matrisi henüz sonuç üretmedi |
| Telemetry | Bounded counters ve p50/p95/p99 capture/codec/send/receive/playout dağılımları | Cross-device clock estimate ölçüm aracıdır, mutlak senkronizasyon değildir |
| Resource governor | Thermal, low-power, battery, encode, client-load ve backpressure ile normal/constrained/survival/audio-first profil | Release eşikleri fiziksel soak testinde doğrulanmalı |
| WebRTC | Opt-in, tek peer H.264+Opus; auth'lu HTTP signaling ve MJPEG/WAV fallback | Host ICE/LAN pilotu; TURN/relay, multi-peer ve production kanıtı yok |
| Discovery | `_miucam._tcp` DNS-SD/NSD, IPv4/IPv6 resolve; dual-stack bind denemesi | QR/manual adres fallback korunuyor |
| Room features | Procedural comfort PCM ve parent-to-room talk audio native sink'e yazılıyor | Talk video/parent overlay yok; acoustic echo fiziksel test bekliyor |
| Purchase | Wrong product/source/state/evidence fail-closed; yalnız SHA-256 fingerprint metadata tutuluyor | Apple/Google server-side receipt authenticity doğrulaması yok |
| Server parçalama | Test endpoint part extension, feature facade, room-audio coordinator, WebRTC gateway ve governor sınırları | `MiuCamServer` hâlâ büyük HTTP composition host |

Kullanıcı kapsamı gereği public pairing nonce redesign, merkezi body limitleri,
socket lease/revoke ve secure session ticket paketi bilinçli olarak uygulanmadı.
Bu maddeler aşağıda kalan güvenlik riski olarak tutulur.

| Öncelik | Bulgu | Uygulanan düzeltme |
| --- | --- | --- |
| Kritik | Alert aynı olay için JSON ve legacy binary olarak iki kez gidiyordu | Legacy packet feature flag arkasına alındı; varsayılan tek JSON event |
| Kritik | Bearer token media endpointinde stream token kontrolünü bypass edebiliyordu | `/video` ve `/audio` için geçerli, kısa ömürlü stream token zorunlu |
| Kritik | `session/stop` açık media socketlerini bırakabiliyordu | Client video/audio socketleri kapatılıp registry atomik olarak temizleniyor |
| Kritik | Server yeniden yaratılınca trusted client kaydı kayboluyordu | Repository pattern; yalnız SHA-256 token hash'i ve metadata kalıcı |
| Yüksek | MJPEG parser her fragmentte tüm buffer'ı yeniden birleştiriyordu | Bounded incremental state machine ve tek body allocation |
| Yüksek | `Image.memory` canlı kareleri global 100 MiB `ImageCache` içine taşıyordu | Cache dışı `ui.Image` decode, 1 active + 1 latest queue, explicit dispose |
| Yüksek | Kamera tam sensör çözünürlüğünde JPEG üretiyordu | Profil boyutuna aspect-ratio koruyarak downscale, JPEG 4:2:0, kopya azaltma |
| Yüksek | Yavaş MJPEG client flush işlemi sonsuza kadar bekleyebiliyordu | 300 ms bounded flush timeout ve client detach |
| Yüksek | Backpressure aggregate metriği client sırasına göre değişiyordu | Worst-client/max write latency; sıra bağımsız seçim |
| Yüksek | Mikrofon `start/stop` yarışında geç stream aktif kalabiliyordu | Single-flight start + generation ownership + idempotent dispose |
| Yüksek | WAV header buffer'ı sınırsız ve tekrar kopyalıydı | 64 KiB bounded incremental parser; PCM16/rate/channel doğrulaması |
| Orta | Üç client loop ayrı retry formülü taşıyordu | Strategy pattern `RetryPolicy`; exponential cap ve injectable jitter |
| Orta | Quality monitor aktif watch sırasında her saniye GET+POST yapıyordu | Stable durumda 4 sn POST throttle; tier kötüleşince immediate report |
| Orta | Çoklu status/report platform battery çağrılarını çoğaltıyordu | Decorator pattern TTL cache + in-flight request coalescing |
| Orta | Audio jitter queue head silme O(n) idi | `ListQueue` ile O(1) head/tail işlemleri |
| Orta | Router her istekte route listesi/closure üretiyordu | Constructor'da immutable route registry ve unknown path için 404 |
| Orta | Local preview varken remote session bitişi runtime'ı idle gösteriyordu | Phase hesabı tüm media sahiplerini dikkate alıyor |

## Uygulanan pattern sınırları

- **Repository:** `TrustedClientRepository`; kalıcı ve in-memory adapter.
- **Strategy:** `RetryPolicy`; alert, audio ve video reconnect aynı politika.
- **State machine:** MJPEG ve WAV incremental parse durumları.
- **Latest-only mailbox:** kamera encode, server client writer ve client decode
  tarafında eski iş birikmiyor.
- **Worker:** JPEG dönüşümü kalıcı isolate üzerinde, ana isolate dışında.
- **Decorator:** `CachedBatterySnapshotProvider` platform okumasını cache ve
  coalesce ediyor.
- **Serialized lifecycle/ownership:** media profile apply queue, mikrofon
  generation guard ve explicit socket cleanup.
- **Immutable registry:** HTTP route tablosu bir kez kuruluyor.
- **Demand reconciler:** `MediaRuntimeController` bağımsız video/audio resource
  transition'larını sıraya alıyor.
- **Facade:** `BabyMonitorFeatureController` room feature business/device
  davranışını HTTP handler'lardan ayırıyor.
- **Coordinator:** `RoomAudioCoordinator` comfort ve talk için tek native sink
  sahipliği ve öncelik kuralını uyguluyor.
- **Strategy:** `BroadcastPurchaseVerifier` local store-envelope doğrulamasının
  server verifier ile değiştirilebilmesini sağlıyor.
- **Gateway:** WebRTC peer/track ve DNS-SD advertise/browser platform
  bağımlılıklarını composition sınırlarına taşıyor.
- **Bounded metrics collector:** session telemetry uzun runtime'da sabit sample
  tavanı ile percentile snapshot üretiyor.

## Performans ölçümleri

Komutlar:

```bash
dart run tool/benchmarks/media_pipeline_benchmark.dart
dart compile exe tool/benchmarks/media_pipeline_benchmark.dart \
  -o /tmp/miucam_media_benchmark
/usr/bin/time -l /tmp/miucam_media_benchmark
```

Son AOT ölçümü:

| İş | Girdi | Ortalama |
| --- | --- | ---: |
| Audio analysis | 1.000 × 20 ms, 16 kHz mono PCM chunk | 49,375 µs/chunk |
| Motion analysis | 1.000 × 640×480 luma frame | 24,815 µs/frame |
| MJPEG incremental parse | 30 × 128 KiB frame, 257-byte fragment | 50,5 µs/frame |

MJPEG parser JIT ölçümü eski birleştirmeli uygulamada 2.534,4 µs/frame iken
307,57 µs/frame oldu: yaklaşık **8,24× hızlanma**. AOT proses maksimum RSS
24.002.560 byte (~22,89 MiB), peak footprint 13.992.440 byte (~13,34 MiB).

Kontrol düzlemi yük modeli, beş aktif client ve saniyelik health GET için:

- önce: yaklaşık 10 HTTP request/s (5 GET + 5 POST),
- şimdi stabil tier: yaklaşık 6,25 HTTP request/s (5 GET + 1,25 POST),
- azalma: **%37,5**; tier kötüleşmesi throttle beklemez.

Server battery platform okuması en fazla 15 saniyede bir, client battery okuması
en fazla 30 saniyede bir yapılır; eşzamanlı talepler tek future'da birleşir.

## İşletim bütçeleri

Kodla enforce edilen bütçeler:

| Ölçüt | Bütçe |
| --- | ---: |
| Server audio client queue | 160 ms |
| Client adaptive audio playout | 60–220 ms |
| Client Dart audio buffer hard cap | 320 ms |
| Server media flush timeout | 300 ms |
| Client video decode queue | 1 active + 1 latest pending |
| MJPEG header | 16 KiB |
| MJPEG frame | 2 MiB |
| WAV header | 64 KiB |
| Stable quality POST | en fazla 1 / 4 sn / client |
| Session telemetry sample window | metric başına 1.024 örnek |
| WebRTC pilot peer count | 1 |
| Talk/comfort PCM frame | 20 ms |

Gerçek cihaz kabul hedefleri henüz ölçülmüş sonuç değildir; network shaping
testinde doğrulanmalıdır:

- LAN video glass-to-glass: p50 < 300 ms, p95 < 700 ms
- audio underrun: stabil LAN'da < 1/dakika
- reconnect: bağlantı geri geldikten sonra < 2 sn
- sürdürülebilir memory: 15 dakika watch boyunca artan trend olmaması
- skipped video: stabil LAN'da < %5

Tam cihaz/OS/network/thermal senaryoları ve release gate'leri
[`physical_device_test_matrix.md`](physical_device_test_matrix.md) içindedir.
`tool/benchmarks/device_soak_harness.dart` authenticated `/status` JSONL kaydı üretir;
matris dokümanının varlığı fiziksel sonuçların çalıştırıldığı anlamına gelmez.

## Kalan riskler ve sonraki refactor sırası

### P1

1. `MiuCamServer` yaklaşık 2.500 satırlık HTTP composition host olmaya devam
   ediyor. Diagnostics part extension, feature facade, room-audio coordinator,
   WebRTC gateway ve resource governor ayrıldı; sonraki güvenli adım pairing,
   session ve quality route controller'larını çıkarmaktır.
2. `ServerRuntime` aktif session seti ile `ActiveClientRegistry` ayrı state
   tutuyor. Tek `ServerSessionCoordinator` altında serial start/stop ownership
   kurulmalı.
3. HTTP/WS LAN üzerinde cleartext. Tokenlar güçlü ve route auth sıkı olsa da
   aynı ağdaki aktif saldırgana karşı TLS yok. WebRTC pilot media için DTLS-SRTP
   getirir, fakat control/signaling HTTP kalır ve pilot TURN/relay içermez.
4. MJPEG + WAV bağımsız TCP bağlantıları retransmission sırasında head-of-line
   blocking ve kesin A/V sync problemi taşır. Mevcut çözüm bunu bounded ve
   gözlenebilir yapar; WebRTC pilotu riski azaltan deneysel yoldur, default
   fallback davranışını ortadan kaldırmaz.
5. WebRTC gateway kendi `getUserMedia` track'lerini doğrudan sahiplenir. Session
   demand'i native foreground-service sözleşmesine birleştirilir, legacy capture
   WebRTC boyunca askıya alınır ve iOS platform pause'u peer track'lerini kapatır.
   Pilot track'leri legacy motion/cry analiz hattını beslemez; codec, thermal ve
   background davranışı fiziksel cihazda ayrıca kanıtlanmalıdır.

### P2

1. Kullanıcı kararıyla güvenlik paketinin bu geçişte kapsam dışında kalan
   parçaları: public pairing nonce redesign, merkezi JSON body byte limitleri,
   socket lease/revoke ve secure session ticket. Bunlar yapılmış sayılmamalı.
2. DNS-SD/NSD discovery adres bulmayı çözüyor; discovery sonucu, QR/manual IP ve
   status probe timeout/cancel ownership'i ileride tek client discovery facade
   altında sadeleştirilebilir.
3. `ActiveClientRegistry` session/token/socket durumları tek immutable
   session record modeline taşınmalı; expiry ve reconnect aynı transition
   tablosundan geçmeli.
4. Global bounded E2E telemetry eklendi; `MjpegStreamService` ve
   `WavAudioStreamService` transport metriklerinin session kapanışında tek
   client-scoped snapshot'a bağlanması hâlâ eksik.
5. Async widget/runtime dispose işlemleri join edilebilir controller sahibi
   üzerinden tamamlanmalı; fire-and-forget yalnız telemetry için kalmalı.
6. Store payload verification fail-closed olsa da gerçek receipt/token
   authenticity için Apple/Google server-side verifier gereklidir.

### P3

1. `server_home_screen.dart`, `watch_screen.dart` ve `client_home_screen.dart`
   1.500–1.900 satır aralığında. Presentation state, commands ve section
   widget'ları ayrılmalı.
2. Localization catalog üretim/asset pipeline'ına taşınmalı; elle tutulan 3.000+
   satırlık katalog review yüzeyini büyütüyor.
3. Role isolation testi gerçek `AppBootstrap` widget ağacını ve composition
   root çağrılarını çalıştıracak hale getirilmeli.
4. Procedural comfort audio ürün kalitesinde mastered asset değildir; talk echo
   cancellation/feedback ve output-route davranışı fiziksel cihazlarda
   ölçülmelidir.

## Doğrulama kapısı

- `flutter analyze`: 0 issue
- Full `flutter test`: 387/387 test geçti
- Full coverage koşusu: 9.458 / 12.564 satır = **%75,28**
- iOS simulator build: başarılı (`build/ios/iphonesimulator/Runner.app`)
- Android build: bu workstation'da Android SDK olmadan çalıştırılamadı

Android SDK bulunan bir makinede Android build ve physical-device matrix ayrıca
tamamlanmalıdır. Yeni odak test yüzeyi:

```bash
flutter test test/features/server/media_runtime_controller_test.dart
flutter test test/services/platform/platform_runtime_contract_test.dart
flutter test test/services/server/media_resource_governor_test.dart
flutter test test/core/media/media_session_telemetry_test.dart
flutter test test/features/server/webrtc_signaling_endpoints_test.dart
flutter test test/features/client/stream_session_controller_test.dart
flutter test test/services/discovery/miucam_service_discovery_test.dart
flutter test test/services/server/room_audio_coordinator_test.dart
flutter test test/features/client/client_room_controls_test.dart
flutter test test/services/monetization/broadcast_access_service_test.dart
```

Algoritmik kararların birincil kaynakları ve transport sınırları
[`media_transport_algorithms.md`](media_transport_algorithms.md) içinde.
