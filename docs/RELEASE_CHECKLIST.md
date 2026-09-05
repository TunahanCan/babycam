# MiuCam Production Release Checklist

Bu belge mağaza yüklemesinden önce tamamlanması gereken teknik ve operasyonel
kapıları tanımlar.

## Otomatik kapılar

Her pull request ve `master/main` güncellemesinde GitHub Actions şunları
çalıştırır:

1. `dart format --output=none --set-exit-if-changed lib test`
2. `flutter analyze`
3. `flutter test`
4. `flutter build appbundle --release`
5. `flutter build ios --release --no-codesign`

Yerel iOS release doğrulaması:

```bash
/Users/tunahan.can/flutter_develop/flutter/bin/flutter build ios \
  --release --no-codesign
```

## Yayın kimliği

- Android `applicationId/namespace`, Kotlin paket yolları ve iOS
  `PRODUCT_BUNDLE_IDENTIFIER` production kimliği olarak `com.miucam.app`
  kullanır.
- Kimlik ilk Google Play veya App Store kaydından sonra değiştirilmemelidir.
- Her yüklemede `pubspec.yaml` içindeki build number artırılmalıdır.

## İmzalama

Android için `android/key.properties.example`, `android/key.properties` olarak
kopyalanır ve gerçek upload key bilgileri girilir. Key ve parola dosyaları git'e
eklenmez. Google Play App Signing etkinleştirilmeli ve upload key güvenli bir
parola kasasında yedeklenmelidir.

iOS için Apple Developer Team, App ID, Distribution Certificate ve App Store
provisioning profile Xcode/App Store Connect üzerinde yapılandırılmalıdır.

## Mağaza ve politika

- Gizlilik politikası HTTPS üzerinden yayınlanmalı, URL hem mağaza metadata'sına
  hem uygulamanın Ayarlar/Hakkında alanına eklenmelidir. `PRIVACY.md` yayınlanacak
  metnin kaynak taslağıdır.
- Kamera ve mikrofon kullanılırken uygulama görünür durum ve sistem gizlilik
  göstergelerini korumalıdır.
- Android foreground service türleri Play Console App Content alanında kamera,
  mikrofon, medya oynatma ve bağlı cihaz kullanım amacıyla beyan edilmelidir.
- Google Play Data Safety ve Apple App Privacy cevapları gerçek release
  konfigürasyonuyla eşleşmelidir.
- iOS server modunda kamera arka planda devam edemez. Arka plan audio modu kamera
  kısıtını aşmak için kullanılmamalı; mağaza açıklaması bu platform sınırını açık
  söylemelidir.

## Deneme ve tek seferlik satın alma

Normal derlemelerde oda telefonunda toplam 2 saatlik deneme sınırı açıktır.
Ömür boyu yayın ürünü, Türkiye mağazasında 350 TL hedef fiyatıyla tek seferlik
(non-consumable) ürün olarak yapılandırılmalıdır. Mevcut ürün kimliği fiyat
değişikliğinde korunur: `miucam_lifetime_unlock_try_300`. Kimlikteki eski sayı
fiyatı belirlemez; daha önce satın alanların hakkı ve geri yüklemesi korunur.

Gerçek ödeme derlemesi güvenilir HTTPS doğrulama adresini gerektirir:

```bash
--dart-define=MIUCAM_PURCHASE_VERIFIER_URL=https://YOUR-BACKEND/verify
```

Mağaza fiyatı, ürünün satış durumu ve makbuz doğrulaması gerçek hesaplarda
hazır olmadan bu derleme satışa sunulmamalıdır. Eksik doğrulama adresinde uygulama
ödeme ekranını açmaz. Sandbox satın alma, geri yükleme, bekleyen/iptal işlem ve
başarısız doğrulama senaryoları [fiyatlandırma notunda](broadcast_pricing.md)
açıklanmıştır. Deneme kapatma bayrağı yalnız teşhis derlemeleri içindir:
`--dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=false`.

## Cihaz kabul testi

Son sınırlı cihaz doğrulaması: [5 Eylül 2026 LG H870 raporu](reports/lg_h870_validation_2026-09-05.md).
Takip çalışması: [ses/görüntü analizi ve bildirim lokalizasyonu](reports/alert_pipeline_localization_2026-09-05.md)
(889 test, tüm 9 locale ve LG native dil kontrolü).
Bu rapor aşağıdaki çoklu cihaz ve platform kapılarının yerine geçmez.

- En az bir güncel ve bir eski desteklenen iPhone/iPad.
- Android 13, 14, 15 ve 16 üzerinde gerçek cihaz testi.
- Ekran kilidi, Wi-Fi internet yok, Wi-Fi değişimi ve zayıf sinyal senaryoları.
- Aynı Client'ın tekrarlı bağlanması, ses aç/kapat ve uygulama rol değişimi.
- Kamera/mikrofon/bildirim izni reddetme ve Ayarlar'dan sonradan açma.
- 30 dakika kesintisiz yayın, termal yük ve pil tüketimi kaydı.

## Güvenlik ve teslimat kapıları

Aşağıdaki maddeler tamamlanmadan MiuCam, güvenilmeyen/ortak ağlar veya
"uygulama kapalıyken WhatsApp benzeri bildirim" vaadiyle yayınlanmamalıdır:

- QR ile pinlenen sunucu kimliği ve HTTPS/WSS; bearer token, ses ve video
  cleartext HTTP/WS üzerinden taşınmamalı.
- Manuel IP eşleşmesinde QR'a eşdeğer fiziksel onay. Public discovery yanıtı
  tek başına uzun ömürlü trusted token üretmeye yetmemeli.
- Kayıp telefonu server ekranından listeleme/iptal etme ve iptal anında açık
  medya, WebSocket, WebRTC ve talk bağlantılarını kapatma.
- Uygulama askıda/kapalıyken bildirim vaat edilecekse APNs/FCM, kalıcı event
  sırası, ACK ve kaçırılan olay replay mekanizması.
- Yukarıdaki tehdit modeli için gerçek iki cihazlı saldırı/yeniden bağlanma
  kabul testi ve bağımsız güvenlik incelemesi.

## Dış bağımlı blockerlar

- Production bundle/application ID kararı.
- Apple Developer Team ve Google Play Console sahipliği.
- Android upload key ve iOS dağıtım sertifikaları.
- HTTPS gizlilik/support URL'si ve destek e-postası.
- Paywall açılacaksa mağaza ürünleri ve trusted verifier backend'i.

## Toolchain bakım notu

- Mevcut Flutter sürümünde release AAB oluşuyor; ancak Flutter, uygulama ve
  `camera_android_camerax`, `flutter_webrtc`, `mobile_scanner`, `nsd_android`,
  `wakelock_plus` eklentileri için eski Kotlin Gradle Plugin modelinin ileride
  kaldırılacağını bildiriyor. Flutter major sürümü yükseltilmeden önce uygulama
  Built-in Kotlin'e geçirilmeli, eklentilerin uyumlu sürümleri seçilmeli ve bu
  listedeki Android/iOS kapıları yeniden çalıştırılmalıdır.
