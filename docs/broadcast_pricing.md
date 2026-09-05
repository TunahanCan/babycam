# Oda telefonunda deneme ve ömür boyu yayın

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
- Oda telefonunda tek seferlik ömür boyu satın alma; Türkiye hedef fiyatı 350 TL.
  Abonelik veya her ebeveyn telefonu için ek ödeme yoktur. Beş eşzamanlı
  ebeveyn cihazı sınırı devam eder.
- Kullanılmış süre yeniden başlatmada korunur. Sistem saati değişse de aktif
  kullanım monoton saatle ölçülür. Çökme sonrasında en fazla 15 saniyelik eksik
  bölüm kurtarılır; çevrimdışı geçirilen günler kullanım sayılmaz.

## Yerel uygulama ve mağaza arasındaki sınır

Deneme ve ömür boyu erişim oda telefonunda denetlenir. Apple/Google makbuzu
geçerli bir satın alma olarak doğrulanmadan erişim açılmaz. Ebeveyn telefonu
oda telefonunun erişim durumunu gösterir ve satın almayı oda telefonuna yönlendirir.

Uygulama verilerini silme/kaldırıp yeniden yükleme yerel deneme kaydını siler.
Mevcut uygulamada kullanıcı hesabına bağlı bir sunucu deneme kaydı yoktur;
aynı telefonun yeniden kurulumlarla denemeyi tekrarlamasını kesin olarak
engellediğimiz iddia edilmez. Satın alınmış ömür boyu hak, aynı mağaza hesabıyla
satın almayı geri yükleyerek yeniden açılır; mağazalar arasında otomatik hak
aktarımı uygulanmış değildir.

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
4. Güvenilir HTTPS makbuz doğrulama servisi. Adres
   `MIUCAM_PURCHASE_VERIFIER_URL` derleme tanımıyla verilir. Servis mağazaya
   danışarak ürün, uygulama/paket, satın alma durumu ve işlem kanıtını doğrulamalı;
   geçerli işlem için `verified`, `productId`, `source`, `transactionFingerprint`
   ve `entitlementId` döndürmelidir. Mağaza sırları uygulamaya gömülmez.
5. Sandbox'ta başarılı satın alma, geri yükleme, iptal, bekleme, ağ kesintisi,
   doğrulama reddi ve yinelenen işlem teslimatı kontrolü. Gerçek para harcayan
   işlem bu çalışma sırasında gerçekleştirilmedi.

Bu depoda çalışan bir doğrulama sunucusu veya yapılandırılmış mağaza ürünü
bulunmadığından, yapılan kod değişikliği gerçek tahsilatın açıldığı anlamına
gelmez. Doğrulama yapılandırması yokken uygulama ödeme ekranını açmadan durur.

Tek seferlik kalıcı hak modeli [Google Play tek seferlik ürün belgelerinde](https://developer.android.com/google/play/billing/one-time-products)
ve [Apple tüketilmeyen satın alma belgelerinde](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
tanımlanır. Mağaza fiyatı ayrı bir yapılandırmadır:
[App Store Connect satın alma yönetimi](https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases).
