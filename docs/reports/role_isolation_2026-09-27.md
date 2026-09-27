# Client / Server modlarının kesin ayrımı

Tarih: 27 Eylül 2026. Başlangıç: `60af3ef`.

## Mod geçişi sözleşmesi

Tek seferde yalnız bir modun runtime'ı çalışabilir. Geçiş sırasında önceki ekran
kaldırılır; önceki modun kapanışı ve native kaynakların bırakılması doğrulanmadan
yeni runtime oluşturulmaz.

1. Ebeveynin oda lisansı sorguları/aktarım tekrarları durdurulur; açık LAN
   istekleri kesilir. Geç yanıtlar önceki oturumu yeniden etkinleştiremez.
2. Eski runtime yeni işlemlere kapanır. Kamera, mikrofon, ses çıkışı, yayın,
   talkback, bildirim bağlantısı ve keşif kaynakları bırakılır. Aynı anda yapılan
   dispose çağrıları devam eden kapanışı bekler.
3. Önceki ekranın widget kapanışları da geçişe dahildir. Sadece bir sonraki
   Flutter frame'ini beklemek, asenkron medya kapanışını tamamlanmış saymaz.
4. Native snapshot; server/alert/media/playback taleplerinin, capture/output
   sahipliğinin ve foreground servisin bittiğini doğrular. Denetim yalnız geçiş
   sırasında çalışır; normal kullanımda yeni sürekli polling eklenmez.
5. Bundan sonra eşleştirme kaydı temizlenir ve yeni rol kaydedilir. Yeni modun
   composition root'u yalnız bu kapı açıldıktan sonra çağrılır.

Bir kaynak kapanışı başarısızsa veya zaman aşımına uğrarsa yeni mod başlatılmaz.
Önceki runtime da yeniden oluşturulmaz: kapanmamış kaynağın üstüne ikinci bir
sahip bindirilmez. Kullanıcıya ayrı, yerelleştirilmiş kapanış hatası gösterilir.
Tekrar deneme kapanışı yeniden doğrular; kalıcı native hata durumunda uygulamayı
tamamen kapatıp açmak gerekir. Rol kaydı yazımı gibi kapanıştan sonraki hatalarda
önceki mod, kaynakların kapandığı bilindiği için yeniden kurulabilir.

Uygulama ömürlü mağaza işlem sahibi korunur: açılmış ödeme tamamlanıp hak kalıcı
kaydedilebilir. Bu, diğer modun kamera/izleme/bildirim/oda iletişimini çalıştırmaz.
Client kapalıyken aile lisansının LAN aktarımı yapılmaz. Bekleyen teslimat ancak
Client tekrar seçilip geçerli oda oturumu bağlandığında devam eder.

## Kapatılan boşluklar

- AppBootstrap kapanış hatasında eski runtime referansını bırakıp yeni bir
  runtime oluşturabiliyordu; artık kapanış sahibi tutulur ve geçiş engellenir.
- Önceki rol izolasyonu testi yalnız test içindeki bir `switch`i çalıştırıyordu.
  Yerine gerçek AppBootstrap, runtime factory çağrıları, bekletilen kapanışlar
  ve native servis durumu üzerinden entegrasyon testleri konuldu.
- App ömürlü satın alma koordinatörü server modunda da eski odalara tekrar
  isteği gönderebiliyordu; açık client modu artık zorunlu bir koşuldur.
- Client kapanışı geç başladığı veya timeout'u yuttuğu için yeni işler
  kabul edilebiliyordu; runtime ilk await öncesi mühürlenir ve bağımsız
  kaynakların kapanışı birlikte başlatılır.
- Server eşleştirme kuyruğu ve geç dönen capture başlangıçları terminal
  kapanışa dahil değildi; kuyruklar ve gerçek native edinim işleri beklenir,
  toparlanma timer'ları kapanıştan sonra kaynak açamaz.
- Discovery, HTTP oda kontrolleri ve WebRTC kaynaklarının geç edinim/kapanış
  davranışları mod sahibinin sonlandırılmasına bağlandı.
- PCM ses ve video yeniden bağlanma beklemeleri iptal edilebilir hâle getirildi;
  kapanmış modun gecikme timer'ları arka planda uyanmaz.
- Gerçek Android testinin yakaladığı kapanış sırası düzeltildi: birleşik medya
  kaynağı kapanırken eski mikrofon talebi yeniden gönderilemiyor. Native medya
  EventChannel dinleyicisi de stop sırasında bırakılıyor ve sonraki kullanımda
  yeniden bağlanıyor.

## Doğrulama

Son kaynak ağacında:

- `flutter test --no-pub`: **1345 test geçti**.
- `dart analyze`: **No issues found**.
- `dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool/tests`:
  **399 dosya, değişiklik yok**.
- `git diff --check`: temiz.
- `flutter build appbundle --release`: başarılı, `app-release.aab` (92.3 MB).
- `flutter build apk --debug --target=lib/main.dart`: başarılı; test dışı APK
  varsayılan özelliklerle `adb install -r` üzerinden telefona geri yüklendi.

Yerel test/analiz kayıtları `build/role_final_flutter_tests.log`,
`build/role_final_analyze.log` ve `build/role_final_format.log` dosyalarında.
Release derlemesi `build/role_final_android_release.log` içinde kayıtlıdır.
Widget fixture'ları kendi test döngüsü içinde kapanışı bekler; fake-async
kuyrukların test dışındaki teardown'da yanlış timeout üretmesi giderildi.
Kapanış hataları üretim kodunda yutulmuyor, UI assertion'ları gevşetilmedi.

Ana regresyonlar:

- Server→Client ve Client→Server sırasında gecikmiş dispose yeni factory'yi
  bekletir; aynı anda iki mod oluşmaz.
- Native arka plan işi sürerken Dart dispose bitse de yeni mod oluşmaz.
- Hatalı kapanış eski veya yeni runtime'ı yeniden kurmaz; eşleştirme/rol kaydı
  erken değiştirilmez.
- Geçiş sırasında uygulama widget'ı kapatılırsa kapanış sahibi kaybolmaz.
- Geç store başarısı lisansı korur, pasif client üzerinden LAN işi başlatmaz.
- Geç discovery, mikrofon/kamera ve WebRTC başlangıçları kapanıştan kaçamaz.
- Kapanış hatası ekranının dokuz dilde, dar ekranda ve iki kat metin ölçeğinde
  taşmaması ve tekrar deneme düğmesinin erişilebilirliği doğrulanır.

### Gerçek Android cihaz

LG H870 üzerinde iki Client → Server → Client döngüsü geçti. Her server
oturumunda gerçek kamera ve mikrofon verisi alındı. İlk döngü 2 video frame'i ve
30 PCM chunk, ikinci döngü 1 frame ve 14 chunk üretti. Client ekranına dönüşte ve
son temizlikte kamera, mikrofon, ses çıkışı, server/alert talepleri ve foreground
servis kapalıydı. Factory sayıları da her adımda yalnız seçilen modun kurulduğunu
doğruladı. Geçiş süreleri 3134 ve 1981 ms; bu ölçüler onay ekranının animasyonunu
ve test beklemelerini de içerir, yalnız native kapanış süresi değildir.

Kanıt: [yalnız durum/sayaç içeren cihaz raporu](role_isolation_device_2026-09-27.json).
Görüntü veya ses kaydedilmedi. Son koşu mevcut uygulamanın VM'ine bağlandı;
uygulama test sonunda kurulu kaldı ve Android servis listesi boştu.
Tekrar çalıştırma: [güvenli cihaz testi yönergesi](../../integration_test/role_isolation_device.md).

İlk cihaz koşusu eski mikrofon talebinin kapanış sırasında tekrar gönderilmesini
yakaladı. İlgili düzeltme ve regresyon testi eklendi. Bir sonraki denemedeki
kaçırılan modal dokunuşu ve daha sonraki denemedeki Android izin diyaloğu test
kurulumunda düzeltildi; son iki döngü kesintisiz geçti.

### Test aracının cihaz verisine etkisi

İlk denemelerde kullanılan varsayılan `flutter drive` temizliği uygulamayı
kaldırdı. Bellekte tutulan test tercihleri bu araç davranışına karşı koruma
sağlamadı. Başlangıçta kayıtlı mod Client'tı ve eşleştirme yoktu; önceki tüm
yerel ayarların yedeği bulunmadığı için eksiksiz geri yükleme iddiasında
bulunulamıyor. Kullanıcı çalışma sırasında bilgilendirildi. Son koşu
`--use-existing-app --keep-app-running` ile yapıldı; tekrar kullanım yönergesi
de bu yöntemi zorunlu kılıyor.

Normal uygulama geri yüklendikten sonra ebeveyn ekranından Client seçildi.
Kalıcı `app_role=client`, eşleştirme kaydı bulunmaması ve Android servis
listesinin boş olması doğrulandı. Cihaz başlangıçtaki gibi launcher ekranına
bırakıldı. Bu işlem uygulamayı ve bilinen rolü geri getirir; yedeği olmayan
önceki ayarların eksiksiz kurtarıldığı anlamına gelmez.

iOS'ta fiziksel cihaz testi, iki telefon arasında uzun yayın ve uzun süreli pil
ölçümü bu çalışmada yapılmadı. Android'deki kısa mod geçişi kabulü bu ölçümlerin
yerine geçmez.
