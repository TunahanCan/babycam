# Ekran ve kullanıcı akışı kabulü

27 Eylül 2026. Gerçek Flutter ekranları; sahte LAN yanıtları, mağaza/platform
sınırları ve bellek içi tercihlerle çalıştırıldı. Kontroller yalnız metin aramaz:
düğmelere basar, giriş yapar, sekme/rota değiştirir ve oluşan servis çağrıları,
kalıcı tercihler ile medya sahipliğini doğrular. Bu çalışma fiziksel telefona
uygulama kurmaz, cihaz verisini silmez ve gerçek tahsilat yapmaz.

## Ekran ekran kapsam

| Ekran / görünüm | Gerçekleştirilen işlem ve doğrulanan sonuç | Test kaynağı |
|---|---|---|
| Mod seçimi | Ebeveyn/oda seçenekleri; dar ekranda kaydırma; seçilen rol callback'i; 9 locale × 2 boyut | `role_selection_screen_test.dart`, `server_screen_matrix_test.dart` |
| Ebeveyn ana ekranı, oda yok | “Odayı bul ve bağlan” üzerinden Bul sekmesine geçiş | `client_screen_acceptance_test.dart`: `manual connection validates, retries, arms alerts and opens watch` |
| Bul · elle IP | Geçersiz adres ağ isteği başlatmaz; erişilemeyen oda anlaşılır hata verir; yeniden deneme eşleştirir ve bildirim dinlemesini açar | Aynı kabul testi |
| Bul · yavaş bağlantı | Çift dokunma tek LAN isteği üretir; beklerken QR, IP ve keşfedilen oda üzerinden yeni eşleşme açılmaz | `pairing request cannot be submitted twice while LAN reply is pending` |
| Bul · geç yanıt / hata | Ekran kapatıldıktan sonra gelen LAN yanıtı eşleştirme yapmaz; beklenmeyen hata teknik ayrıntı göstermez ve tekrar denenebilir | `closing the pairing screen ignores a late LAN reply`, `unexpected pairing failures remain actionable without technical details` |
| Bul · keşfedilen odalar | Yenile taramayı tetikler; gelen oda listelenir; Bağlan seçilen IP ve portu kullanır | `discovered room refresh and selection use the advertised endpoint` |
| QR tarayıcı | İzin reddi, kalıcı ret ve kamerasız cihaz; Ayarları aç; boş/geçersiz metin; geçerli QR metniyle çağıran rotaya geri dönme; yatay büyük yazıda klavye altında erişilebilir giriş | `qr_scan_screen_test.dart` |
| Ebeveyn · eşleşmiş oda | Canlı izle açılır; geri dönüldüğünde bildirim dinleme kalır; trial kilidi her locale'de açıklanır; eski oda bildirimi yeni odayı açamaz | `client_screen_acceptance_test.dart`, `client_alert_access_screen_test.dart`, `client_notification_screen_test.dart` |
| Bildirim geçmişi | Ses/hareket/sistem filtreleri gerçek kayıtları ayırır; uygun bildirime dokunma canlı izlemeyi açar; OS bildirim dokunuşu açık rotadan geçmişe getirir | `client_notification_screen_test.dart` |
| Ebeveyn ayarları | Ekranı açık tut tercihi ve dil kaydedilir, ekran yeniden açılınca korunur; dil seçimini kapatmak değişiklik yapmaz; disk hatası eski değeri korur | `client_screen_acceptance_test.dart`, `client_preferences_screen_test.dart` |
| Ebeveyn ayarları · iki bildirim eylemi | Uyarı geçmişi uygulamadaki geçmiş sekmesini açar; telefon bildirim ayarları yalnız mock OS `openAppSettings` çağrısını yapar | `notification history and phone notification settings have distinct actions` |
| Canlı izleme / hata | Bağlantı hatası teknik metin sızdırmaz; Tekrar bağlan tek işlem yürütür; mute/unmute ve geç bağlantı sonuçları tutarlıdır; ekran kapanışı medya sahipliğini bırakır | `client_notification_screen_test.dart`, `watch_screen_production_behavior_test.dart` |
| Canlı izleme · tam ekran / gece saati | Gir/çık; sistem geri; RTL; 48dp erişilebilir eylemler; algılama duraklatıldı uyarısı görünür kalır; arka plana geçişte stream ve wakelock durur | `watch_screen_production_behavior_test.dart`, `watch_and_navigation_accessibility_test.dart` |
| Canlı izleme · geçmiş / ayarlar | Alt sekmeler dolaşılır; son uyarıdan geçmişe gidilir; filtreler çalışır; tercih kayıt hatası anahtarı yanlış konumda bırakmaz | `client_screen_matrix_test.dart`, `client_notification_screen_test.dart`, `watch_screen_production_behavior_test.dart` |
| Oda kontrolleri | Ses/parça seçimi, ses seviyesi, talkback izinleri; bekleyen komutlar çakışmaz; hatada onaylanmış değer geri gelir; polling kullanıcı taslağını ezmez | `room_controls_panel_production_test.dart`, `room_controls_panel_accessibility_test.dart`, `watch_screen_production_behavior_test.dart` |
| Oda yayın ekranı | Yerel önizlemeyi aç/kapat; açık ebeveyn yayını yerel önizleme kapatılınca devam eder; bağlantı ana eylemi QR/IP ekranını açar | `hard_split_navigation_test.dart`, `server_screen_matrix_test.dart` |
| Oda önizleme · tam ekran | Tam ekran açılır, sığdırma değiştirilir, sistem geri ile dönülür; önizleme sahipliği korunur; QR/IP sekmesine gidince kamera bırakılır | `server_screen_acceptance_test.dart`: `room preview fullscreen fit and back keep ownership until leaving preview` |
| Oda yayını durdurma | İptal yayını korur; onay host/kamera/mikrofonu kapatır; kapanış beklerken ikinci onay açılamaz; hatada sakin mesaj ve yeniden deneme kalır | `server_screen_acceptance_test.dart`: diğer 3 senaryo |
| Oda · QR/IP | Gerçek QR bileti; yenile yeni nonce üretir; adresi kopyala panoya yazar; tüketilen QR yenilenir; üretim hatası sahte QR göstermez; arka planda QR timer'ı durur | `hard_split_navigation_test.dart`, `trusted_devices_scenario_test.dart`, `server_presentation_lifecycle_test.dart` |
| Oda · servis durumu | Servisler sekmesi erişilir ve sonuna kadar kaydırılır; native durum polling'i arka planda/dismiss sonrası durur; eski native yanıt yeni durumu ezmez | `server_screen_matrix_test.dart`, `server_presentation_lifecycle_test.dart` |
| Oda ayarları | Hassas/Dengeli/Daha az uyarı seçimleri ses-hareket eşikleri, süreler ve bildirim beklemesini birlikte kaydeder; kayıt hatası kalıcı değerlere döner | `server_settings_scenario_test.dart` |
| Güvenilen ebeveyn cihazları | Ekleme canlı görünür; yeniden adlandır; tekli kaldırma onayı; aynı isimli telefonların kimlik ayrımı; kayıt hatasından sonra retry; 5 cihaz kapasitesi | `trusted_devices_scenario_test.dart`, `server_settings_scenario_test.dart` |
| Ödeme / lisans | Hazır, pending, doğrulama, aktivasyon, çevrimdışı oda, etkin, iade/iptal, restore ve mağaza erişilemez durumları | Ayrıntılı ve ayrı kanıt: [Mağaza ödeme kabulü](store_payment_acceptance_2026-09-27.md) |

Test kaynakları `test/features/client/`, `test/features/server/`,
`test/features/role_selection/` altındadır; ortak navigasyon dosyası
[`hard_split_navigation_test.dart`](../../test/features/hard_split_navigation_test.dart).
Yeni etkileşim senaryoları
[`client_screen_acceptance_test.dart`](../../test/features/client/client_screen_acceptance_test.dart),
[`server_screen_acceptance_test.dart`](../../test/features/server/server_screen_acceptance_test.dart)
ve [`qr_scan_screen_test.dart`](../../test/features/client/qr_scan_screen_test.dart)
içindedir.

## Bulunan ve giderilen kullanıcı sorunları

1. IP/discovery yanıtı beklenirken ikinci dokunuş yeni istek açıyordu. QR, IP ve
   keşfedilen oda artık ortak tek eşleştirme işlemini kullanıyor; bekleme durumu
   görünür, girişler kilitli ve kapatılmış ekrana gelen yanıt yok sayılıyor.
2. Beklenmeyen eşleştirme hatası ham `StateError` metnini gösteriyordu. Bilinen
   hata kodlarının açıklamaları korundu; beklenmeyen hata mevcut, yerelleştirilmiş
   bağlantı açıklamasını kullanıyor.
3. Yayın durdurulurken tekrar onay açılabiliyordu. Diyalog/kapanış boyunca eylem
   kilitleniyor. Kapanış hatası yakalanıyor; UI retry eylemini koruyor.
4. Ebeveyn ayarlarında geçmiş ve telefon bildirim ayarı aynı başlık/açıklamayla
   sunuluyordu. İki eylem artık gerçek hedefini anlatıyor. Yeni metinler Türkçe,
   İngilizce, Çince, Hintçe, İspanyolca, Fransızca, Almanca ve Arapçada mevcut.

## Doğrulama ve sınırlar

- Geniş UI geçişi: 18 test dosyasında **134 test geçti**
  (`build/screen_acceptance_final.log`). Son bildirim metni/eylem değişikliği
  ardından etkilenen **38 test** yeniden geçti
  (`build/screen_acceptance_changed.log`); ek oda tam ekran yolculuğu dahil
  **4 server kabul testi** geçti (`build/screen_acceptance_server.log`).
  Bu gruplar örtüşür; sayılar toplanarak toplam test sayısı üretilmemelidir.
- Matris: desteklenen 9 locale; 320×568 boyutta 2× yazı ve 640×360 yatayda
  1,3× yazı. İlgili sekmeler sonuna kadar kaydırılır ve Flutter layout hatası
  olmadığı doğrulanır. Yeni etkileşim testlerinde boşa giden dokunuşlar fataldır.
- Önizleme widget testinde sahte native kaynak, canlı izleme gezinme testinde
  sahte stream başlangıcı kullanılır. Bunlar gerçek kamera görüntü kalitesi veya
  hoparlör gecikmesi ölçümü değildir. Gerçek LAN socket/parser/audio davranışı
  [medya mock kabulünde](media_mock_acceptance_2026-09-27.md) ayrı doğrulanır.
- OS ayar sayfası ve Apple/Google satın alma penceresi uygulamanın kendi Flutter
  ekranı değildir. Bu çalışmada giriş/çıkış sözleşmeleri mock sınır üzerinden
  doğrulanır; gerçek mağaza hesabı, tahsilat veya iOS cihaz kabulü yapılmış sayılmaz.

Tüm yeni UI senaryolarını yeniden çalıştırmak için:

```sh
flutter test test/features/client/client_screen_acceptance_test.dart \
  test/features/server/server_screen_acceptance_test.dart \
  test/features/client/qr_scan_screen_test.dart
```
