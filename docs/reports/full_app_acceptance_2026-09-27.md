# Uygulama, medya ve mağaza kabulü — 27 Eylül 2026

Uygulamanın iki rolündeki ekranlar ve kullanıcı eylemleri incelendi; ödeme,
eşleştirme ve yayın durdurma hataları düzeltildi. **36 yeni regresyon** ile
tam Flutter paketi **1381/1381** geçti. Bu kayıt, otomatik kabulün kanıtlarını ve
henüz yapılmamış gerçek mağaza/cihaz kabulünü ayırır.

## İncelenebilir çıktı

- [38 görüntülü ekran ve ödeme galerisi](app_acceptance_2026-09-27/index.html):
  17 ekran/durum, uzun ekranların alt bölümleri ve 13 ödeme durumu.
- [Ekran ekran eylem matrisi](screen_acceptance_2026-09-27.md): rol seçimi,
  QR/IP/keşif, bildirim geçmişi, canlı izleme, oda kontrolleri, önizleme,
  servisler, ayarlar ve güvenilen cihazlar.
- [Mağaza ödeme kabulü](store_payment_acceptance_2026-09-27.md): native
  adaptörler, pending/restore/iade ve kalıcı lisans teslimi.
- [Ödeme düğmesinden oda aktivasyonuna kabul](store_checkout_ui_acceptance_2026-09-27.md).
- [Gerçek yerel soketlerle medya ve bildirim kabulü](media_mock_acceptance_2026-09-27.md).

Galeri gerçek Flutter widget'larından host üzerinde üretildi. Görüntüdeki ikon
kontrollü test yayınıdır; fiyat ve mağaza sonuçları sentetiktir. QR ekranı gerçek
izin reddi/elle giriş görünümünü kullanır. Kamera veya Apple/Google ödeme
penceresi fotoğrafı değildir. Roboto, Material Icons ve emoji fontları host
testinin Ahem fontu yerine bağlandı; uygulamanın metinleri, bileşenleri ve
etkileşimleri değiştirilmedi. Görseller elle rötuşlanmadı. Her PNG'nin SHA-256
değeri galerinin `manifest.json` dosyasındadır.

## Düzeltilen davranışlar

1. Açık native ödeme penceresinde UI zaman aşımı artık ikinci satın almaya izin
   vermiyor. Geç gelen eski sonuç yeni işlemi kapatmıyor.
2. StoreKit'in iade edilmiş işlem geçmişi yeni satın almayı engellemiyor;
   tamamlanmamış mağaza işlemleri kaybolmuyor.
3. QR, IP ve keşfedilen oda eşleştirmesi tek bekleyen işlemi paylaşıyor. Çift
   dokunma ikinci istek açmıyor; kapatılmış ekranın geç yanıtı eşleştirme yapmıyor.
4. Yayın durdurma onayı ve kaynak kapanışı tekrar girişe kapalı. Hata anlaşılır
   biçimde gösteriliyor ve tekrar deneme korunuyor.
5. Ebeveyn ayarlarındaki uygulama bildirim geçmişi ile telefonun bildirim
   ayarları farklı başlık/açıklamalarla gerçek hedeflerini anlatıyor.

## Ödeme ve aile lisansı

Tahsilat yalnız **App Store / Google Play** üzerinden. Ek bir ödeme şirketi
entegrasyonu yok. Ebeveyn kendi mağaza hesabıyla öder; eşleştirilmiş oda
telefonuna imzalı aile lisansı aktarılır. Oda telefonunda kart veya aynı mağaza
hesabı gerekmez. Oda çevrimdışıysa teslim tekrar denenir; yeniden ücret alınmaz.
Ödeme sırasında seçilen oda değişse de ilk hedef korunur. Aynı aile lisansının
diğer eşleştirilmiş odada kullanılabilmesi de test edildi.

`backend/` kendi makbuz doğrulama ve lisans servisidir, tahsilat yapmaz. Mevcut
mimaride canlı satış için HTTPS kurulumu, mağaza API erişimleri ve ürün
yapılandırması hâlâ gereklidir. Bunların hazır olmadığı bilgisi korunmuştur.

## Doğrulama sonuçları

| Kontrol | Sonuç | Yerel kanıt |
| --- | --- | --- |
| Tam Flutter paketi | **1381 geçti** | `build/app_acceptance/flutter_test.log` |
| Backend paketi | **92 geçti** | `build/payment_acceptance_backend.log` |
| Python backend → HTTP doğrulayıcı → Dart oda lisansı → imzalı iade | **1 geçti** | `build/acceptance_backend_contract.log` |
| Gerçek ekran görüntüsü üretimi | **17 geçti**, 25 PNG | `build/app_acceptance/screen_capture.log` |
| Ödeme kartı görüntüsü üretimi | **1 geçti**, 13 PNG | `build/app_acceptance/payment_capture.log` |
| Flutter analiz | Sorun yok | `build/app_acceptance/analyze.log` |
| Dart format | Değişiklik yok | `build/app_acceptance/format.log` |
| Android release App Bundle | Başarılı, 92,3 MB | `build/app_acceptance/android_release.log` |

158 ödeme, 395 medya ve diğer odaklı test grupları tam paketin alt kümeleridir;
bu sayılar 1381'e eklenmez. Ekran matrisleri 9 locale'de dar ekran, yatay ekran
ve büyütülmüş yazıyı kapsar. Görsel galeri Türkçedir.

Release derlemesi Flutter'ın mevcut Kotlin Gradle Plugin kullanımına ilişkin
gelecek sürüm uyumluluk uyarısı verdi; derleme başarılıdır. Backend testleri
Starlette/httpx için bir deprecation uyarısı verdi. Bu çalışma bağımlılık/Gradle
göçü yapmaz.

## Tekrar çalıştırma

```sh
flutter test --no-pub
build/purchase_backend_venv/bin/python -m pytest backend/tests -q
flutter test --no-pub tool/tests/purchase_backend_contract_test.dart
flutter analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
flutter build appbundle --release
```

Backend venv yoksa `backend/requirements-test.txt` kurulmalı; kontrat testine
Python yolu `MIUCAM_BACKEND_TEST_PYTHON` ile verilebilir. Ekran üretimi için
`build/app_acceptance/fonts/` altında `Roboto-Regular.ttf`,
`MaterialIcons-Regular.otf` ve `NotoColorEmoji.ttf` gerekir. İlk ikisi Flutter
SDK'nin `bin/cache/artifacts/material_fonts/` dizininde; bu Linux ortamında
emoji fontu `/usr/share/fonts/truetype/noto/` altında bulunur.

```sh
flutter test --no-pub tool/tests/full_app_screen_capture_test.dart \
  --dart-define=MIUCAM_SCREENSHOT_FONT_DIR=build/app_acceptance/fonts
flutter test --no-pub test/features/client/client_purchase_card_test.dart \
  --plain-name='render Turkish parent purchase states' \
  --dart-define=MIUCAM_CAPTURE_PURCHASE_UI=true \
  --dart-define=MIUCAM_SCREENSHOT_FONT_DIR=build/app_acceptance/fonts
python3 tool/create_screen_acceptance_gallery.py \
  --output docs/reports/app_acceptance_2026-09-27
```

Görüntü aracı host testidir; telefon kurulumu, cihaz tercihi değişikliği veya
gerçek tahsilat yapmaz. Test yayını WAV başlığı ve doğru PCM örnek hızıyla
çalışır. Fixture kapanışında medya kaynaklarının bırakıldığı doğrulanır.

## Açık kalan gerçek kabul

Gerçek App Store Sandbox / Play test hesabı, Ask to Buy/banka reddi, gerçek
ürün fiyatı ve iade webhook'u; iOS derleme/cihaz kabulü; iki fiziksel telefonla
uzun süreli Wi-Fi, pil ve ısınma ölçümü bu çalışmada tamamlanmadı. Sentetik
analiz testleri gerçek evlerde yanlış bildirim oranı ölçümü değildir. Bu
kanıtlar kod ve mock kabulünü destekler; tek başına canlı mağaza yayınına
hazır olunduğu iddiasını desteklemez.
