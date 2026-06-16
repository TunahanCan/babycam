# MimiCam — İnternetsiz, Güvenli ve Yerel Bebek Kamerası

**MimiCam**, evinizdeki iki telefonu ya da tableti saniyeler içinde güvenli bir bebek kamerasına dönüştüren Flutter uygulamasıdır. Bir cihaz **Bebek Odası Cihazı** olur; kamera, mikrofon ve akıllı uyarıları yönetir. Diğer cihaz **Ebeveyn Cihazı** olur; canlı görüntüyü, sesi ve uyarıları aynı Wi‑Fi ağı içinde takip eder.

Cloud hesabı yok. Abonelik yok. İnternete yayın yok. MimiCam, ebeveynlerin ihtiyaç duyduğu temel şeyi yapar: **bebek odasını yerel ağda, kontrollü ve güvenli şekilde izletir.**

---

## Neden MimiCam?

- **Aynı Wi‑Fi içinde çalışır:** Video, ses ve uyarılar ev ağınızdan çıkmadan cihazlar arasında akar.
- **QR ile kolay kurulum:** Bebek odasındaki cihaz QR üretir; ebeveyn cihazı okutur ve güvenli eşleşme tamamlanır.
- **Rol bazlı güvenli tasarım:** Server ve client görevleri kesin ayrılır; seçilmeyen role ait servisler çalıştırılmaz.
- **60 günlük güvenilir cihaz oturumu:** Eşleşen ebeveyn cihazı trusted token ile tekrar tekrar QR okutmak zorunda kalmaz.
- **Canlı izleme ve uyarılar:** Video, ses, hareket ve ağlama algılama akışları tek uygulama içinde yönetilir.
- **Kaynak dostu çalışma:** Kamera, mikrofon ve analiz bileşenleri yalnızca ihtiyaç olduğunda açılır.
- **Manuel paylaşım kontrolü:** Uyarı paylaşımı otomatik relay değildir; kullanıcı aksiyonuyla yapılır.

---

## MimiCam nasıl çalışır?

MimiCam aynı kod tabanından iki farklı ürün deneyimi sunar:

### 1. Bebek Odası Cihazı

Eski bir telefonunuzu veya tabletinizi bebek odasına yerleştirin. Bu cihaz:

1. QR eşleştirme kodu üretir.
2. Ebeveyn cihazını güvenilir client olarak kaydeder.
3. Kamera ve mikrofon kaynaklarını yönetir.
4. Canlı video, ses ve olay akışlarını yerel ağda yayınlar.
5. Hareket ve ağlama analizinden uyarı üretir.

### 2. Ebeveyn Cihazı

Kendi telefonunuzdan QR kodu okutun. Bu cihaz:

1. Bebek odası cihazını doğrular.
2. Güvenilir token alır ve güvenli oturumu saklar.
3. Canlı görüntü ve sesi izler.
4. Uyarıları dinler ve yerel bildirim gösterebilir.
5. İzlemeyi durdurduğunuzda medya akışlarını kapatır.

---

## Kurulum deneyimi

```text
Uygulamayı aç
  ↓
Bu cihazın rolünü seç
  ↓
Bebek odası cihazında QR oluştur
  ↓
Ebeveyn cihazında QR okut
  ↓
İzle + dinle
```

Yanlış rol seçilirse uygulama içinden rol sıfırlanabilir. Rol sıfırlanınca aktif runtime kapatılır ve kullanıcı güvenli şekilde ilk ekrana döner.

---

## Güvenlik yaklaşımı

MimiCam güveni IP adresine veya cloud hesabına bağlamaz. Güven modeli şu üç parçaya dayanır:

```text
serverDeviceId + certificateFingerprintSha256 + trustedClientToken
```

Temel güvenlik ilkeleri:

- İlk güven QR payload ile kurulur.
- Pairing nonce tek kullanımlıktır ve kısa süreli yaşar.
- Eşleşme sonrası 256-bit rastgele trusted client token üretilir.
- Server token düz metnini saklamaz; hash saklar.
- Korunan endpointler bearer token ister.
- Video/ses linkleri token olmadan açılmaz.
- Uygulama internet relay, cloud backend, STUN/TURN veya OAuth gerektirmez.

---

## Öne çıkan özellikler

| Özellik | Açıklama |
| --- | --- |
| QR ile eşleşme | İlk kurulum hızlı, anlaşılır ve kontrollüdür. |
| Yerel video | MJPEG tabanlı canlı görüntü yerel ağda tüketilir. |
| Yerel ses | PCM/WAV ses akışı ebeveyn cihazına aktarılır. |
| Olay kanalı | WebSocket üzerinden uyarı ve durum olayları iletilir. |
| Ağlama analizi | Mikrofon verisinden ağlama skoru üretilebilir. |
| Hareket analizi | Kamera karelerinden hareket skoru çıkarılabilir. |
| Bildirim modu | Canlı izleme kapalıyken seçili uyarılar açık tutulabilir. |
| Güç modları | Pairing, bildirim ve canlı izleme modları kaynak kullanımını dengeler. |
| Rol izolasyonu | Server ve client dependency graph'ları birbirinden ayrıdır. |

---

## Kime uygun?

MimiCam özellikle şunlar için tasarlanır:

- Kullanmadığı ikinci telefonu bebek kamerası yapmak isteyen ebeveynler.
- Cloud kamera veya abonelik kullanmak istemeyen aileler.
- Bebek odası görüntüsünün ev ağından çıkmamasını isteyen kullanıcılar.
- Basit kurulum, net ekranlar ve kontrollü uyarılar isteyenler.
- Flutter ile yerel ağ medya mimarisi geliştirmek isteyen ekipler.

---

## Kullanıcı ekranları

- **Rol seçimi:** “Bu cihaz ne olarak çalışacak?” sorusuyla başlar.
- **Bebek odası ekranı:** QR eşleştirme, yayın durumu, medya runtime ve analiz özetini gösterir.
- **Ebeveyn ekranı:** QR tarama, eşleşme durumu ve “İzle + dinle” aksiyonunu sunar.
- **Watch ekranı:** Video, ses, WebSocket bağlantısı ve son uyarı tek yerde izlenir.

Ürün dili teknik servis listesi yerine kullanıcı aksiyonlarına odaklanır: **QR okut, izle, dinle, uyarıyı gör, yayını durdur.**

---

## Teknik özet

- Framework: Flutter / Dart
- Platformlar: Android ve iOS hedefli mobil uygulama
- Transport hedefi: HTTPS + WSS, yerel ağ
- Pairing: QR payload + tek kullanımlık nonce
- Yetkilendirme: Bearer trusted client token
- Video: MJPEG stream servis katmanı
- Ses: PCM16LE / WAV stream servis katmanı
- Olaylar: JSON alert event DTO'ları
- Analiz: MotionAnalyzerV2, CryAudioAnalyzerV2, AlertEngine
- Saklama: SharedPreferences tabanlı rol ve pairing session store

Detaylı teknik dokümantasyon için [`ARCHITECT.md`](ARCHITECT.md) dosyasına bakın.

---

## Geliştirici kurulumu

Gereksinimler:

- Flutter SDK
- Android Studio veya Xcode
- Aynı Wi‑Fi/LAN üzerinde iki test cihazı
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

## Yol haritası

- Platform uyumlu kalıcı self-signed TLS certificate üretimi
- Android foreground service ve kalıcı bildirim akışı
- iOS foreground/background medya yaşam döngüsü iyileştirmeleri
- Manual IP/discovery yardımcı eşleşme ekranları
- Token yenileme ve revoke kullanıcı arayüzleri
- Daha zengin uyarı geçmişi ve paylaşım deneyimi

---

## MimiCam ne değildir?

MimiCam bir internet kamerası, cloud kayıt sistemi veya uzak erişim servisi değildir. Uygulama bilinçli olarak şu hedefleri dışarıda bırakır:

- Cloud backend
- İnternete yayın
- WebRTC relay/STUN/TURN
- Otomatik üçüncü cihaz paylaşımı
- Enterprise OAuth akışları
- Abonelik veya hesap zorunluluğu

MimiCam'in odağı net: **aynı ağda, QR ile eşleşen iki cihaz arasında güvenli bebek izleme deneyimi.**
