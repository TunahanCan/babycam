# Ses / görüntü analizi ve bildirim lokalizasyonu — 5 Eylül 2026

Bu çalışma, önceki [LG doğrulamasının](lg_h870_validation_2026-09-05.md)
devamıdır. Mevcut medya düzeltmeleri korundu; analizden ebeveyn bildirimine
giden akış ve desteklenen tüm dil paketleri yeniden kontrol edildi.

## Kapsam

8 dil / 9 bölgesel seçenek: Türkçe, ABD İngilizcesi, Çince, Hintçe,
İspanyolca, Fransızca, Almanca, Arapça–Suudi Arabistan ve Arapça–Katar.
Yeni dil eklenmedi. Alıcı ebeveynin dili, oda telefonunun dilinden bağımsızdır.

Akış: kamera/mikrofon → güvenilirlik ve kalibrasyon → ağlama/yüksek ses/hareket
analizi → süre/tekrar/birleştirme kuralları → semantik olay ve metadata →
WebSocket + geçmiş/ACK/yeniden teslim → ebeveyn dilinde arayüz ve sistem bildirimi.

## Analiz düzeltmeleri

| Bulgu | Düzeltme / kanıt |
| --- | --- |
| Yeniden kalibrasyon eski ses penceresini kullanıyordu | Kalibrasyon ring buffer ve önceki özellikleri temizleyerek yalnız yeni sesle başlıyor. |
| Sessizlik ortam eşiğini aşırı düşürebiliyordu | Adaptif güncellemede kalibrasyondaki −65 dBFS tabanı korunuyor; önce −119,986 dBFS'ye düşebiliyordu. |
| Güvenilmez sesin iki yanındaki kısa parçalar birleşebiliyordu | Engine ve episode aggregator, güvenilmez aralıkta önceki ağlama kanıtını kesiyor. |
| Sürekli hareketin her karesi ayrı olay sayılabiliyordu | `motionBursts` hareket başlangıçlarını sayıyor; geçersiz görüntü ve ışık değişimi sürekliliği doğru kesiyor. |

Beş yeni regresyon önce başarısız oldu, düzeltmelerden sonra geçti. DSP ve
algılama eşikleri dile göre değişmiyor; dil yalnız sunumu belirliyor.

## Dil ve gösterim düzeltmeleri

- Eski veya eksik metadata içeren uyarılar, ebeveyn ekranında sunucunun
  dilindeki ham metne düşmüyor. Bilinen olayın yerel kısa açıklaması gösteriliyor;
  bilinmeyen olayda ayrıntının gösterilemediği açıklanıyor. Ham metin protokol ve
  saklanan geçmişte korunuyor; eksik ölçümler sıfırmış gibi üretilmiyor.
- Bilinen `messageKey`, kategori/başlık/gövdeyi tutarlı belirliyor. Yüksek ses,
  kısa ses ve ağlama aynı metinle etiketlenmiyor.
- Kuyrukta bekleyen, yeniden teslim edilen veya izin/plugin hazırlığı sırasında
  dili değişen bildirim, gönderim anındaki ebeveyn diliyle hazırlanıyor.
- Android bildirim kanalları dil değişince yenileniyor. Native foreground
  servis, uygulamanın kaydedilmiş dilini kullanıyor; etkin bildirim dil veya
  sistem konfigürasyonu değişiminde yenileniyor.
- Sayı, ondalık ayıracı, yüzde, süre ve çoğullar yerelleştirildi. SA/QA Arapça
  seçeneklerinde Arap rakamları kullanılıyor. ID, URL ve kullanıcı metinleri
  sayıya veya başka bir şablona dönüştürülmüyor.
- Uyarı saatleri ve gece saati yerel biçim ve sistemin 24 saat tercihini
  izliyor. Eski günlerin uyarılarında yerel tarih de gösteriliyor.
- Geçmiş ve uyarı kartları uzun çeviriler / büyük yazı için düzenlendi;
  Fransızcada saptanan yatay taşma giderildi. Arapça RTL kontrol edildi.
- Eski protokolün varsayılan oda adları ebeveyn dilinde gösteriliyor;
  özel oda adları korunuyor. Paylaşım metni üretimi yerelleştirildi.
- Android/iOS kaynak dil paketleri ve placeholder sayıları kontrol edildi.
  iOS mikrofon izni açıklaması oda yayını ve bas-konuş kullanımını anlatıyor.

## Doğrulama

| Kontrol | Sonuç |
| --- | --- |
| Son tam Flutter paketi | **889/889** |
| Analiz → JSON → DTO → alıcı dili | **9 × 9 × 5 = 405 kombinasyon**: ağlama, gerçek süreli episode, yüksek ses, hareket, ışık değişimi |
| Alıcı arayüzü | Her 9 locale için geçmiş ve izleme ekranı; eski yabancı dilde olay, büyük yazı, RTL, tarih/saat |
| Bildirim hedef grubu | 47 test; locale race, pending/replay, native kanal çağrıları ve paylaşım metni |
| L10n/native kaynak hedef grubu | 55 test; sayı/yüzde/süre, anahtarlar, placeholder sayıları ve platform kaynakları |
| Analyze / format | Temiz |
| Android | Profile APK ve imzasız release AAB oluştu; Kotlin/JVM **7/7** |
| Son LG LAN testi | 60 s; 303 kare, 1.919.360 PCM byte; ses p95 34 ms / max 87 ms, görüntü p95 296 ms / max 411 ms veri aralığı; parser hatası ve clipping 0 |

Hedef test sayıları tam paketin alt kümeleridir; birbirine eklenmemelidir.
İlk tam koşudaki eski `HH:mm` arayan kontrast testi, yerel tarih/saat etiketini
bulacak şekilde güncellendi; kontrast eşiği değiştirilmedi.

## Fiziksel LG kontrolü

LG H870 / Android 9 üzerinde sistem dili `tr-TR` bırakıldı. Eski APK'da uygulama
`en-US` seçiliyken native servis bildirimi Türkçeydi. Son APK aynı koşulda
`MiuCam local server is active` başlığını ve İngilizce gövdeyi gösterdi.
`ar-QA` seçimiyle aynı gerçek native bildirim Arapça oldu; ardından özgün
“telefon dilini kullan” tercihi ve Türkçe bildirim geri geldi. Sistem dili
hiç değiştirilmedi. Bu, foreground servis bildiriminin gerçek cihaz kanıtıdır;
405 sentetik analiz senaryosunun fiziksel bebek sesiyle çalıştırıldığı anlamına
gelmez. Paket `adb install -r` ile uygulama verisi korunarak güncellendi.

Kısa LAN koşusunda olay bağlantısı açık kaldı; sessiz ortamda uyarı olayı yoktu.
Ölçülen aralıklar host alım zamanlarıdır, fiziksel oynatma gecikmesi değildir.
Test hostunun erişimi arayüzden iptal edilip HTTP 401 ile doğrulandı. Geçici
credential dosyası silindi; telefon sunucu rolü ve özgün sistem dili tercihiyle
bırakıldı.

## Sonuç sınırları

Bu testler gerçek bir bebek sesi veri kümesinde duyarlılık/özgüllük ölçümü veya
klinik doğrulama değildir. Yerel PCM/analiz senaryoları ve gerçek telefonun
taşıma/bildirim davranışı ayrı kanıtlardır. Ninni/bas-konuş sırasında tüm
ağlama/yüksek ses analizinin durması devam eder; önceki oturumda eklenen görünür
uyarı korunur. Akustik AEC veya hoparlör kaydı eklenmedi.

Paylaşım servisinin metin üretimi test edildi; mevcut `shareAlert` stub'ı yeni
bir native paylaşım özelliğine dönüştürülmedi. iOS cihaz/derleme doğrulaması
Linux'ta yapılamadı. Önceki rapordaki imzalama, TLS/E2E, süreç kapalı bildirim,
iki cihaz/platform matrisi ve iki saatlik release soak kapıları açık kalır.
Önceki 30 dakikalık soak yeni analiz kodunun soak testi olarak sunulmaz.

Kanıtlar: `build/localization_validation/2026-09-05/`; analiz kırmızı/yeşil
logları ayrıca `build/device_validation/2026-09-05/alert-analysis-*.log`.
Kalıcı [sayısal özet](alert_pipeline_localization_2026-09-05.json), test kapsamını,
native bildirim metinlerini ve son APK/AAB SHA-256 değerlerini içerir.
