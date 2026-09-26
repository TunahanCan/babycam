# MiuCam performans ve ekran incelemesi — 27 Eylül 2026

İnceleme tabanı: `6687e90`. Değişiklikler çalışma alanındadır; yayın veya
mağaza yüklemesi yapılmadı. Ortam: Linux, Flutter 3.44.2 / Dart 3.12.2,
LG H870 / Android 9. README/CI'daki Flutter 3.44.4 ile birebir aynı SDK değildir.

## Düzeltilen bulgular

| Öncelik | Sorun | Düzeltme ve kanıt |
| --- | --- | --- |
| P1 | Kalıcı kamera/mikrofon hatasında saniyede 10 kez yeniden deneme donanımı ve işlemciyi gereksiz meşgul ediyordu. | `MediaRuntimeController`: iptal edilebilir tek timer, 100 ms–5 s artan bekleme; başarıda sıfırlama. Kalıcı arıza ve toparlanma testleri. |
| P1 | Aynı kamera kapatma hatası iki ayrı yoldan timer kurarak tekrarları çoğaltıyordu. | Kamera başına tek temizleme timer'ı, 250 ms–5 s bekleme. Eski kod 650 ms içinde 5 dispose çağrısıyla regresyon testini kırdı. |
| P1 | Mikrofon akışı hatasız ama beklenmedik biçimde kapanınca analiz ses kesintisini bilmiyordu. | Yeniden başlamadan önce analiz sahibine kesinti bildiriliyor; kesinti öncesi/sonrası verinin aynı olayda birleştirilmesi önleniyor. |
| P1 | Android ses kuyruğu kapatılınca çalıştırılmadan atılan yazma işlemlerinin platform yanıtları tamamlanmıyordu. | İptal edilebilir yazma görevi, tam bir kez sonuçlandırma, eski nesle ait sayaç temizliği. Başlatma/temizleme hatalarında AudioTrack bırakılıyor. |
| P1 | Sessize alınmış izleme ekranı arka plandan döndükten sonra ses açılması, ses kanalı bulunmayan oturumda etkisiz kalabiliyordu. | Gerekirse oturum ses kanalıyla yeniden kuruluyor; eski sessiz oturumda oynatıcı açılmıyor. |
| P1 | WebRTC bağlantısının kurulması veya sıfır sayaçlı ilk istatistik gerçek medya alınmış gibi gösteriliyordu. | Video sağlığı çözümlenmiş kare artışına, ses sağlığı alınan ses verisine dayanıyor. |
| P2 | Oda sesi/parça değişiminde yakalanmayan async hatalar, üst üste komutlar ve yanlış başlangıç değerleri vardı. | Bekleyen işlem kilidi, hata geri bildirimi, doğrulanmış değerlere dönüş; geç yanıtlar kapanmış ekranı güncellemiyor. Polling kullanıcının sürüklemesini/seçimini ezmiyor. |
| P2 | Ayar yazımı `false` döndüğünde UI başarılı sanıyor; SharedPreferences önbelleği diskte olmayan değeri gösteriyordu. | Sunucu ve istemci yazımları sıralandı; başarısız sonuç hata oluyor, önbellek yeniden okunuyor. Dil/bölge tek kayıtta tutuluyor; eski kayıtlar okunabiliyor. Android servis bildirimi aynı kaydı izliyor. |
| P2 | Bir algılama profili kısmen kaydedildiğinde ekrandaki ayarlar ile çalışan analiz farklı kalabiliyordu. | Başarısız çoklu işlemden sonra da analiz kalıcı ayarlardan yenileniyor; kullanıcıya hata gösteriliyor. |
| P2 | Dar ekranda büyük yazı ve uzun çeviriler rol rozetini, sunucu önizleme durumunu ve istemci bağlantı kartını taşırıyordu. | Rozet metni esnek genişlikte; kamera kapalı/hazırlanıyor mesajı doğal yükseklikte; istemci yükleniyor/hata kartı yazı ölçeğine göre genişliyor. Hintçe/Fransızca/İspanyolca ve istemcide 6,8–68 px taşmalar regresyonla doğrulandı. |
| P2 | Karanlık QR ekranından dönünce durum çubuğu simgeleri açık arka planda beyaz kalıyordu. | Görünür ekrana bağlı `AnnotatedRegion` kullanılıyor: açık ekranlarda koyu, tam ekran/gece saatinde açık simgeler. Gerçek QR ekranı push/pop ve dört UI regresyonu. |

iOS ses çıkışı, PCM16LE verisini standart Float32 grafik biçimine dönüştürecek
şekilde sağlamlaştırıldı; medya servisi sıfırlama hatasında ses sahipliği
bırakılıyor. Dört XCTest eklendi. Float32 değişikliği **cihazda yeniden üretilmiş
bir iOS çökme düzeltmesi olarak sayılmıyor**; bu Linux ortamında Xcode/iOS testi
çalıştırılamadı. Standart biçim için [Apple AVAudioFormat belgesi](https://developer.apple.com/documentation/avfaudio/avaudioformat).

## Doğrulama kapsamı

- Başlangıç test paketi: 1.023 test geçti; başlangıç statik analizi temiz.
- Son birleşik paket: **1.090/1.090 Flutter testi**, **17/17 Android JVM testi**
  geçti. 67 yeni Flutter regresyonu eklendi. Son `flutter analyze --no-pub`
  temiz; 348 Dart dosyasının format kontrolü ve `git diff --check` geçti.
- `flutter build appbundle --release` ile **imzasız** 91,5 MB AAB üretildi;
  son `--no-pub` doğrulama komutu çıkış kodu 0 ile tamamlandı. İlk denemede
  testten kalmış üretilen plugin kaydı derlemeyi engelledi; Flutter'ın bağımlılık
  ve kayıt üretimi yenilenince derleme geçti. Mevcut Kotlin eklentisi geçiş
  uyarıları devam ediyor. Paket üretimi mağaza imzası/kabulü değildir.
- Yeni regresyonlar hata/iptal/sıralama davranışını sınar; yalnız kaynak metni
  kontrolü veya uygulama kodunun kopyası değildir.
- Ekran matrisi: 9 locale, 320×568 / %200 yazı ve 640×360 / %130 yazı.
  36 senaryo; rol seçimi, oda telefonunun dört sekmesi, önizleme aç/kapat,
  ebeveynin dört sekmesi, izleme ekranının hata/yeniden bağlanma durumlarındaki
  üç sekmesi ve kaydırma sonundaki içerikler kapsanır.
- Fiziksel testler ayrı `com.miucam.app.review` paketiyle yürütüldü.
  `com.miucam.app` adına kurulum, kaldırma veya veri temizleme komutu
  çalıştırılmadı.
  Bu çalışma sırasında kurulduğu doğrulanan test paketi bitişte kaldırıldı.
- İlk profile UI ölçümü: kaydırıcı p95 **34,650 ms**, liste kaydırma p95
  **24,109 ms**; mevcut eski cihaz kabul eşiği 35 ms. Bu sonuç 60 FPS'in
  bütün karelerde korunduğunu göstermez.
- Son kaynaklarla profile UI ölçümü de geçti: kaydırıcı **33,388 ms p95**
  (98 kare), kaydırma **26,910 ms p95** (159 kare). Her ikisi 35 ms sınırının
  altında. İki koşu aynı termal/şarj koşullarında yapılmış uzun süreli bir
  karşılaştırma değildir; bunlardan genel hızlanma veya pil tasarrufu yüzdesi
  çıkarılmıyor.
- Son sürümden Türkçe/Arapça **34 fiziksel ekran görüntüsü** alındı ve PNG'lerin
  okunabilirliği doğrulandı. Ana ekran, izleme, kontroller, hata kurtarma,
  ayarlar ve QR görünümleri görsel olarak incelendi. İki QR ekranı bağımsız
  ZXing çözücüsüyle bilgisayarda okunup schema/host/port/cihaz alanları doğrulandı;
  bu, ikinci fiziksel telefonla optik tarama kabulü değildir.
- Gerçek Android AudioTrack ile üç yaklaşık 3,1 saniyelik localhost ses
  oynatımı ve iki yeniden başlatma geçti. Kararlı aralıklarda underrun artışı
  sıfır; her durdurmada native oynatıcı kapandı. Gerçek Android test bildirimi
  aktif bildirim listesinden doğrulandı ve testin kendi bildirimi temizlendi.
- Bu fiziksel ses testi mikrofon, iki telefon arasındaki Wi-Fi aktarımı veya
  hoparlör/mikrofon akustik kalitesi testi değildir.

Ekran görüntüsü aracı da güncellendi: eski kısaltılmış QR fixture'ında zorunlu
kimlik/son kullanma alanları olmadığından yalnız hata görünümü oluşuyordu.
Araç artık uygulamanın güncel `PairingPayload` biçimini kullanıyor. Görsel
kontrollerde üretim widget'ları ve kontrollü örnek veriler kullanılır; fixture
görüntüsü gerçek kamera/eşleşme veya uçtan uca ağ testi sayılmaz.

## Açık yayın engelleri

Bu çalışma uygulamanın tamamen production ready olduğunu doğrulamaz.

1. **P0 — Yerel aktarım şifresiz:** `TransportConfig` hâlâ HTTP/WS kullanıyor.
   Token, ses ve görüntü için sunucu kimliği doğrulanmış HTTPS/WSS ve güvenli
   eşleşme geçişi gerekiyor.
2. **P0 — Fiziksel eşleşme onayı:** Eşleşme açıkken public durum endpoint'i nonce
   veriyor; aynı LAN'a erişim, QR'a eşdeğer fiziksel sahiplik kanıtı değildir.
   Manuel/keşif eşleşmesi oda telefonundaki onaya bağlanmalı.
3. **P1 — Gerçek satın alma kabulü:** Ürün/verifier yapılandırması ile satın
   alma, geri yükleme ve iade/iptal akışları gerçek sandbox hesaplarıyla
   doğrulanmış değil. Yapılandırılmamış sürüm ödemeyi açmıyor.
4. **Cihaz kabulü:** iOS derleme/XCTest, güncel Android sürümleri, iki fiziksel
   telefonla Wi-Fi kopma/dönüş ve uzun süreli pil/ısı/bellek testi tamamlanmadı.
   LG test sırasında USB'den şarj oluyor ve pil seviyesi %3–5 civarındaydı;
   bu koşudan pil ömrü veya termal kararlılık sonucu çıkarılamaz.

Önceki güvenlik/mağaza incelemesi:
[6 Eylül raporu](production_code_review_2026-09-06.md).

Makine tarafından okunabilir sonuçlar:
[doğrulama özeti](performance_ui_review_2026-09-27.json).
Yerel ayrıntılı loglar ve ekran görüntüleri `build/review_2026-09-27/` altında.
Örnekler: [düzeltilmiş izleme ekranı](../../build/review_2026-09-27/screens/tr/08_watch_live.png),
[başarılı QR görünümü](../../build/review_2026-09-27/screens/tr/15_server_qr_ip.png).
