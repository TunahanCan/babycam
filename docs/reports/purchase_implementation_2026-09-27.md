# Satın alma akışı uygulama ve doğrulama kaydı

Tarih: 27 Eylül 2026. Önceki [44 senaryolu incelemenin](purchase_scenarios_2026-09-27.md)
ardından ebeveyn telefonundan satın alma, eşleşmiş odaya lisans teslimi ve mağaza
işleminin uygulama kapanışından sonra kurtarılması uygulandı.

## Uygulanan davranış

- Tek uygulama ömürlü satın alma sahibi vardır. Rol/ekran değişimi devam eden
  ödemeyi kapatmaz; ebeveynin yerel deneme sayacı oda için otorite olmaz.
- Ebeveyn ödeme yapar, imzalı aile lisansını seçili odaya LAN'dan aktarır. Odanın
  kartı, ödeme hesabı veya interneti gerekmez. Bir lisans birden fazla eşleşmiş
  aile odasında kullanılabilir; odanın beş izleyici sınırı korunur.
- Hak kalıcı kaydedilmeden mağaza işlemi tamamlanmaz. Disk hatası yanlış başarı
  üretmez. Mağaza tamamlama hatası ise teslim edilmiş hakkı geri almaz; tekrar
  teslimde completion yeniden denenir. Backend Google ack işini kalıcı saklar.
- Ödeme hedefi checkout'tan önce kaydedilir. A'da başlayan satın alma B'ye
  yönlenmez. Oda değiştirilince eski erişim snapshot'ı temizlenir.
- Pending mağaza onayı, doğrulama beklemesi ve LAN aktivasyon beklemesi ayrı
  durumlardır. Aynı uygulamadaki ikinci checkout engellenir. Aktivasyon tekrarları
  yalnız foreground'da 5–60 saniye aralığında çalışır; ödeme yeniden başlatılmaz.
- Açılış/foreground ve checkout öncesinde sahip olunan işlemler sorgulanır.
  Android mevcut satın alımları, iOS bitmemiş işlemleri ve gereken durumda mevcut
  hakları okur. Otomatik mutabakatta hesap senkronizasyon penceresi açılmaz;
  iOS `AppStore.sync` yalnız kullanıcının geri yükleme eyleminde çağrılır.
- Eski oda sürümünün aktivasyon desteği ve backend/public key uyumu ücretli
  mağaza ekranından önce kontrol edilir. Geçerli yerel lisans internet yokken
  çalışır. Public status'a sertifika veya makbuz eklenmez.
- Zaten lisanslı oda daha yeni bir active sertifika tutuyorsa eski ebeveyn tokenı
  tekrar tekrar gönderilmez; odanın güncel açık durumu kabul edilir. Bu kısa yol
  imzalı revoke için kullanılmaz; kontrol sırasında gelen revoke kaybolmaz.
- İade, ağ hatasından ayrılır. İmzalı revoke odaya iletilir; aktif lisansın
  aktarımıyla aynı ana denk gelse de daha yeni iptal yeniden gönderilir. Eski
  active token tekrar erişim açamaz. Restore önceki başarı cache'ini kullanmaz.
  Kesin iade/iptal, ebeveyn ve oda ekranlarında ayrı mesajla gösterilir.
- Bozuk deneme kaydı ücretli hakkın geri yüklenmesini engellemez. Önceden
  doğrulanmış eski yerel lisanslar korunur; cihazlar arası aktarım için restore
  üzerinden imzalı sertifikaya yükseltilir.
- Lisanslı trusted odadan yeni ebeveyn hakkı geri alabilir. Bu işlem farklı
  mağaza hesabı/platformunda ikinci satın alma gerektirmez.
- Boş restore için ayrı “satın alma bulunamadı” mesajı vardır. Fiyat cache'i
  süreli yenilenir; checkout fiyatı sabit Türkiye tutarından uydurulmaz.

## Sunucu ve kaynak kullanımı

Flutter tarafında `broadcast_access_models.dart` sabitleri, durumları ve
sözleşmeleri; `in_app_purchase_store.dart` platform adaptörünü;
`in_app_broadcast_purchase_gateway.dart` mağaza işlem yaşam döngüsünü taşır.
`broadcast_access_service.dart` deneme sayacı ve kalıcı hak kaydına odaklanır.
Mevcut import yolu export ile korunur; dosya ayrımı davranış değişikliği değildir.

`backend/` Google Android Publisher ve Apple'ın resmî App Store Server SDK'sı
ile doğrulama yapan FastAPI servisidir. Google/Apple sırları uygulamaya girmez.
SQLite kalıcı teslimat ve acknowledge kaydını, Ed25519 oda tarafından çevrimdışı
doğrulanabilen lisansı sağlar. Tek worker/replika dağıtımında aynı mağaza işlemi
kilitlenir; eşzamanlı restore ve iade yanıtı sırası bozulmaz. Legacy Apple receipt
önce canonical originalTransactionId'ye çözülür, sonra o kilit altında güncel
mağaza durumu okunur. Apple geçici OCSP hatası webhookta 503 döndürerek tekrar
teslime izin verir.
Başarısız ack denemelerinin tekrar zamanı da kalıcı ilerletilir; ilk 20 hatalı
kayıt arkadaki geçerli ödemeleri süresiz bekletemez. Bu değişim lisans revision'ını
ve durumunu değiştirmez.

İmza doğrulama aktivasyon/yükleme sırasında yapılır. Ses, video, bildirim analizi
ve normal izleme döngüsünde backend isteği yoktur. Hak yenileme foreground'da
altı saat aralıkla sınırlıdır. Lisans teslimi arka planda sürekli çalışmaz.
Mağaza/ağ çağrıları ve uygulama kapanışı için sınırlı bekleme süreleri kullanılır.

Üretim Docker imajında sentetik mağaza, test anahtarı veya test endpoint'i yoktur.
Sabitlenmiş Python bağımlılıkları, non-root süreç, veri volume'u ve private key
üretim aracı bulunur. CI, backend testini ve Python→Dart sözleşme testini Flutter
release kapısına dahil eder. Dağıtım ve yedekleme adımları
[backend/README.md](../../backend/README.md) içinde yer alır.

## Senaryo kapsamı ve ürün sınırları

| İnceleme senaryoları | Son davranış |
| --- | --- |
| 01–07 | Ebeveyn ödemesi, internetsiz oda, farklı platform/hesap ve çoklu aile odası için imzalı aktarım/kurtarma. |
| 08–11 | Aynı uygulamada tek işlem; pending ikinci checkout'u engeller. Ayrı ebeveynler işlem öncesi odanın mevcut lisansını kontrol eder. Birbirinden bağımsız mağaza hesaplarında eşzamanlı iki tahsilatı bütün aile çapında engelleyen merkezi kullanıcı hesabı yoktur. |
| 12–17 | Açılış/foreground owned purchase mutabakatı, kalıcı teslimden sonra ack, timeout ve geç gelen event kurtarma. Native mağaza davranışı gerçek sandbox kabulüne tabidir. |
| 18–23 | Kalıcı oda hedefi, idempotent aktivasyon, bağlantı geri geldiğinde retry, oda kimliğine bağlı snapshot ve eski sürüm capability kontrolü. |
| 24–27 | Yerel lisansla restart, mağaza restore'u veya trusted lisanslı odadan aile kurtarma. Bütün cihazlar kayıpsa satın alan mağaza hesabı gerekir; bulut hesap sistemi yoktur. |
| 28–29 | Restore checkout kataloğundan bağımsızdır. Boş restore için ayrı mesaj gösterilir; mevcut lisans korunur. iOS explicit restore hesap sync'i yapar. Gerçek hesap değişimi/ürün satıştan kaldırma mağaza kabul testidir. |
| 30–32 | İmzalı revoke, bozuk trial'dan paid recovery ve disk hatasında ack yapmama. |
| 33–37 | Deneme enforcement korunur; kilitli odada aktivasyon kontrol kanalı çalışır. Çoklu izleyici tek süre tüketir, altıncı izleyici limiti aşamaz. |
| 38–39 | Hak IP/router adına bağlı değildir. QR eşleştirme aile davetidir; eşleştirmeyi silmek satın alımı iade etmez. Aile dışına verilen odada yerel uygulama verisi temizlenir. |
| 40–43 | Yerel mağaza fiyatı ve mevcut SKU korunur; yapılandırma/preflight ve trusted pairing kontrolü yapılır. |
| 44 | Aile lisansı tek aktif oda transferi değildir. Tamamen çevrimdışı odanın anlık uzaktan iptali vaat edilmez. |

Mağazanın Family Sharing özelliği otomatik açılmadı. Aile paylaşımı mevcut trusted
QR eşleştirme üzerinden yapılır. Kalıcı yeni kullanıcı hesabı, aile yöneticisi
ve tüm cihazları buluttan silme ürünü eklenmedi.

## Doğrulama

Son otomatik kapı sonuçları aşağıdadır. Kanıt yolları `build/` altında üretilir;
gerçek makbuz/mağaza sırrı rapora veya git'e eklenmez.

- **Tüm Flutter paketi: 1.221 test geçti** (`build/purchase_final_flutter_tests.log`).
- Normal `flutter analyze`: **No issues found** (`build/purchase_final_analyze.log`).
- Format: 375 Dart dosyası, 0 değişiklik (`build/purchase_final_format.log`).
- Android `flutter build appbundle --release`: **başarılı**, 92,1 MB AAB
  (`build/purchase_final_android_release.log`). Testten kalan generated plugin
  kaydı normal build'in dependency/registrant üretimiyle yenilendi.
  Bu artefakt gerçek verifier URL/public key içermez; canlı satış yapılandırması
  eklenerek yeniden derlenmelidir. Linux ortamında iOS native build yapılmadı;
  macOS CI ve gerçek StoreKit kabulü ayrıca gereklidir.

- Gerçek Python HTTP → Dart Ed25519 doğrulama → denemesi bitmiş oda aktivasyonu →
  imzalı iade → eski token reddi uçtan uca testi geçti.
- Backend testleri sahte upstream HTTP/SDK cevapları kullanır; resmî Apple SDK
  gerçek configuration constructor'u ve Google response sözleşmesi sınanır.
- Python backend: **84 test geçti**. Production Docker imajı oluşturuldu ve
  ağ erişimi kapalı container'da üretim modüllerinin yüklenmesi doğrulandı.
- Flutter alan testleri kalıcı hak, restart, restore/revoke, disk ve timeout
  hataları ile oda/rol değişimlerini kapsar.
- Yeni satın alma kartı 9 locale, dar ekran ve büyük yazıda render/tap testine
  tabidir. Bebek olay bildirimi kanalı ödeme durumları için kullanılmaz.
- Türkçe hazır/pending/aktivasyon bekliyor/aktif ekranlarının 320×568 PNG'leri
  gerçek fontlarla üretildi ve görsel kontrol yapıldı:
  [satın alma](purchase_ui_2026-09-27/ready.png),
  [mağaza onayı](purchase_ui_2026-09-27/pending.png),
  [oda aktivasyonu](purchase_ui_2026-09-27/activation_pending.png),
  [lisans aktif](purchase_ui_2026-09-27/active.png).
- Site fiyatlandırma ve veri saklama açıklamaları 8 dilde aile lisansına uyarlandı;
  16 yerelleştirilmiş sayfanın static doğrulaması geçti.
- Site tarayıcı smoke testi masaüstü, tablet, 320px mobil, Arapça RTL ve
  JavaScript kapalı toplam 7 senaryoda geçti (`build/purchase_website_browser.log`).

## Dış kurulum ve canlı kabul

Kod, backend paketi ve otomatik testler hazırlandığı hâlde gerçek Google Play/App
Store hesapları, ürün erişimi ve production sunucu bilgileri bu çalışma ortamında
yoktur; kullanıcı sunucu ve mağaza erişimlerinin henüz hazır olmadığını teyit etti.
Canlı backend dağıtımı, gerçek tahsilat/iade veya mağaza sandbox kabulü
yapıldığı iddia edilmez. Son kapı, [backend kabul listesinin](../../backend/README.md)
gerçek hesaplar ve iki fiziksel cihazla çalıştırılmasıdır. Uygulama, backend URL
ve uyumlu public key olmadan ücretli checkout açmaz.
