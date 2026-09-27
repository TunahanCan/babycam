# Deneme, aile lisansı ve ömür boyu yayın

## Ürün kuralı

- Her oda telefonunda toplam 120 dakika ücretsiz takip vardır; günlük veya
  oturum başına yenilenmez.
- Uzak bir ebeveyn ses/görüntü alırken veya bildirim takibi açıkken süre işler.
  Beş ebeveynin aynı anda bir dakika izlemesi toplam bir dakika tüketir.
- QR ekranında bekleme, yerel önizleme ve ebeveyn bağlantısı olmadan geçen süre
  denemeden düşülmez. Son bağlantı kapandığında sayaç durur.
  Akış bağlantısı kurulurken kamera açılışı ve WebRTC görüşmesi için geçen kısa
  hazırlık süresi dahildir; hiç akış açılmayan oturum bileti beklemesi sayılmaz.
- Süre bitince aktif aktarım kapanır; yeni aktarım isteği ödeme gerektiğini
  bildirir. Cihaz eşleştirmeleri silinmez.
- Ebeveyn veya oda telefonundan tek seferlik aile lisansı satın alınır; Türkiye
  hedef fiyatı 350 TL. Lisans eşleşmiş aile oda telefonlarında kullanılabilir.
  Abonelik, her ebeveyn için ücret veya tek aktif oda transferi yoktur. Her oda
  için beş eşzamanlı ebeveyn cihazı sınırı devam eder.
- Kullanılmış süre yeniden başlatmada korunur. Sistem saati değişse de aktif
  kullanım monoton saatle ölçülür. Çökme sonrasında en fazla 15 saniyelik eksik
  bölüm kurtarılır; çevrimdışı geçirilen günler kullanım sayılmaz.

## Yerel uygulama ve mağaza arasındaki sınır

Deneme ve yayın erişimi oda telefonunda denetlenir. Satın alma uygulama ömründe
tek servis tarafından yürütülür; rol değişimi mağaza dinleyicisini kapatmaz.
Ebeveyn kendi mağaza hesabıyla ödeme yapar. Backend Apple/Google işlem kanıtını
doğrular ve imzalı lisans üretir. Ebeveyn önce hakkı kalıcı kaydeder, ardından
mağaza işlemini tamamlar ve lisansı eşleşmiş odaya LAN üzerinden aktarır.
Odada kart, ödeme hesabı veya aktivasyon sırasında internet gerekmez.

Ödeme başarılı olsa bile oda erişilemiyorsa “aktivasyon bekliyor” gösterilir;
tekrar satın alma istenmez. Hedef oda ödeme başlamadan kalıcı kaydedilir. A odası
için başlayan işlem sırasında B'ye geçmek hedefi değiştirmez. Uygulama ön planda
bağlantı döndüğünde artan bekleme aralıklarıyla tekrar teslim eder. Pending mağaza
onayı ve doğrulama beklemesi ayrı durumlardır; bekleyen işlemde ikinci checkout
açılmaz.

QR ile trusted eşleştirme aile cihazını davet etmek anlamına gelir. Aynı Wi-Fi'da
olmak yeterli değildir. Lisanslı oda, eşleşmiş ebeveyne imzalı hakkı geri verebilir;
bu ebeveyn farklı mağaza hesabında veya platformda olsa da başka aile odasını
etkinleştirebilir. Sertifika public `/status` yanıtında bulunmaz. Eşleşmeyi silmek
ödeme iadesi veya mevcut cihaz lisansını uzaktan silmek anlamına gelmez; aile dışına
verilecek oda telefonunda uygulama verileri temizlenmelidir.

Uygulama verilerini silme/kaldırıp yeniden yükleme yerel deneme kaydını siler.
Mevcut uygulamada kullanıcı hesabına bağlı bir sunucu deneme kaydı yoktur;
aynı telefonun yeniden kurulumlarla denemeyi tekrarlamasını kesin olarak
engellediğimiz iddia edilmez. Satın alınmış ömür boyu hak, aynı mağaza hesabıyla
satın almayı geri yükleyerek veya lisanslı eşleşmiş odadan hakkı alarak yeniden
açılır. Bütün lisanslı cihazlar kayıpsa mağaza restore'u için alım sahibi hesap
gerekir; mağazalar arasında kullanıcı hesabıyla bulut senkronizasyonu yoktur.

Lisans ön plana dönüşte en fazla altı saatte bir backend üzerinden yenilenir.
Geçici ağ hatası mevcut hakkı kapatmaz. Mağazadan doğrulanmış iade imzalı iptal
kaydına dönüşür; oda bu kaydı aldığında yayını kilitler ve eski lisansla yeniden
açılamaz. Tamamen çevrimdışı cihaz iadeyi anında öğrenemez. Yayın/ses/video
döngüsünde lisans sorgulaması veya sürekli internet ihtiyacı yoktur.

## Gerçek ödeme için hazırlanacak yapılandırma

1. Google Play ve App Store Connect'te **tüketilmeyen, tek seferlik** ürün:
   `miucam_lifetime_unlock_try_300`. Önceki satın alımların geri yüklenebilmesi
   için mevcut ürün kimliği korunur. Adındaki sayı eski bir kimliktir, fiyat
   değildir. Yeni bir ürün kimliğine geçmek ayrıca eski hakları taşıma planı ister.
2. Türkiye mağazasında hedef 350 TL fiyat, diğer bölgelerde mağaza tarafından
   belirlenen yerel fiyat. Uygulama satın alma düğmesinde mağazadan gelen fiyatı
   aynen gösterir. Mağaza fiyatı henüz yoksa Türkiye tarifesi ayrı etiketlenir;
   yabancı para cinsinden fiyat uydurulmaz.
3. Ürünün satılabilir durumda olması, uygulamayla eşleşmesi ve mağaza test
   hesaplarının hazırlanması. Bu depoda mağaza hesaplarına ait bu ayarlar yoktur.
4. Depodaki [doğrulama backend'ini](../backend/README.md) gerçek mağaza kimlik
   bilgileri ve kalıcı DB/Ed25519 anahtarıyla HTTPS'e dağıtın. Flutter'a
   `MIUCAM_PURCHASE_VERIFIER_URL` ve `MIUCAM_LICENSE_PUBLIC_KEY` verin.
   Preflight ürün, kaynak ve imza anahtarı uyuşmasını kontrol eder. Yanıtta
   `verified`, `productId`, `source`, `transactionFingerprint`, `entitlementId`
   ve imzalı `licenseToken` gerekir. Mağaza/private signing key uygulamaya girmez.
5. Sandbox'ta başarılı satın alma, geri yükleme, iptal, bekleme, ağ kesintisi,
   doğrulama reddi ve yinelenen işlem teslimatı kontrolü. Gerçek para harcayan
   işlem bu çalışma sırasında gerçekleştirilmedi.

Backend kaynakları, Docker paketi ve otomatik testleri depodadır. Mağaza ürünleri,
gerçek kimlik bilgileri ve canlı HTTPS dağıtımı bu kodla kendiliğinden oluşmaz.
Eksik/uyuşmayan doğrulama yapılandırmasında ödeme ekranı açılmaz. Gerçek mağaza
kabul senaryoları [backend kurulum belgesinde](../backend/README.md) listelenmiştir.

Tek seferlik kalıcı hak modeli [Google Play tek seferlik ürün belgelerinde](https://developer.android.com/google/play/billing/one-time-products)
ve [Apple tüketilmeyen satın alma belgelerinde](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
tanımlanır. Mağaza fiyatı ayrı bir yapılandırmadır:
[App Store Connect satın alma yönetimi](https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases).
