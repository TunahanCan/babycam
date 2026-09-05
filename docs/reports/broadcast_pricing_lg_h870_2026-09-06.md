# Yayın denemesi ve ömür boyu erişim doğrulaması

Ürün kuralı: oda telefonunda toplam iki saat ücretsiz ses/görüntü veya bildirim
takibi, ardından Türkiye hedef fiyatı 350 TL olan tek seferlik ömür boyu hak.
Beş eşzamanlı ebeveyn sınırı korunur. Yerel önizleme ve bağlantısız bekleme
ücretsizdir. Ürün ve mağaza hazırlığı: [fiyatlandırma notu](../broadcast_pricing.md).

## Otomatik senaryolar

- Beş izleyicinin ortak kullanım süresi; iki saat sınırı; oturum, süreç ve saat
  değişimlerinde kalıcılık; depolama hatasında hatalı erişim verilmemesi.
- Ses/görüntü, WebRTC ve yalnız bildirim takibinde erişim kontrolü; yavaş medya
  açılışı sırasında süre dolması; erişimi kaldırılmış akışın tekrar açılmaması.
- Son aktarım kapandığında sayacın durması ve yeniden bağlantıda devam etmesi.
- Yerel önizlemenin kullanım süresini tüketmemesi ve süre dolduktan sonra da
  kullanılabilmesi.
- Doğrulama yapılandırılmadığında tahsilat ekranının açılmaması; geç gelen
  doğrulanmış satın alma ve geri yükleme sonuçları; mağaza sorgusu takılırken
  yerel erişim kontrolünün devam etmesi; kapanışta bekleyen sorguların iptali.
- Sekiz dilde dar ekran, fiyat ve kalan süre metinleri; gerçek mağaza fiyatının
  gösterilmesi ve ebeveyn telefonunda ikinci bir ödeme istenmemesi.
- Yalnız bildirim takip eden ebeveynde ilk bağlantı veya aktif takip sırasında
  süre sonu; doğrulanmış kilitte tekrar denemenin durması, normal ağ hatalarında
  devam etmesi; kilit açıklamasının dokuz desteklenen yerel ayarda gösterilmesi.

## Son doğrulama

- Tam Flutter test paketi: **974/974 geçti**.
- `flutter analyze --no-pub`: sorun yok.
- Web sitesi kaynak doğrulaması: 2 sayfa, 8 dil, 234 çeviri anahtarı.
- Yerelleştirilmiş web sitesi derlemesi: 16 sayfa; mevcut tasarım ve görseller
  korundu.
- LG üzerindeki fiyat gösterimi düzeltmesinden sonra ilgili dil ve ekran
  testleri: **63/63 geçti**; değişen dosyaların analizi temiz.

## LG H870 / Android 9

- Profile APK uygulama verileri korunarak kuruldu.
- USB üzerinden yönlendirilmiş yerel HTTP bağlantısında bir host ebeveyn ile
  30 saniye ses, görüntü ve olay WebSocket'i testi geçti. İkinci fiziksel ebeveyn
  telefonu kullanılmadı; gerçek uyarı olayı üretilmedi.
- 152 geçerli JPEG kare, bozuk JPEG yok; 958.720 PCM byte, kırpılmış örnek yok.
  Görüntüde en uzun alım aralığı 395 ms, seste 81 ms. Bu değerler fiziksel
  görüntüleme/oynatma gecikmesi değildir.
- Toplam kullanılan süre **30.178 ms** oldu; üç aktarım kanalı süreyi katlamadı.
  Bağlantılar kapanınca `active=false`; bekleme ve force-stop/yeniden açılış
  sonrasında kullanılan süre aynı kaldı.
- Satın alma düğmesi, yapılandırma eksikliğinde mağaza ödeme ekranı açmadan
  Türkçe açıklama gösterdi. Gerçek para harcanmadı.
- Son APK'da Türkçe fiyat **350 TL** olarak ekranda doğrulandı; kullanılan süre
  son paket güncellemesinde de korundu. APK SHA-256:
  `16f8ad359c54c1dc3b6259ef4a6b439a32165e3e4268b33207bbbfdedb3e7c14`.
- Test ebeveyni oda telefonu ayarlarından kaldırıldı; eski kimlik HTTP 401 aldı.
  Kullanıcının uygulama verileri veya deneme sayacı sıfırlanmadı.

İki saat sınırı kontrollü saatle otomatik test edildi; gerçek cihazı iki saat
açık tutarak yapılan bir ödeme testi değildir. Apple/Google gerçek veya sandbox
satın alması yapılmadı. Bu depoda mağaza ürünü ve doğrulama sunucusu ayarları
bulunmadığından gerçek tahsilat etkin değildir. Uygulama verilerini silmek yerel
deneme kaydını da siler; yeniden kuruluma dayanıklı hesap tabanlı deneme kaydı
bu değişikliğin parçası değildir.
