# MiuCam Production Release Checklist

Bu belge mağaza yüklemesinden önce tamamlanması gereken teknik ve operasyonel
kapıları tanımlar.

Son üretim hazırlığı: [27 Eylül 2026 özellik kabulü ve gerçek Android ölçümleri](reports/production_readiness_2026-09-27.md).
Son kod incelemesi: [27 Eylül 2026 kapsamlı inceleme](reports/full_code_review_2026-09-27.md).
Önceki kabul: [27 Eylül 2026 uygulama, medya ve mağaza kabulü](reports/full_app_acceptance_2026-09-27.md)
(38 görüntülü galeri; gerçek mağaza kabulü açık).
Önceki inceleme: [27 Eylül 2026 performans ve ekran incelemesi](reports/performance_ui_review_2026-09-27.md).
Odaklı takip: [ses/video akışı ve bildirim tutarlılığı](reports/media_alert_review_2026-09-27.md)
(1.107 test ve son kaynaklarla Android ses/bildirim doğrulaması).
Önceki kapsamlı inceleme: [6 Eylül 2026 kod incelemesi](reports/production_code_review_2026-09-06.md).
Otomatik kontrollerin geçmesi gerçek cihaz, imzalama ve mağaza kabulünün
yerine geçmez.

## Otomatik kapılar

Her pull request ve `master/main` güncellemesinde GitHub Actions şunları
çalıştırır:

1. `dart format --output=none --set-exit-if-changed lib test tool/tests`
2. `flutter analyze`
3. `flutter test`
4. Android native JVM testleri: `cd android && ./gradlew testDebugUnitTest`
5. `flutter build appbundle --release` — imzasız derleme kontrolü; ardından ayrı
   Gradle çağrısıyla `:app:lintRelease`
6. `flutter build ios --release --no-codesign` — imzasız derleme kontrolü
7. iOS simülatöründe `RunnerTests` XCTest ses dönüştürme/oynatma testleri
8. Python backend testleri, Docker build ve container satın alma/yeniden başlatma/
   SQLite yedek kurtarma/iade yaşam döngüsü kabulü
9. Gerçek Python HTTP → Dart lisans doğrulama → oda aktivasyon/iade sözleşme testi
10. Production build kapısı testleri:
    `python3 -m unittest discover -s tool/tests/release -v`

CI artifact'ları mağazaya yüklemeye hazır paket sayılmaz. Üretim paketi aşağıdaki
komutla oluşturulur; komut eksik ödeme/imza ayarlarını ve sandbox backend'ini
reddeder.

Yerel iOS release doğrulaması:

```bash
/Users/tunahan.can/flutter_develop/flutter/bin/flutter build ios \
  --release --no-codesign
```

## Production paketini oluşturma

`tool/release/production.example.json` dosyasını git tarafından dışlanan
`tool/release/production.json` yoluna kopyalayıp gerçek HTTPS `/verify` adresi ve
backend Ed25519 public key'ini girin. Private key uygulamaya verilmez.

```bash
python3 tool/release/build_production.py --platform android \
  --defines-file tool/release/production.json --check-only
python3 tool/release/build_production.py --platform android \
  --defines-file tool/release/production.json
```

Kapı, deneme sınırının açık ve teşhis WebRTC pilotunun kapalı olmasını; Android
upload keystore dosyası ve alanlarının varlığını; canlı HTTPS preflight yanıtında
mağaza, ürün, public key ve `storeEnvironment=production` eşleşmesini zorunlu
kılar. HTTP yönlendirmesi kabul etmez. `--check-only` derleme/ödeme/yükleme yapmaz;
canlı backend'e yalnız makbuz içermeyen preflight isteği gönderir. Gerçek key
parolası ve imza doğrulaması paket oluşturulurken Gradle tarafından yapılır.

macOS üzerinde aynı kapı iOS için App Store IPA üretir:

```bash
python3 tool/release/build_production.py --platform ios \
  --defines-file tool/release/production.json \
  --export-options-plist tool/release/ExportOptions.plist
```

Xcode'da Apple Developer Team ayarlanmalı; export plist aynı `teamID` ve
`method=app-store-connect` içermelidir. Dağıtım sertifikası/provisioning gerçek
IPA üretiminde Xcode tarafından kontrol edilir. Export plist `destination`
alanı yalnız `export` olabilir (atlanırsa varsayılan budur); `upload` reddedilir.
Flutter PATH'te değilse
`--flutter /absolute/path/to/flutter` eklenebilir. Komut dosyaları hiçbir paketi
mağazaya yüklemez. Gerçek sandbox ödeme kabulü ayrı sandbox derlemesiyle yapılır;
production komutu sandbox backend'i özellikle reddeder.

Derleme sıfır koduyla bitse bile kapı yeni, boş olmayan ve imza yapısı bulunan
AAB/IPA arşivi ister. Önceden kalan dosyanın metadata ve SHA-256 özeti aynıysa
başarı sayılmaz; hiçbir eski paket otomatik silinmez. Bu kontrol, Flutter'ın IPA
export başarısızlığını başarılı archive nedeniyle sıfır çıkışla bildirebildiği
durumu da yakalar. İmza sertifikasının mağaza hesabıyla eşleşmesi Gradle/Xcode ve
mağaza kabulünün sorumluluğundadır.

Doğrudan `flutter build ... --release` derleme doğrulaması için hâlâ kullanılabilir;
production komutunun yaptığı yapılandırma kontrolünü gerçekleştirmez.

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

`flutter drive` yalnız önceden derlenmiş, `adb install -r` ile güncelleme olarak
kurulmuş uygulamaya `--use-existing-app=VM_SERVICE_URI --keep-app-running`
ile bağlanmalıdır. `--keep-app-running` tek başına kurulum hatasında kaldırıp
yeniden kurma yolunu engellemez. Kurulum başarısızsa durun; uygulamayı kaldırma
veya veri temizleme ile çözmeyin. Kullanıcı verisi bulunan cihazda önce uygun
yedek yöntemi doğrulanmalı; test sonrasında normal paket `adb install -r` ile
geri kurulmalıdır. [Cihaz testi kurulumu](../integration_test/role_isolation_device.md)
ve [profile benchmark yönergesi](ui_frame_time_benchmark.md) bu akışı açıklar.

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

## Eşleştirme ve bildirim kapsamı

Ürün, aynı güvenilir yerel ağda QR veya geçici altı haneli kodla ilk eşleştirme
kullanır. Görüntü/ses HTTP/WS üzerinden iletilir; medya şifreleme bu sürümün
kapsamında değildir. Bu nedenle mağaza metni uçtan uca şifreleme veya ortak ağlarda
şifreli yayın iddiası taşımamalıdır.

- Manuel IP/ağ keşfi geçerli altı haneli kod olmadan trusted token üretmez.
  Kod 10 dakika geçerlidir; kullanım/yenileme sonrası değişir. Kod denemeleri
  cihaz geneli dakikada beş ile sınırlıdır; QR yolu bundan ayrı çalışır.
- Kayıp telefonu oda ekranından iptal etme ve açık medya, WebSocket, WebRTC ve
  talk bağlantılarını kapatma otomatik testlerde kapsanır.
- Mevcut LAN bildirimlerinin uygulama tamamen kapalıyken APNs/FCM bildirimi gibi
  çalıştığı vaat edilmez. Böyle bir özellik ayrıca uygulanıp kabul edilmelidir.
- İki cihazda eşleştirme, kod yenileme, iptal ve tekrar bağlantı cihaz kabul
  matrisinde doğrulanır.

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
