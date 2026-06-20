# MimiCam — Yerel Ağda Güvenli Bebek Kamerası

**MimiCam**, aynı Wi‑Fi ağı içindeki telefon veya tabletleri bebek kamerasına dönüştüren Flutter uygulamasıdır. Bir cihaz **Server / Bebek Odası** olarak kamera, mikrofon, analiz ve yayın tarafını yönetir; bir veya daha fazla **Client / Ebeveyn** cihaz eşleşir, canlı izleme oturumunu açar ve uyarıları takip eder.

Cloud hesabı, abonelik, internet relay, UDP discovery veya Telegram otomasyonu yoktur. Kurulum QR veya manuel IP ile yapılır; yayın ve uyarılar yerel ağda kalır.

---

## Güncel Ürün Akışı

```text
Uygulamayı aç
  ↓
Bu cihaz Server mı Client mı seç
  ↓
Server cihazda QR/IP bağlantı bileti üret
  ↓
Client cihazda QR okut veya IP:port gir
  ↓
Client İzle ekranından canlı izleme oturumunu aç
```

Rol seçimi ilk açılışta yapılır ve cihazda saklanır. Günlük kullanımda rol değiştirme öne çıkarılmaz; sağ üstteki küçük rol rozeti yalnızca gerekli olduğunda rol değiştirmeyi sağlar. Server’dan Client’a geçerken aktif server runtime onaydan sonra kapatılır.

---

## Temel Özellikler

| Alan | Açıklama |
| --- | --- |
| Kesin rol ayrımı | Server ve Client graph'ları aynı anda kurulmaz; seçilmeyen role ait servisler kapalı kalır. |
| QR + manuel IP eşleşme | Server QR/IP bileti üretir; Client QR tarar veya IP:port fallback kullanır. |
| Büyük okunabilir QR | Server QR/IP ekranındaki QR, küçük telefonların okuyabilmesi için responsive olarak büyür. |
| Yerel yayın | Video MJPEG, ses PCM/WAV stream olarak aynı LAN içinde aktarılır. |
| Çoklu ebeveyn cihazı | Eşleşmiş birden fazla Client aynı Server yayınına bağlanabilir; kalite ortak kapasiteye göre dengelenir. |
| Akıllı uyarılar | Hareket ve ağlama analizlerinden ebeveyne anlamlı, lokalize mesajlar üretilir. |
| Bildirim önceliği | Client tarafında Bildirim sekmesi bebeğin son durumunu ebeveyne hızlı gösterir. |
| Adaptif medya | Yayın 480p altına düşmez; cihaz gücü, ağ kalitesi ve aktif izleyici sayısına göre FPS/JPEG dengelenir. |
| Çok dil | Telefon dili algılanır; destek yoksa varsayılan İngilizce kullanılır. |
| Performans koruması | Tek encode + çoklu dağıtım, frame budget, yavaş client frame atlama ve ihtiyaç yokken encode etmeme politikaları kullanılır. |

---

## Roller ve Ekranlar

### Server / Bebek Odası

Server cihaz bebek odasında kalır ve yalnızca server özelliklerini gösterir:

- **Yayın:** Kamera önizleme, aktif medya profili, yayın durumu ve yayını durdur aksiyonu.
- **QR/IP:** Büyük QR, IP:port payload alanı, QR yenileme ve kopyalama.
- **Servis:** Kamera, mikrofon, analiz ve bağlantı servislerinin durumu.
- **Ayarlar:** Hareket/ağlama eşikleri, minimum süreler ve cooldown ayarları.

Server modunda QR tarama, ebeveyn geçmişi veya client bildirim ayarları görünmez.

### Client / Ebeveyn

Client cihaz ebeveynin elindedir ve yalnızca client özelliklerini gösterir:

- **İzle:** Eşleşmiş Server için canlı izleme oturumu, kalite durumu ve ebeveyn aksiyonları.
- **Bul:** QR tarama ve manuel IP:port ile eşleşme.
- **Bildirim:** Bebeğin son durumu ve ebeveyn için öncelikli uyarılar.
- **Ayarlar:** Client bildirim/ebeveyn tercihleri için alan.

Client modunda yayın durdurma, QR üretme, kamera/mikrofon server kontrolleri veya servis yönetimi görünmez.

---

## Güvenlik Modeli

İlk güven QR payload ile kurulur:

```text
serverDeviceId + certificateFingerprintSha256 + pairingNonce
```

Eşleşme sonrasında Client süreli token ile çalışır:

```text
trustedClientToken / sessionToken
```

Kurallar:

- Pairing nonce tek kullanımlık ve kısa ömürlüdür.
- Eşleşme sonrası 256-bit rastgele token üretilir.
- Server token düz metnini saklamaz; SHA-256 hash saklar.
- Token varsayılan olarak 60 gün geçerlidir ve son 7 günde yenilenebilir.
- Korunan endpointler Bearer token ister.
- Token loglara yazılmamalıdır.

Mevcut runtime yerel HTTP/WS ile çalışır; mimari production hedefi kalıcı self-signed TLS ve fingerprint pinning ile HTTPS/WSS’e taşınacak şekilde tasarlanmıştır.

---

## Medya ve Adaptasyon

MimiCam eski Android/iPhone cihazlarda da çalışabilmek için kaliteyi üç sinyale göre ayarlar: cihaz kapasitesi, aktif Client ağ raporları ve aynı anda izleyen cihaz sayısı. Güncel kural: **yayın profili 480p altına düşmez.**

1. **Cihaz kapasitesi**
   - `legacy`: 480p, düşük FPS, ses öncelikli.
   - `balanced`: 480p dengeli profil.
   - `modern`: 720p kalite profili.

2. **Ağ kalitesi**
   - Client `/status` ölçümü ve `/quality/report` ile RTT/failure bilgisini Server’a iletir.
   - Server aktif izleyen Client’lar arasındaki en zayıf güncel raporu baz alır; aktif olmayan cihazın eski raporu canlı kaliteyi düşürmez.
   - Zayıf ağda görüntü 480p kalır, FPS/JPEG düşer ve ses önceliği korunur.

3. **Aktif izleyici sayısı**
   - 2+ izleyicide modern 720p profil daha stabil FPS/JPEG aralığına çekilir.
   - 4+ izleyicide ortak yayın 480p, en fazla 8 FPS ve JPG 52 kaliteye iner.
   - Kritik/offline ağda yine 480p korunur; FPS 4’e kadar düşebilir.

Performans politikaları:

- Kamera frame’i her Client için ayrı ayrı encode edilmez; tek JPEG encode edilir ve tüm MJPEG clientlara dağıtılır.
- Yavaş bir Client’a önceki frame hâlâ yazılıyorsa yeni frame o Client için atlanır; Server tarafında frame kuyruğu şişmez.
- Video client yoksa JPEG encode yapılmaz.
- Frame işleme `MediaFrameBudget` ile sınırlandırılır.
- Kartlar ve QR gibi pahalı yüzeyler `RepaintBoundary` ile izole edilir.
- Kamera preset değişirse controller kontrollü yeniden başlatılır.

---

## Analiz ve Uyarılar

Server tarafındaki analiz boru hatları:

```text
CameraImage → LumaDownsampler → MotionAnalyzerV2 → AlertEngine
PCM audio  → GoertzelBandAnalyzer → CryAudioAnalyzerV2 → AlertEngine
```

`AlertEngine` skoru, cooldown politikasını ve lokalize ebeveyn mesajını üretir. Mesajlar tanı koymaz; “ses yükseldi”, “ağlama ihtimali arttı”, “odada hareket var” gibi ebeveynin kontrol etmesine yardım eden pratik bilgi verir.

---

## Dil Desteği

Desteklenen diller:

- İngilizce (`en`) — varsayılan fallback
- Türkçe (`tr`)
- Çince (`zh`)
- Hintçe (`hi`)
- İspanyolca (`es`)
- Fransızca (`fr`)

Tüm ana ekran yazıları, butonlar, rol metinleri, uyarı mesajları ve placeholder içerikler `AppStrings` üzerinden gelir. Flutter `Localizations` telefonun locale değerine göre doğru dili seçer; desteklenmeyen diller İngilizceye düşer.

---

## Teknik Özet

- Framework: Flutter / Dart
- Platform hedefi: Android ve iOS
- State/runtime: Role-aware composition root + runtime state stream
- Pairing: QR payload + nonce + HTTP pair confirm
- Yetkilendirme: Bearer trusted client token
- Video: MJPEG stream
- Ses: PCM16LE/WAV stream
- Event: JSON alert/status event DTO’ları
- Analiz: `MotionAnalyzerV2`, `CryAudioAnalyzerV2`, `AlertEngine`
- Saklama: `SharedPreferences` ile rol, ayar ve pairing session
- Lokalizasyon: `AppStrings` + Flutter localization delegates

Detaylı teknik açıklama için [`ARCHITECT.md`](ARCHITECT.md) dosyasına bakın.

---

## Geliştirici Kurulumu

Gereksinimler:

- Flutter SDK
- Android Studio veya Xcode
- Aynı Wi‑Fi/LAN üzerinde en az iki test cihazı
- Kamera, mikrofon, bildirim ve Android battery optimization izinleri

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

Debug APK:

```bash
flutter build apk --debug
```

---

## Test Kapsamı

Repo; rol izolasyonu, permission policy, pairing, runtime lifecycle, network quality, adaptive profile, analiz, alert, localization, ekran overflow ve performans bütçesi testlerini içerir.

Öne çıkan test alanları:

- `test/app/role_isolation_test.dart`
- `test/app/role_permission_coordinator_test.dart`
- `test/features/hard_split_navigation_test.dart`
- `test/features/performance/screen_render_budget_test.dart`
- `test/core/media/adaptive_media_profile_test.dart`
- `test/core/media/client_quality_tracker_test.dart`
- `test/features/client/network_quality_monitor_test.dart`
- `test/l10n/app_strings_test.dart`
- `test/analysis/audio/*`
- `test/analysis/video/*`
- `test/analysis/alert/*`

---

## Yol Haritası

- Kalıcı self-signed TLS certificate üretimi ve pinning akışı.
- Native Android foreground service kanalının tamamlanması.
- iOS lifecycle ve yerel ağ izin metinlerinin olgunlaştırılması.
- Token revoke/renew kullanıcı arayüzleri.
- Daha zengin alert history ve manuel paylaşım deneyimi.
- Native video/audio player entegrasyonu ve uzun vadede WebRTC/H264 yayın katmanı.

---

## MimiCam Ne Değildir?

MimiCam bir cloud kamera, internetten izleme servisi veya abonelik ürünü değildir. Bilinçli olarak şu kapsam dışıdır:

- Cloud backend
- İnternete yayın
- UDP discovery
- Telegram otomasyonu
- WebRTC relay/STUN/TURN zorunluluğu
- İnternet üzerinden otomatik üçüncü kişi paylaşımı
- Hesap veya abonelik zorunluluğu

Odak net: **aynı ağda, QR/IP ile eşleşen bir Server ve yetkili Client cihazlar arasında güvenli, anlaşılır bebek izleme deneyimi.**
