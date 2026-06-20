# MimiCam

MimiCam, aynı Wi‑Fi/LAN içindeki iki veya daha fazla telefonu yerel bebek kamerası sistemine dönüştüren Flutter uygulamasıdır. Tek uygulama iki ayrı rol taşır:

- **Server / Bebek Odası:** Kamera, mikrofon, analiz, yayın ve eşleşme biletini yönetir.
- **Client / Ebeveyn:** QR veya manuel IP ile eşleşir, canlı izleme oturumunu açar ve uyarıları takip eder.

MimiCam cloud hesap, abonelik, internet relay, UDP discovery veya Telegram otomasyonu içermez. Yayın, tokenlar, uyarılar ve kalite raporları yerel ağ içinde kalır.

---

## Ürün Akışı

```text
Uygulama açılır
  ↓
Cihaz rolü seçilir: Server veya Client
  ↓
Server QR/IP bağlantı bileti üretir
  ↓
Client QR tarar veya IP:port girer
  ↓
Client eşleşir, uyarıları dinler ve canlı izleme başlatabilir
```

Rol seçimi cihazda saklanır. Rol değişimi sağ üstteki küçük rol rozetiyle yapılır; Server’dan Client’a geçerken aktif Server runtime kapatılır ve pairing session temizlenir.

---

## Öne Çıkanlar

| Alan | Durum |
| --- | --- |
| Rol izolasyonu | Server ve Client graph’ları aynı anda kurulmaz. |
| Eşleşme | QR birincil akıştır; manuel IP:port fallback korunur. |
| Transport | Release varsayılanı self-signed HTTPS/WSS + SHA-256 certificate pinning’dir. |
| Debug esnekliği | HTTP/WS yalnızca debug geliştirici konfigürasyonunda açılabilir. |
| Video | MJPEG stream, tek JPEG encode + çoklu client dağıtımı. |
| Ses | PCM16LE/WAV stream ve ağlama analizi. |
| Uyarılar | Hareket/ağlama analizi, cooldown ve lokalize ebeveyn mesajları. |
| Adaptif kalite | Yayın 480p altına düşmez; FPS/JPEG kalite ağ ve client yüküne göre ayarlanır. |
| Çoklu client | Aynı Server’a birden fazla ebeveyn cihazı bağlanabilir. |
| UI dayanıklılığı | Kompakt ekran overflow testleri ve QR panel sınır testleri vardır. |

---

## Ekranlar

### Server / Bebek Odası

Server modu yalnızca bebek odası sorumluluklarını gösterir:

- **Yayın:** Kamera önizleme, medya profili, analiz özeti ve yayın durdurma.
- **QR/IP:** Responsive QR bileti, QR yenileme ve adres kopyalama.
- **Servis:** Kamera, mikrofon, analiz ve bağlantı durumları.
- **Ayarlar:** Hareket/ağlama eşikleri, minimum süreler ve cooldown.

Kompakt ekranlarda uzun HTTPS QR payload’ı ham metin olarak gösterilmez; QR paneli ekrana sığacak şekilde sınırlandırılır ve kopyalama aksiyonu korunur.

### Client / Ebeveyn

Client modu yalnızca ebeveyn akışlarını gösterir:

- **İzle:** Eşleşmiş Server için canlı izleme, kalite ve hızlı aksiyonlar.
- **Bul:** QR tarama ve manuel IP:port bağlantı.
- **Bildirim:** Bebeğin son durumu ve uyarı geçmişi yüzeyi.
- **Ayarlar:** Client tarafı tercih alanı.

Client modunda Server kamera/mikrofon yönetimi, QR üretme veya yayın durdurma kontrolleri bulunmaz.

---

## Güvenlik Modeli

MimiCam’in güvenlik modeli yerel ağ için basit ve açık tutulur:

1. Server ilk güvenli açılışta RSA 2048 self-signed sertifika üretir.
2. Sertifika ve private key application support directory altında `mimicam_tls/` dizininde saklanır.
3. QR payload aktif sertifikanın SHA-256 DER fingerprint’ini taşır.
4. Client, QR veya manuel HTTPS `/status/public` keşfiyle fingerprint alır.
5. Client HTTPS/WSS bağlantılarında sertifikayı host + port + fingerprint ile pin’ler.
6. Fingerprint uyuşmazsa pairing ve stream bağlantıları reddedilir.

Korunan endpointler Bearer token ister. Pairing sonrası Server 256-bit trusted token üretir, düz metin token saklamaz; token hash saklar. Token lifetime 60 gündür ve son 7 günde yenilenebilir.

Debug dışında düz HTTP/WS açık kalmamalıdır. `TransportSecurityConfig.insecureHttpDevOnly` profile/release benzeri modlarda `StateError` fırlatır.

---

## Manuel IP Bağlantısı

Manuel IP hâlâ desteklenir, ama HTTPS sonrası davranışı değişmiştir:

```text
Client IP:port girer
  ↓
HTTPS /status/public çağrılır
  ↓
Self-signed cert fingerprint keşfedilir
  ↓
Payload oluşturulur
  ↓
/pair/confirm pinned HTTPS ile çağrılır
```

Release’te HTTP fallback yoktur. Debug’da geliştirme kolaylığı için HTTP fallback denenebilir.

---

## Medya ve Performans

MimiCam eski ve modern cihazları aynı kod yolu içinde destekler. Medya kalitesi üç sinyale göre belirlenir:

- **Cihaz kapasitesi:** `legacy`, `balanced`, `modern`
- **Ağ kalitesi:** Client RTT/failure ölçümü ve `/quality/report`
- **Aktif izleyici sayısı:** Aynı anda canlı izleme yapan Client sayısı

Güncel kurallar:

- Yayın profili 480p altına düşmez.
- Modern cihaz varsayılanı 720p olabilir.
- Zayıf ağda FPS/JPEG kalite düşer, ses önceliği korunur.
- 4+ aktif izleyicide ortak yayın 480p ve daha düşük FPS/JPEG kaliteye çekilir.
- Video client yoksa JPEG encode yapılmaz.
- Her client için ayrı frame encode edilmez; tek JPEG tüm MJPEG clientlara dağıtılır.
- Yavaş client’a yeni frame yazmak yerine frame skip/backpressure uygulanır.

---

## Analiz ve Uyarılar

Server tarafındaki analiz boru hatları:

```text
CameraImage → LumaDownsampler → MotionAnalyzerV2 → AlertEngine
PCM audio  → GoertzelBandAnalyzer → CryAudioAnalyzerV2 → AlertEngine
```

`AlertEngine`, skorları cooldown politikasıyla birleştirir ve lokalize ebeveyn mesajı üretir. Mesajlar tanı koymaz; ebeveyne pratik kontrol sinyali verir.

---

## Teknik Bileşenler

| Katman | Ana dosyalar |
| --- | --- |
| Bootstrap / rol | `lib/app/*` |
| Server runtime | `lib/features/server/*`, `lib/services/mimicam_server.dart` |
| Client runtime | `lib/features/client/*` |
| Protokol | `lib/core/protocol/*` |
| Güvenlik | `lib/core/security/*` |
| Medya adaptasyonu | `lib/core/media/*` |
| Analiz | `lib/analysis/*` |
| Lokalizasyon | `lib/l10n/app_strings.dart` |
| Platform servisleri | `lib/services/platform/*` |

Detaylı mimari için `ARCHITECT.md` dosyasına bakın.

---

## Kurulum

Gereksinimler:

- Flutter SDK
- Android Studio veya Xcode
- Aynı LAN üzerinde en az iki test cihazı
- Kamera, mikrofon, bildirim ve Android battery optimization izinleri

Komutlar:

```bash
flutter pub get
flutter run
```

Debug APK:

```bash
flutter build apk --debug
```

---

## Kalite Kontrolleri

Standart doğrulama:

```bash
dart format .
flutter analyze
flutter test
```

Öne çıkan test alanları:

- `test/app/role_isolation_test.dart`
- `test/app/role_permission_coordinator_test.dart`
- `test/features/hard_split_navigation_test.dart`
- `test/features/performance/screen_render_budget_test.dart`
- `test/core/security/*`
- `test/core/pairing_payload_test.dart`
- `test/core/media/adaptive_media_profile_test.dart`
- `test/core/media/client_quality_tracker_test.dart`
- `test/features/client/network_quality_monitor_test.dart`
- `test/analysis/audio/*`
- `test/analysis/video/*`
- `test/analysis/alert/*`
- `test/l10n/app_strings_test.dart`

---

## Kapsam Dışı

MimiCam bilinçli olarak şunları içermez:

- Cloud backend
- İnternet üzerinden yayın
- Hesap veya abonelik
- UDP discovery/broadcast
- Telegram otomasyonu
- STUN/TURN relay zorunluluğu
- Otomatik üçüncü kişi paylaşımı

---

## Yakın Yol Haritası

- TLS private key saklamasını secure storage arkasına taşıma.
- Native Android foreground service kanalını üretim seviyesine tamamlama.
- iOS yerel ağ/lifecycle/background davranışlarını netleştirme.
- Token revoke/renew için kullanıcı arayüzleri.
- Alert history ve filtreleme deneyimini olgunlaştırma.
- Native video/audio player entegrasyonu.
- Uzun vadede WebRTC/H264 yayın katmanı.
