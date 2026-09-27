# Mağaza ödeme kartı: gerçek uygulama zinciri kabul testi

27 Eylül 2026 tarihinde `store_checkout_ui_acceptance_test.dart` içindeki **4 test geçti**. Kartın düğmesine basılması gerçek `ClientRuntime`, `BroadcastPurchaseCoordinator` ve `BroadcastAccessService` üzerinden ilerler. Arayüz için satın alma durumları elle atanmaz. İmzalı test lisansı üretim `LicenseGrantVerifier` ile doğrulanır; uygulamanın kalıcı lisans/hedef oda kayıtları bellek içi SharedPreferences üzerinde kontrol edilir.

Yalnız mağaza dönüşleri ve karşı odanın ağ sınırı kontrollü test nesneleridir. Bu paket Apple/Google ödeme penceresini açmaz ve gerçek ücret çekmez; native mağaza adaptörünün ayrı testleriyle birlikte değerlendirilmelidir.

| Düğmeden başlayan yol | Doğrulanan sonuç |
| --- | --- |
| Satın al → mağaza onayı bekleniyor → geç onay → oda çevrimdışı → odada etkinleştir | Beklerken ikinci satın alma düğmesi yok. Lisans saklanıyor; oda bağlantısı düzelince tek satın alma ile etkinleşiyor. Ebeveyn telefonda ikinci deneme süresi başlamıyor. |
| Geri yükle → satın alma bulunamadı → sahip olunan satın almayı geri yükle | Boş sonuç anlaşılır mesaj veriyor, oda açılmıyor. Sonraki başarılı geri yükleme odayı etkinleştiriyor; satın alma çağrısı hiç yapılmıyor. |
| A odası için ödeme sürerken B odasına geç → A ödemesi tamamlanıyor | A hedefi korunuyor. B kartı açılmış gibi görünmüyor; B için izlemeyi başlatabilecek `onActivated` çağrısı yapılmıyor. Ebeveyn B’de ayrıca etkinleştirdiğinde aynı aile lisansı kullanılıyor, yeni ödeme açılmıyor. |
| Satın al → iptal → yeniden dene | İptal mesajı ve kullanılabilir düğme gösteriliyor; bekleyen hedef temizleniyor. İkinci kullanıcı denemesi başarılı olabiliyor. |

Yeni kabul paketi, mevcut 9 locale / iki görünüm ödeme kartı testleri ve oda yaşam döngüsü testleri birlikte **29/29 geçti**. Yeni dosyanın Dart analizi temiz. Bu çalışma ürün kodu değişikliği gerektiren bir hata ortaya çıkarmadı.

```sh
flutter test --no-pub --reporter expanded \
  test/features/client/store_checkout_ui_acceptance_test.dart \
  test/features/client/client_purchase_card_test.dart \
  test/features/client/client_purchase_room_lifecycle_test.dart \
  test/features/client/client_broadcast_access_room_test.dart
```

Yerel çıktı: `build/store_checkout_ui_focused.log`. App Store Sandbox / StoreKit ve Google Play lisanslı test hesabında native mağaza penceresi, gerçek ürün yapılandırması ve sunucu doğrulama erişimi bu host testleriyle doğrulanmış sayılmaz.
