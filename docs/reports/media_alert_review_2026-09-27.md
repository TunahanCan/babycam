# MiuCam ses/video akışı ve bildirim incelemesi — 27 Eylül 2026

Bu takip incelemesi canlı ses/video aktarımı, analiz maliyeti, yanlış/tekrarlı
bildirim ve oda değişimi tutarlılığına odaklanır. Yerel ağ kullanım tercihi
korundu; şifreleme bu çalışmanın kapsamı değildir. Önceki çalışma alanı
değişiklikleri korunmuştur. Yayın veya mağaza yüklemesi yapılmadı.

## Düzeltilen bulgular

| Öncelik | Bulgu | Son davranış ve doğrulama |
| --- | --- | --- |
| P1 | Native ses durum sorgusu PCM yazma yolunda bekleniyordu; gecikirse oynatım ve başlangıçta ağ tüketimi duraklıyordu. | Durum sorgusu oynatımı bekletmiyor; son sonuç kullanılıyor ve native çağrı gerçekten tamamlanana kadar yalnız bir sorgu bekliyor. Süresi aşılmış durum sorgusu sırasında ses yazımı ve durdurma regresyonu geçti. |
| P1 | MJPEG/WAV için `close().timeout()` yalnız beklemeyi bitiriyor, tamponu dolu TCP bağlantısını açık bırakabiliyordu. | Kapatmada `HttpResponse.deadline` gerçek bağlantıyı da sonlandırıyor. Okumayan istemci ve 8 MiB bekleyen çıktı kullanan iki gerçek TCP testi bağlantının kapandığını doğruladı. |
| P1 | Kalibrasyonda öğrenilmiş yüksek ortam sesi, yeni olay olmadan yüksek ses bildirimi üretebiliyordu. | Mutlak ses eşiğine ek olarak ortam tabanının en az 6 dB üstünde artış gerekiyor. Sabit gürültü ve küçük artış sessiz kaldı; belirgin yeni artış bildirim üretti. Negatif senaryo önceki kodda başarısızdı. |
| P1 | Durum endpoint'i, cooldown bilgisi okurken zaman çapaları değişebildiği için tekrar bildirim süresini kısaltabiliyordu. | `remainingMs` salt okunur oldu; saat geri alma düzeltmesi yalnız yeni olay değerlendirilirken yapılıyor. Farklı ses/video zamanlarıyla durum okuma, ayar yenileme ve 60 saniyelik bekleme testi geçti. Eski kod hem birim testinde hem üretim hattı senaryosunda başarısızdı. |
| P2 | Canlı izleme için açık kamera/mikrofon, bildirim analizi kapalıyken de özellik çıkarımına devam ediyordu. | Ses ve hareket analizi ayrı talep kontrollerine bağlandı. Kapalı durumda analiz pencere/kare sayısı sıfır; tekrar açılışta eski süre kanıtı temizleniyor. Gerçek HTTP MJPEG/WAV akışları analiz kapalıyken de çalışıyor. |
| P2 | Video güvenilirliği kesildiğinde, bozuk karede veya saat geri gittiğinde eski hareket bilgisi sonraki ağlama olayına taşınabiliyordu. | Hareket ilişkisi temizleniyor; gelecekte görünen zaman damgası yeni olaya katılmıyor. Negatif testler önceki kodda başarısızdı. |
| P2 | Analizden çıkan olay async teslimat kuyruğundayken bildirim talebi kapatılabiliyordu. | Göndermeden hemen önce ilgili ses/video talebi tekrar kontrol ediliyor; kapatılmış analizin bekleyen olayı gönderilmiyor. |
| P1 | Oda değişirken eski teslimat yeni odanın replay cursor'unu değiştirebiliyor; eşzamanlı değişiklikler eski odayı yeniden açabiliyordu. | Eski bağlantı boşaltılıyor, nesil kontrolüyle geç sonuçlar eleniyor; son oda isteği kazanıyor. Aynı endpoint'te cihaz kimliği değişimi de yeni oturum sayılıyor. |
| P2 | Gönderilmiş bildirimin aktif listede hemen görünmemesi veya kullanıcı tarafından kapatılması başarısız teslimat sayılabiliyordu. | Native API'nin kabul ettiği gönderim tekrar gönderilmiyor. Gerçek Android testinde ilk `verifiedActive=false` sonucundan sonra bildirim aktif listede görüldü. Bu anlık sorgunun teslimat kanıtı olmadığını cihazda da doğruladı. |
| P2 | Aynı bildirime sonraki gerçek dokunuş engelleniyor; eski odanın bildirimi yeni odanın izleme ekranını kapatabiliyordu. | Gerçek dokunuşlar çalışıyor, tekrarlanan açılış intent'i ayıklanıyor. Eşleştirme sırasında veya mevcut oda geçmişinde olmayan bildirime dokunulduğunda başka odaya yönlendirme yapılmıyor. Widget regresyonu mevcut izleme rotasını da kontrol ediyor. |
| P2 | Android bildirim kanalları her uyarıda tekrar oluşturuluyordu. | Kanal metadatası locale başına güncelleniyor; izin kontrolü devam ediyor. Bildirim listesinde aynı sunum verisinin tekrar üretilmesi de kaldırıldı. |

Başlıca kaynaklar:

- [Ses oynatımı](../../lib/features/client/media/client_live_audio_pipeline.dart),
  [MJPEG](../../lib/features/server/media/mjpeg_stream_service.dart),
  [WAV](../../lib/features/server/media/wav_audio_stream_service.dart).
- [Analiz koordinasyonu](../../lib/services/server/media_analysis_coordinator.dart),
  [üretim hattı](../../lib/services/server/miucam_server_media_controllers.dart),
  [uyarı motoru](../../lib/analysis/alert/alert_engine.dart),
  [bekleme politikası](../../lib/analysis/alert/cooldown_policy.dart),
  [olay birleştirme](../../lib/analysis/alert/episode_notification_aggregator.dart).
- [Bildirim dinleyicisi](../../lib/features/client/alerts/client_alert_listener.dart),
  [teslimat koordinasyonu](../../lib/features/client/alerts/client_alert_delivery_coordinator.dart),
  [native bildirim servisi](../../lib/services/notification_service.dart),
  [bildirim yönlendirmesi](../../lib/features/client/client_home_screen.dart).

## Doğrulama

- Birleşik paket: **1.107/1.107 Flutter testi geçti**. Önceki incelemenin
  1.090 testine ek olarak 17 regresyon var. Mevcut ekran matrisi, bildirim
  ekranları ve lokalizasyon testleri bu koşuya dahildir.
- `flutter analyze --no-pub`: sorun yok. 352 Dart dosyasının format kontrolü
  ve `git diff --check` geçti.
- Sentetik PCM/luma senaryoları: kalibrasyon, sabit gürültü, sabit ton, kısa
  ses, sürekli ağlama benzeri ses, ışık değişimi, yerel hareket, kesinti,
  talep kapatma/açma, cooldown ve ayar yenilemesi. Ninni ve ebeveyn konuşması
  sırasında analiz bastırılırken ses aktarımı devam ediyor. Sonraki sürekli
  ağlama örneği hâlâ bildirim üretiyor.
- Kaynak sınırı: 30 FPS girişte saniyede üç tam hareket analizi; 16 kHz,
  20 ms ses paketlerinde kararlı durumda saniyede en fazla yaklaşık dört
  özellik çıkarımı. Kapalı analizde bu ağır işlemler sıfır.
- Android LG H870 / Android 9 üzerinde son kaynaklardan **profile** derlemesi
  ve gerçek AudioTrack/bildirim testi geçti. Üç oynatım gözlem süresi
  3.169 / 3.115 / 3.104 saniye; iki yeniden başlatma. Her kararlı oynatım
  aralığında underrun artışı sıfır; durdurmada native oynatıcı kapandı ve
  bekleyen yazmalar sıfırlandı.
- Gerçek Android test bildirimi aktif listeden doğrulandı ve yalnız kendi
  kimliğiyle temizlendi. Ayrı `com.miucam.app.review` paketi kullanıldı;
  test öncesi bulunmadığı, testte yeni kurulduğu doğrulandı ve bitişte kaldırıldı.
- Bu tur Kotlin/Swift kaynaklarında yeni değişiklik yapılmadı; önceki
  incelemenin native değişiklikleri korundu. Bu tur yeni iOS/XCTest sonucu yok.

Ortam: Flutter 3.44.2 / Dart 3.12.2, Linux. Yerel loglar ve fiziksel sonuç:
`build/media_alert_review_2026-09-27/`. Makine özeti:
[media_alert_review_2026-09-27.json](media_alert_review_2026-09-27.json).

## Kalan doğrulama sınırları

Bu testler gerçek bebek/konuşma/TV kayıtlarından oluşan etiketli bir veri
kümesinde yanlış alarm oranını ölçmez. Sınıflandırıcı sezgiseldir; “ağlama
benzeri” olasılık dili korunmuştur. +6 dB koşulu sabit gürültüye karşı koruma
sağlar, fakat yüksek taban gürültüsünde daha küçük gerçek artışları kaçırma
dengesi gerçek ortam kayıtlarıyla ölçülmelidir. Kalibrasyon hiç kullanılabilir
örnek bulamadan zaman aşımına uğrarsa mevcut -55 dBFS yedek tabanı kullanılır;
bu başlangıç koşulu için cihazlar arası doğruluk ölçülmedi.

Fiziksel ses testi kontrollü localhost PCM kaynağı kullanır; mikrofon,
iki telefon arasındaki Wi-Fi, akustik kalite veya uzun süreli bağlantı kabulü
değildir. Telefon USB'den şarj oluyordu (kontrol anında %8, 31,3 °C).
Pil tasarrufu yüzdesi, saatler süren termal/bellek kararlılığı veya sıfır yanlış
alarm garantisi çıkarılamaz. Analiz hâlâ Dart isolate'ında senkron çalışır;
kapalı talep ve analiz sıklığı sınırları gereksiz işi azaltır, uzun süreli düşük
donanım kabulünün yerini tutmaz.

Önceki genel ekran/performans doğrulaması:
[27 Eylül raporu](performance_ui_review_2026-09-27.md).
