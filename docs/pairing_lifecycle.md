# Oda cihazında eşleştirme yaşam döngüsü

Oda telefonu en fazla **5 ebeveyn cihazını hatırlar** ve aynı anda en fazla
**5 farklı ebeveyn cihazına yayın oturumu açar**. Ses ve görüntüyü birlikte alan
bir telefon tek yayın kontenjanı kullanır. Bildirim bağlantısının ayrı bağlantı
bütçesi vardır; aynı telefondaki ek bağlantılar yeni cihaz sayılmaz.

| Senaryo | Beklenen davranış |
| --- | --- |
| İlk eşleştirme | Tek kullanımlık QR doğrulanır; kayıt diske yazılmadan başarı dönmez. |
| Sonraki telefon | Kullanılan QR ekranda otomatik yenilenir; kayıtlı cihaz listesi canlı güncellenir. |
| Uygulama yeniden açılır | Kayıtlı cihazların kimlikleri, adları, ilk eşleşme ve son bağlantı bilgileri korunur. |
| Kayıtlı telefon yeniden bağlanır | Geçerli saklanmış anahtarla QR taramadan bağlanır. Yeni cihaz kontenjanı tüketmez. |
| Kayıtlı telefon yeniden QR tarar | Aynı kayıt, saklanmış anahtarın doğrulanmasıyla yenilenir. Sahibinin verdiği ad ve ilk eşleşme tarihi korunur. |
| Aynı kimliği bildiren başka telefon | Eski anahtarın sahipliğini kanıtlayamazsa mevcut kaydı değiştiremez. Yer varsa farklı kimlik verilir; liste doluysa reddedilir. |
| Altıncı cihaz eşleşmek ister | HTTP 409 `MAX_TRUSTED_CLIENTS_REACHED`; mevcut cihazların kaydı değişmez. Önce oda telefonundan bir cihaz kaldırılmalıdır. |
| Altıncı eşzamanlı yayın | HTTP 429 `MAX_ACTIVE_CLIENTS_REACHED`; eşzamanlı isteklerde de beş sınırı aşılmaz. |
| Uzun süre kullanılmayan anahtarın süresi dolar | Mevcut 60 günlük anahtar ömrü korunur. Son 7 günde normal bağlantı akışı yenilemeyi dener; süre dolmuşsa yeni QR gerekir. |
| Yayın durdurulur | Yayın kontenjanı geri verilir; cihaz hatırlanmaya devam eder. |
| Tek cihaz kaldırılır | Yetki hemen iptal edilir. Ses, görüntü, konuşma ve bildirim bağlantıları kapatılır; diğer cihazlar çalışmaya devam eder. |
| Tüm cihazlar kaldırılır | Tüm erişimler iptal edilir. Tekrar bağlanmak için yeni QR eşleştirmesi gerekir. |
| Silme kaydı başarısız olur | O anki erişim engellenir. Listede kaydetme bekleyen satır ve yeniden deneme imkânı kalır. Kalıcı silme tamamlanmadan yeniden başlatma sonrasında silinmiş olduğu varsayılmaz. |
| Ad değiştirme kaydedilemez | Önceki ad geri yüklenir; eşzamanlı erişim iptali geri alınmaz. |
| İstek kuyrukta beklerken cihaz silinir | Yayın başlatma/durdurma ve bildirim bağlantısı, işlem sırasında yetkiyi tekrar doğrular. Silinmiş yetkiyle oturum canlandırılamaz. |

Ebeveyn tarafında anahtarlar güvenli depoda, oda telefonunda yalnızca anahtar
özetleri ve cihaz bilgileri saklanır. Yeniden eşleştirmede hatırlanmış anahtar,
yalnızca aynı oda kimliği ve aynı adres/port için gönderilir; QR içindeki oda
kimliği tek başına anahtarı başka adrese göndermek için yeterli değildir.
Adres değiştiğinde mevcut keşif ve bağlantıyı yenileme akışı kullanılır.

Cihaz yönetimi hem eşleştirme hem ayarlar ekranındadır. Kayıtlı/yayın alan
sayıları, son bağlantı zamanı, ad değiştirme ve erişimi kaldırma işlemleri
Türkçe, İngilizce, Çince, Hintçe, İspanyolca, Fransızca, Almanca ve Arapçada
uygulamanın yerel sayı/tarih/saat biçimlerini kullanır.

Otomatik doğrulamalar depo yeniden yükleme, başarısız/gecikmiş yazma,
eşzamanlı istekler, gerçek yerel HTTP/WebSocket uçları, QR yenileme ve sekiz
dilde dar ekran yerleşimini kapsar. Beş fiziksel telefonla uzun süreli medya
yükü testi, bu otomatik doğrulamaların yerini tutmadığı ayrı bir cihaz testidir.

## 6 Eylül 2026 doğrulaması

- Tam Flutter paketi: 925/925. Ardından gelen iki WebSocket regresyonunu içeren
  dosya: 7/7; son isim/kimlik değişikliklerini içeren odak paketi: 22/22. Bu
  koşumlar örtüşür, sayıları birbirine eklenmez.
- Son `flutter analyze --no-pub` ve `git diff --check`: temiz.
- Son Android profile APK derlendi, LG H870 / Android 9'a veriler korunarak kuruldu.
  Eşleştirme ve kayıtlı cihaz ekranı fiziksel cihazda incelendi.
- Başlangıç listesi boşken beş ayrı host test kimliği LG ile eşleştirildi.
  Altıncı eşleştirme HTTP 409 ile reddedildi.
- Gerçek LG kamera/mikrofonundan beş host istemcisine eşzamanlı görüntü ve ses:
  5 aktif yayın, 5 video, 5 ses, toplam 10 medya bağlantısı; on akışın tümünden
  veri alındı. Yaklaşık 12 saniyelik ölçüm USB üzerinden yönlendirilen yerel HTTP
  bağlantısıdır; beş fiziksel ebeveyn telefonu veya Wi-Fi yük testi değildir.
- LG uygulaması zorla durdurulup yeniden açıldığında beş eski anahtar da HTTP 200
  aldı. Kayıtlar ve yetki yeniden eşleştirmeden geri yüklendi.
- LG arayüzünden test cihazları kaldırılırken açık gerçek ses ve görüntü
  akışları sunucu tarafından kapatıldı; beş eski anahtar HTTP 401 aldı.
  İkinci zorla durdurma/yeniden açma sonrasında da beşi reddedildi.
- Oluşturulan test eşleştirmeleri kaldırıldı. Erişim anahtarları, ortam sesi ve
  kamera görüntüsü rapora eklenmedi.

Sayısal cihaz sonucu: [pairing_lg_h870_2026-09-06.json](reports/pairing_lg_h870_2026-09-06.json).
