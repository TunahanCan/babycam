# App Store / Google Play ödeme kabulü

27 Eylül 2026. Bu kayıt, uygulamadaki ekran ve akış kabul çalışmasının ödeme
bölümüdür. Gerçek tahsilat yapılmadı; mağaza adaptörlerinin native kanal
sözleşmeleri, sahte mağaza yanıtları ve uygulamanın gerçek satın alma/lisans
servisleri çalıştırıldı.

## Ödeme modeli

Tahsilat yalnız **Apple App Store / Google Play uygulama içi satın alma**
üzerindendir. `in_app_purchase`, Android ve StoreKit adaptörleri kullanılır.
Stripe, RevenueCat, PayPal veya başka bir ödeme şirketi SDK'sı/entegrasyonu
bulunmuyor; yeni bir ödeme sağlayıcısı eklenmedi.

`backend/` uygulamanın kendi makbuz doğrulama ve lisans servisidir. Kart bilgisi
almaz, ödeme tahsil etmez. Apple/Google işlem kanıtını doğrular, eşleşmiş oda
telefonunun çevrimdışı doğrulayabildiği imzalı aile lisansını üretir ve iade
durumunu takip eder. Ebeveyn kendi mağaza hesabıyla ödeyebilir; oda telefonunun
kart tanımlaması veya aynı mağaza hesabını kullanması gerekmez. Mevcut tasarımın
canlı satışı için bu servisin HTTPS adresi ve mağaza API yapılandırması gerekir;
bu, ayrı bir ödeme şirketiyle anlaşma gereksinimi değildir.

## Bulunan ve düzeltilen hatalar

1. **Açık mağaza penceresi zaman aşımında yeni checkout'a izin veriyordu.**
   StoreKit 2'nin native satın alma çağrısı kullanıcının mağaza kararını bekler.
   Uygulama bekleme süresini aştığında sonucu hata sayıp işlem kilidini
   temizliyordu. Yeni regresyon önce başarısız oldu. Şimdi native çağrı
   başlamadan kilit alınır, süre aşımı pending kalır. Geç başarı, iptal, hata
   veya açılmadı cevabı işlemi sonuçlandırır. Foreground/restore sorgusu boş olsa
   da henüz açık native çağrı ikinci ödeme açmaz. Eski çağrının geç cevabı yeni
   işlemi kapatamaz. Uygulama yeniden başlarsa mevcut owned-purchase mutabakatı
   çalışır; sahte bir başarı veya otomatik ikinci ödeme üretilmez.

2. **İade edilmiş StoreKit geçmişi yeni satın almayı engelleyebiliyordu.**
   Sabitlenmiş StoreKit eklentisinin `Transaction.all` yanıtı eski iadeyi JWS
   olmadan getirir; `currentEntitlements` bu iptal edilmiş hakkı döndürmez.
   Uygulama bu kaydı sahip olunan fakat doğrulanamayan ödeme olarak tutuyordu.
   Regresyon önce başarısız oldu. Native doğrulanmış geçmişin açık
   `revocationDate` kaydı artık owned sorgusundan çıkarılır. İade sonrası yeni
   checkout, eski iadenin yanındaki yeni satın alma ve JWS geri kazanımı
   doğrulandı. Eksik/bozuk veri hakkı varmış gibi kabul edilmez. Mevcut yerel
   hakkı kaldırmak hâlâ backend'in imzalı revoke belgesini gerektirir.

## Çalıştırılan senaryolar

| Alan | Kabul kapsamı |
| --- | --- |
| Native mağaza | Android acknowledgement hata/tekrar; pending ve unfinished sorgusu; StoreKit JWS geri kazanımı; unfinished işlemin finish hakkının korunması; yalnız explicit restore'da hesap sync'i; geçici makbuz sorgu hatası ve retry. |
| Checkout | Uygun olmayan mağaza/yapılandırma/ürün; fiyat yenileme; preflight; iptal ve hata; mağaza onayı bekleme; açık pencere timeout; ikinci checkout engeli; geç native sonuçlar. |
| Kalıcı teslim | Doğrulama öncesi erişim vermeme; diske kaydetmeden ack yapmama; disk hatası; ack hatası ve tekrar; mükerrer store event'inde tek teslim/tek ack; geç veya uygulama kapalıyken tamamlanan işlemin kurtarılması. |
| Restore / iade | Boş restore; aynı kanıtı güncel doğrulama; geçici bağlantı hatasında mevcut hakkı koruma; kesin imzalı revoke; revoke ardından eski active tokenı reddetme; iade sonrası yeniden satın alma. |
| Ebeveyn → oda | Ebeveynin kendi mağaza fiyatı ve hesabı; imzalı aile hakkı aktarımı; oda A'da başlayan ödemenin B'ye kaymaması; offline odada kalıcı teslim/retry; lisanslı trusted odadan hakkı kurtarma; ödeme sırasında rol değişimi. |
| Kaynak / erişim | Arka planda aktivasyon tekrarını durdurma; native/HTTP timeout; kapanışta iptal; geç cevabın silinmiş odayı geri getirmemesi; deneme bitişinde yayın kapanışı; lisans geri yüklenince beş izleyici sınırını koruma. |
| Backend | Google pending/refund/ack/current-state sözleşmeleri; Apple signed transaction ve güncel durum; yanlış SKU/uygulama; webhook retry; restore/iade yarışı; kalıcı ack recovery ve adil retry. |

**13 yeni regresyon** eklendi. Aşağıdaki odaklı pakette **158 Flutter testi**,
backend paketinde **92 test** geçti. Değişen dört Dart dosyasının analizi temiz.

```sh
flutter test test/services/monetization \
  test/app/broadcast_purchase_coordinator_test.dart \
  test/features/server/broadcast_license_activation_test.dart \
  test/features/server/broadcast_access_enforcement_test.dart \
  test/features/client/remote_broadcast_access_client_test.dart
build/purchase_backend_venv/bin/python -m pytest backend/tests -q
```

Yerel loglar: `build/payment_acceptance_flutter.log` ve
`build/payment_acceptance_backend.log`. Backend testlerinde mağazaya ağ erişimi
engellenir; gerçek makbuz, kart veya secret kullanılmaz. Backend çıktısında
Starlette test istemcisinin httpx kullanımıyla ilgili bir deprecation uyarısı
vardır; test başarısızlığı yoktur.

## Resmî sözleşme ve kalan canlı kabul

Google pending durumda erişim/ack verilmemesini ve tamamlanan satın alımın
zamanında acknowledgement almasını ister; uygulama foreground'da sahip olunan
işlemleri yeniden sorgular. [Google Play entegrasyon belgesi](https://developer.android.com/google/play/billing/integrate).
Apple `sync()` çağrısını kullanıcının açık geri yükleme eylemiyle sınırlar;
güncel haklar iade edilmiş ürünleri içermez. [Apple sync](https://developer.apple.com/documentation/storekit/appstore/sync%28%29),
[Apple currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements).
Flutter adaptörü doğrulama/teslim sonrasında işlemin tamamlanmasını ister.
[Flutter in_app_purchase](https://pub.dev/packages/in_app_purchase).

Mağaza ve production sunucu erişimleri henüz hazır değil. Bu nedenle gerçek
StoreKit Sandbox / Play lisans test hesabı, mağazanın kendi ödeme penceresi,
Ask to Buy, banka reddi, gerçek ürün fiyatı, gerçek iade/webhook teslimi ve
iki fiziksel telefonda mağaza satın alımı **tamamlandı sayılmaz**. Bu çalışma
native sözleşme mock'ları ve uygulama/backend kabulüdür; gerçek mağaza kabulünün
yerine geçmez. Canlı backend kurulumu ve mağaza ürün erişimi hazır olduğunda
[backend kabul listesi](../../backend/README.md) uygulanmalıdır.
