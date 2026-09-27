# MiuCam Production Release Checklist

Bu belge mağaza yüklemesinden önce tamamlanması gereken teknik ve operasyonel
kapıları tanımlar.

Son inceleme: [27 Eylül 2026 performans ve ekran incelemesi](reports/performance_ui_review_2026-09-27.md).
Odaklı takip: [ses/video akışı ve bildirim tutarlılığı](reports/media_alert_review_2026-09-27.md)
(1.107 test ve son kaynaklarla Android ses/bildirim doğrulaması).
Önceki kapsamlı inceleme: [6 Eylül 2026 kod incelemesi](reports/production_code_review_2026-09-06.md).
Otomatik kontrollerin geçmesi, bu rapordaki açık güvenlik ve mağaza engellerini
kapatmaz.

## Otomatik kapılar

Her pull request ve `master/main` güncellemesinde GitHub Actions şunları
çalıştırır:

1. `dart format --output=none --set-exit-if-changed lib test tool/tests`
2. `flutter analyze`
3. `flutter test`
4. `flutter build appbundle --release`
5. `flutter build ios --release --no-codesign`
6. Python backend testleri ve Docker build
7. Gerçek Python HTTP → Dart lisans doğrulama → oda aktivasyon/iade sözleşme testi

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

Gerçek ödeme derlemesi güvenilir HTTPS doğrulama adresini ve o sunucunun Ed25519
public key'ini gerektirir. Backend kaynakları ve kurulum adımları
[backend/README.md](../backend/README.md) içinde bulunur:

```bash
--dart-define=MIUCAM_PURCHASE_VERIFIER_URL=https://YOUR-BACKEND/verify \
--dart-define=MIUCAM_LICENSE_PUBLIC_KEY=YOUR_BASE64URL_PUBLIC_KEY
```

Mağaza fiyatı, ürünün satış durumu ve makbuz doğrulaması gerçek hesaplarda
hazır olmadan bu derleme satışa sunulmamalıdır. Uygulama, doğrulama adresi eksik
olduğunda veya imza anahtarı uyuşmadığında ödeme ekranını açmaz. Sandbox'ta ebeveyn
ödemesi → internetsiz oda aktivasyonu, uygulama kapalıyken pending onayı,
restore, ikinci aile cihazı, rol/oda değişimi, LAN kesintisi, iade bildirimi ve
Google ack kurtarma gerçek mağaza hesabıyla doğrulanmalıdır. Otomatik testler bu
kabulün yerine geçmez. Deneme kapatma bayrağı yalnız teşhis derlemeleri içindir:
`--dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=false`.

## Cihaz kabul testi

`flutter drive` ile yeniden doğrulamada `--keep-app-running` verilmelidir;
aksi halde Flutter test sonunda uygulamayı kaldırır ve yerel verileri siler.
Kullanıcı verisi bulunan cihazda önce uygulama verisinin uygun yedeği alınmalı;
test sonrasında normal paket `adb install -r` ile geri kurulmalıdır.

Önceki cihaz doğrulaması: [5 Eylül 2026 LG H870 raporu](reports/lg_h870_validation_2026-09-05.md).
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
  medya, WebSocket, WebRTC ve talk bağlantılarını kapatma (uygulandı; eşleştirme
  ve iptal yarışları otomatik testlerde kapsanıyor).
- Uygulama askıda/kapalıyken bildirim vaat edilecekse APNs/FCM, kalıcı event
  sırası, ACK ve kaçırılan olay replay mekanizması.
- Yukarıdaki tehdit modeli için gerçek iki cihazlı saldırı/yeniden bağlanma
  kabul testi ve bağımsız güvenlik incelemesi.

## Dış bağımlı blockerlar

- Apple Developer Team ve Google Play Console sahipliği.
- Android upload key ve iOS dağıtım sertifikaları.
- HTTPS gizlilik/support URL'si ve destek e-postası.
- İki saat deneme sonrasında satış için mağaza ürünleri, depodaki verifier'ın
  gerçek mağaza kimlik bilgileriyle HTTPS dağıtımı, kalıcı DB/anahtar yedeği ve
  bildirim adresleri; sandbox satın alma/geri yükleme, iade ve iptal kabul testleri.

## Toolchain bakım notu

- Mevcut Flutter sürümünde release AAB oluşuyor; ancak Flutter, uygulama ve
  `camera_android_camerax`, `flutter_webrtc`, `mobile_scanner`, `nsd_android`,
  `wakelock_plus` eklentileri için eski Kotlin Gradle Plugin modelinin ileride
  kaldırılacağını bildiriyor. Flutter major sürümü yükseltilmeden önce uygulama
  Built-in Kotlin'e geçirilmeli, eklentilerin uyumlu sürümleri seçilmeli ve bu
  listedeki Android/iOS kapıları yeniden çalıştırılmalıdır.
