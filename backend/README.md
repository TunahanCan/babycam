# MiuCam satın alma doğrulama servisi

Ebeveyn telefonundaki Google Play/App Store alımını mağazadan doğrular ve LAN
üzerinden eşleşmiş oda telefonlarının çevrimdışı doğrulayabildiği Ed25519 lisansını
üretir. Kamera, ses ve bebek bildirimleri bu servisten geçmez. Normal yayında
backend isteği yapılmaz.

## Yerel doğrulama

Python 3.14 ve proje kökünde Flutter gereklidir:

```bash
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements-test.txt
cd backend
.venv/bin/python -m pytest -q
```

Proje kökünden `tool/tests/purchase_backend_contract_test.dart` ayrıca gerçek
HTTP yanıtını Dart imza doğrulayıcısı ve oda aktivasyon sunucusuyla sınar. Bu test
yalnız loopback üzerinde sentetik mağaza kanıtı kullanır; gerçek mağaza testi
değildir. Test fixture'ları Docker imajına dahil edilmez.

```bash
MIUCAM_BACKEND_TEST_PYTHON="$PWD/backend/.venv/bin/python" \
  flutter test tool/tests/purchase_backend_contract_test.dart
```

## Dağıtım

1. Google Play ve App Store Connect'te `com.miucam.app` uygulaması için
   `miucam_lifetime_unlock_try_300` tüketilmeyen ürünü, yerel fiyatları ve test
   hesaplarını yapılandırın. Ürün kimliğini mevcut satın alımları korumak için
   değiştirmeyin. Mağaza Family Sharing özelliği bu uygulamadaki eşleşmiş cihaz
   paylaşımından ayrı bir üründür.
2. Google Android Publisher API'yi açın; uygulama satın alımlarını okuyup
   acknowledge edebilen servis hesabına Play Console erişimi verin. Backend ADC
   kullanır; JSON anahtarı uygulamaya veya git'e koymayın.
3. Apple için App Store Server API In-App Purchase anahtarı, key/issuer ID,
   sayısal appAppleId ve [Apple PKI kök sertifikalarını](https://www.apple.com/certificateauthority/)
   hazırlayın. Kökler DER formatındadır. Üretimde yalnız production işlemleri;
   ayrı sandbox dağıtımında yalnız sandbox işlemleri kabul edilir. Apple'ın
   resmî SDK'sı JWS zincirini, ortamı ve uygulama kimliğini doğrular.
4. `backend/.env.example` dosyasını `.env` olarak kopyalayıp gerçek değerleri
   girin. En az bir gerçek mağaza zorunludur. Google ve Apple'ı ayrı ayrı açmak
   mümkündür; kapalı mağaza için uygulama checkout başlatmaz.
5. Kalıcı lisans anahtarını **bir kez** oluşturun:

   ```bash
   cd backend
   .venv/bin/python -m miucam_billing.keygen secrets/license-signing.pem
   ```

   Komut yalnız uygulamaya verilecek base64url public key'i yazdırır; mevcut
   anahtarı ezmez. Private key'i ve veritabanını yedekleyin. Anahtar değişimi eski
   çevrimdışı lisansları etkiler; mevcut sürüm tek public key pinler. Sıradan
   dağıtım/yeniden başlatmada yeni anahtar üretmeyin.
6. Proje kökünden Docker imajını oluşturup yerel HTTPS proxy arkasında başlatın:

   ```bash
   docker build -t miucam-billing backend
   docker run --detach --name miucam-billing --restart unless-stopped \
     --env-file backend/.env \
     --mount type=bind,source=/ABSOLUTE/PRIVATE/miucam-secrets,target=/secrets,readonly \
     --mount type=volume,source=miucam-billing-data,target=/data \
     --publish 127.0.0.1:8080:8080 miucam-billing
   ```

   Süreç UID 10001 ile çalışır; secret dosyaları bu UID tarafından okunabilir
   olmalıdır. SQLite veri dizini kalıcı yerel disktir. **Tek worker/tek replika**
   kullanılır: işlem başına kilitler ve SQLite bu dağıtım modeline göre tasarlandı.
   Çoklu replika için paylaşımlı transactional veritabanı ve dağıtık işlem kilidi
   gerekir. Reverse proxy'de HTTPS, istek boyutu ≤128 KiB, trafik sınırı ve makul
   request timeout ayarlayın. Yalnız kendi proxy IP'nizi forwarded-header için
   `FORWARDED_ALLOW_IPS` ile güvenilir yapın; uygulamanın 8080 portunu internete
   açmayın. Aksi halde IP bazlı limit tüm trafiği aynı proxy altında sayabilir.
   Proxy access log'a
   gövde, Authorization başlığı veya makbuz eklemeyin.
7. `/health` yanıtında açık mağazaları kontrol edin. Flutter release'e aynı
   dağıtımın public key'ini ve HTTPS URL'sini verin:

   ```bash
   flutter build appbundle --release \
     --dart-define=MIUCAM_PURCHASE_VERIFIER_URL=https://billing.example.com/verify \
     --dart-define=MIUCAM_LICENSE_PUBLIC_KEY=YOUR_BASE64URL_PUBLIC_KEY
   ```

   Preflight ürün, mağaza, URL erişimi ve imza anahtarı uyumunu kontrol eder.
   Mağaza hesabının gerçekten tahsilat/doğrulama yapabildiğini kanıtlamak için
   aşağıdaki gerçek sandbox kabul testleri ayrıca gereklidir.
8. Google RTDN için authenticated Pub/Sub push aboneliğini
   `/notifications/google` adresine yönlendirin. OIDC audience ve doğrulanmış
   servis hesabı e-postası `.env` ile birebir eşleşmelidir. Apple App Store Server
   Notifications V2 adresi `/notifications/apple` olur; yalnız Apple imzalı
   bildirimler kabul edilir. Bildirim içeriğine göre doğrudan hak verilmez;
   güncel işlem yeniden mağazadan okunur.

## Teslimat, kurtarma ve iade

- `POST /verify`: mağaza kanıtını doğrular; SQLite commit sonrası imzalı
  `licenseToken`, `productId`, `source`, `transactionFingerprint`, `entitlementId`
  döndürür. Ham makbuz istemci lisansına veya genel durum yanıtına girmez.
- Google ack kaydı kalıcıdır. İstemci kendi lisansını kaydettikten sonra native
  işlemi tamamlar; istemci kapanırsa backend 30 saniyelik aralıklarla eksik ack'i
  kurtarır. Önce güncel mağaza durumu kontrol edilir; iptal edilmiş ödeme ack
  edilmez. Geri yükleme aynı işlem için aynı entitlement ID'yi üretir.
- `POST /verify` + `licenseToken`: mevcut lisansı yeniden doğrular. Kesin iade
  imzalı `revoked` durumu üretir; ağ hatası geçerli yerel lisansı silmez. Artan
  revision oda telefonunda eski active token ile geri açılmayı engeller.
- Oda kontrol kanalı deneme bitse de erişilebilirdir. Lisans aktarımı için
  eşleşmiş trusted client gerekir. Aynı ağda olmak yeterli değildir. QR ile aile
  cihazı olarak eşleştirilen ebeveyn, lisanslı odadan hakkı geri alıp başka eşleşmiş
  odada kullanabilir. Tek aktif oda transfer kuralı yoktur.
- Uygulama ön planda lisansı en fazla altı saatte bir yeniler; medya döngüsünde
  sunucu çağrısı yoktur. Tamamen çevrimdışı oda iadeyi anında öğrenemez. Yenilenen
  iptal bilgisi oda tekrar erişilebilir olduğunda iletilir.
- Uygulama açılışında/ön plana dönüşte bitmemiş veya kaçırılmış mağaza işlemleri
  sessiz sorgulanır. iOS otomatik yolunda `AppStore.sync` çağrılmaz; kullanıcının
  “Satın almayı geri yükle” seçimi hesap senkronizasyonunu başlatabilir. StoreKit
  paketinin 0.4.10+1 sürümü sabittir: mevcut hakların JWS ile alınması için kullanılan
  wrapper'ın native davranışı sürüm yükseltirken tekrar doğrulanmalıdır.
- Her iki telefonda da veri silinmişse alım sahibi mağaza hesabıyla restore
  gerekir. Hesap sistemi yoktur; tüm cihazlar kayıpken Google hesabındaki satın
  alımı yalnız Apple hesabıyla bulma iddiası yoktur.

SQLite yedeği çalışan sunucuda dosyayı doğrudan kopyalayarak alınmamalıdır; WAL
nedeniyle SQLite backup API veya tutarlı disk snapshot kullanın. Veritabanı
mağaza token'ları içerir; erişimi ve yedeği private tutun. Anahtar ve DB kurtarma
tatbikatında aynı alımın entitlement ID'sinin korunduğunu sınayın. Kaydı olmayan
imzalı lisans yenilemesinde servis geçici hata verir; ücretli kullanıcıyı iptal
edilmiş saymaz.

API istek gövdesi ve Google yanıtı sınırlıdır; ağ çağrılarında timeout vardır.
Apple SDK sertifika/OCSP doğrulaması kendi 30 saniyelik ağ timeout'unu kullanır.
İstemci kısa timeout ile ekranda bekleme durumuna geçebilir; kalıcı işlem sonra
geri kazanılır. Süreç/proxy için CPU, RAM ve eşzamanlı bağlantı limitlerini hedef
sunucuya göre ayarlayın. 5xx, doğrulama gecikmesi ve `ack_pending` kaydının yaşı
izlenmelidir; işlem kanıtını metrik etiketi veya log mesajı yapmayın.

## Canlıya geçmeden gerçek mağaza kabul testi

Ayrı sandbox anahtarı/veritabanıyla, mağazadan yüklenmiş iki fiziksel telefon:

- Ebeveyn öder; kart/ödeme hesabı olmayan ve internetsiz oda LAN'da açılır.
- Pending/Ask to Buy → uygulama kapalıyken onay → açılışta hak geri gelir.
- Mağaza ekranında iptal, ödeme reddi, backend kesintisi ve LAN kopması yanlış
  başarı veya ikinci ödeme istemi üretmez.
- Ödeme sırasında rol/oda değişir; seçilen oda karışmaz. Yeniden başlatma ve
  yeniden kurulum sonrası restore çalışır.
- Lisanslı odadan farklı mağaza hesabına/platforma sahip eşleşmiş ebeveyn hakkı
  geri alır; ikinci oda ek ödeme olmadan açılır.
- İade/iptal bildirimi backend'e ulaşır; yeniden doğrulama sonrası oda kapanır;
  eski active token yeniden erişim açamaz. Ağ kesintisi mevcut hakkı kapatmaz.
- Google acknowledgement Play Console'da, Apple transaction completion cihazda
  kontrol edilir. Aynı işlem tekrar tesliminde ek tahsilat veya yeni hak doğmaz.

Bu kontroller için gerçek mağaza sahipliği, ürün ve imza bilgileri gerekir;
otomatik testlerin geçmesi bu dış kurulumu veya kabul testini gerçekleştirmez.
