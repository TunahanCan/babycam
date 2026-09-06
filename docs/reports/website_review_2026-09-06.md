# MiuCam web sitesi incelemesi — 6 Eylül 2026

Başlangıç commit'i: `17fff50`. Çalışma yerel kaynak ve derlenmiş site üzerinde
yapıldı; canlı siteye dağıtım veya push yapılmadı. Mobil uygulama ve LG cihazı
bu çalışmada değiştirilmedi.

## Düzeltilenler

| Bulgu | Sonuç |
| --- | --- |
| Türkiye fiyatı, aboneliksiz kullanım ve beş izleyici sınırı yalnız kapalı bir SSS yanıtındaydı. | Mevcut platform bölümüne fiyat özeti eklendi. İlk ekrandan doğrudan erişiliyor; toplam iki saat, Türkiye hedefi 350 TL, tek seferlik ömür boyu hak ve beş cihaz sınırı birlikte görülüyor. |
| “Gelişmeleri takip et” CTA'sı bir takip hizmetine bağlanmıyordu. | Son CTA telefon uyumluluğu ve ücret bölümüne gidiyor. Mağaza sürümünün hazırlanmakta olduğu açıklaması korunuyor. |
| Büyük başlık masaüstünde uygulama ekranlarını aşağı itiyordu. | Yalnız hero başlığının ölçüsü ve görsel hizalaması düzeltildi. Renkler, sayfa bölümleri, gerçek uygulama ekran görüntüleri ve mevcut marka görselleri korundu. |
| İngilizce gibi doğrudan açılmış bir dil sayfasından başka dile geçince menü/title/ARIA ve bazı metadata metinleri ilk dilde kalabiliyordu. | Otomatik çeviri eşleştirmesi, başlangıç HTML'sinin gerçek dil kataloğunu kullanıyor. Türkçe varsayımı kaldırıldı. |
| Bölüm bağlantısı (`#sss` gibi) canonical, Open Graph ve JSON-LD URL'lerine ekleniyordu. | Gezinme ve SEO adresleri ayrıldı; bölüm bağlantısı gezinmede korunuyor. |
| QR yönü bazı çevirilerde belirsizdi; internet vaadi satın almayı da kapsıyor gibi okunabiliyordu. | Sekiz dilde “oda telefonundaki QR'ı ebeveyn telefonuyla tara” ve izleme/satın alma internet gereksinimleri açıklaştırıldı. |
| Gizlilik sayfasının tarihi ve cihazda saklanan deneme/ömür boyu hak bilgileri güncel değildi. | Yerel tarihler 6 Eylül 2026 yapıldı; deneme ve satın alma hakkının saklanması/silinmesi/geri yüklenmesi açıklandı. Fransızca destek kanalı anlamı düzeltildi. |

## Korunan ürün sınırları

- Android 7.0+ ve iOS 13+; iPhone 13 model şartı yok.
- Aynı erişilebilir yerel ağ; internet üzerinden ev dışından izleme vaadi yok.
- iOS oda kamerası ön planda; zorla kapatılmış uygulamada bildirim garantisi yok.
- Mevcut HTTP/WS güvenlik sınırı ve tıbbi cihaz olmadığı açıklaması korunuyor.
- Türkiye 350 TL hedefi yabancı ülkelerin mağaza fiyatı gibi sunulmuyor.
- Yeni yapay görsel, uydurma mağaza bağlantısı veya çalışmayan kayıt formu yok.

## Doğrulama

Sekiz katalog aynı 244 anahtarı içeriyor; JSON, yinelenen anahtar, boş değer ve
placeholder kontrolleri geçti. Kaynak iki sayfa ve oluşturulan 16 sayfa statik
doğrulamadan geçti. JavaScript sözdizimi ve `git diff --check` temiz.

Masaüstü 1440 px ve mobil 390 px ilk ekran/fiyat bölümü görsel olarak incelendi.
Tüm mevcut görsel dosyaları değişmeden kaldı.

Son tarayıcı koşusu gerçek dağıtımdaki gibi `/babycam/` yolu altında geçti:

- 16 dil/sayfa girişinden toplam **48 dil giriş/geçiş kontrolü**. Menü, title,
  ARIA, metadata, RTL, kalıcı tercih ve bölüm bağlantısı denetlendi. Dil ve SEO
  hatalarının regresyonları düzeltmeden önce başarısız, sonra başarılıydı.
- **Sekiz dilde 320 px** fiyat kartı ve metinlerde yatay taşma yok; yerel
  katalog metni doğru. Hero ve son CTA doğru fiyat bölümüne gidiyor.
- Ücret SSS'si doğrudan bölüm bağlantısında açılıyor; aynı bağlantıya tekrar
  tıklamak da kapatılmış yanıtı yeniden açıyor.
- **Yedi tarayıcı senaryosu**: Türkçe masaüstü, İngilizce tablet, Arapça mobil,
  320 px Almanca, Almanca masaüstü gizlilik, Arapça mobil gizlilik ve
  JavaScript kapalı İngilizce mobil. Kırık görsel, JS hatası ve yatay taşma yok.

Tarayıcı kontrolleri yerel Chrome ile yapıldı; Safari veya Firefox cihaz
kabul testi yapıldığı iddia edilmez. Bu doğrulama mobil uygulamanın açık
production engellerini kapatmaz.
