# MiuCam üretim hazırlığı ve özellik kabulü — 27 Eylül 2026

**Durum: yerel doğrulamalar tamamlandı; mağazaya yayın kabulü henüz tamamlanmadı.**
Gerçek ödeme servisi, mağaza hesapları ve imzalama ayarları bu ortamda yok.
iOS çalıştırma ve iki fiziksel telefonla uzun yayın kabulü de açık. Bu rapor,
`edf2a2f` üzerindeki çalışma ağacını kapsar; herhangi bir dağıtım veya mağaza
yüklemesi yapılmadı.

Yerel ortam Linux, Flutter 3.44.2 / Dart 3.12.2 ve Python 3.14.4 kullandı.
CI Flutter 3.44.4'e sabitlenmiş durumda; uzak CI sonucu bu raporda doğrulanmış
sayılmıyor.

Önceki [kod incelemesindeki sekiz düzeltme](full_code_review_2026-09-27.md)
korundu. Bu tur üretim paketleme, backend işletimi, bütünleşik eşleştirme/medya
akışı ve gerçek Android cihazındaki doğrulamayı genişletir.

## Tamamlanan hazırlıklar

- [Üretim paket komutu](../../tool/release/build_production.py), gerçek HTTPS
  doğrulama adresini, lisans public key'ini, açık deneme sınırını, kapalı WebRTC
  pilotunu ve platform imza ayarlarını denetler. Backend preflight yanıtındaki
  ortam, mağaza, ürün ve anahtar eşleşmelidir. Eksik ayarlar ve sandbox ortamı
  üretim paketlemesini durdurur. Public key dışında gizli anahtar uygulamaya
  taşınmaz.
- Paket komutu, Flutter başarılı dönse bile yeni ve imza yapısı bulunan bir
  IPA/AAB çıktısını zorunlu tutar. Önceden kalan dosyalar başarı sayılmaz.
  iOS export ayarındaki otomatik upload seçeneği reddedilir; komut yalnız
  yerel paket üretir. Bu kontrol gerçek sertifika ve mağaza kabulünün yerine
  geçmez.
- Backend gerçek yapılandırmadaki `storeEnvironment` bilgisini preflight ve
  sağlık yanıtına ekler. Böylece sandbox servisinin üretim servisi gibi
  kullanılması üretim komutunda reddedilir.
- Gerçek Docker imajında, root olmayan kullanıcı ve salt okunur kök dosya
  sistemiyle satın alma, imza, yeniden başlatma, DB/anahtar kalıcılığı,
  SQLite yedekten dönüş, mağaza kesintisi, iade ve istek sınırları çalıştırıldı.
  Mağaza yanıtları sentetiktir; test container ve volume'ları temizlendi.
- QR ve PIN için iki yeni uçtan uca test, gerçek istemci/sunucu bileşenleriyle
  eşleştirme → token saklama/yükleme → eşleştirmeyi kapatma → MJPEG/WAV
  → yeniden bağlanma/yenileme → erişimi iptal etme zincirini doğrular.
  Bu testlerde saklama sözleşmesi bellek içi tercih/secure-store taklitleriyle
  çalışır; disk veya Keychain dayanıklılığı kanıtı değildir.
- Android kamera/mikrofon foreground türleri desteklendikleri API 30'dan
  itibaren gönderilir. Android 12+ bulut yedeği ve cihaz aktarımı için dokuz
  uygulama depolama alanını dışlayan açık kurallar eklendi. Yapılandırma testi
  her iki modu ve tüm alanları denetler.
- Android App Bundle dil bölme kapatıldı: uygulama içinden dil değiştirildiğinde
  native bildirim çevirileri de çevrimdışı kullanılabilir. Dil paketlerinin
  yalnız Play kurulumundaki sistem diline göre dağıtılması engellenir.
- Cihaz benchmark komutu artık cihaz kimliği ve çalışan uygulamanın VM adresini
  zorunlu tutar; mevcut uygulamaya bağlanır. Kurulum hatasında uygulamayı
  kaldıran varsayılan driver yolu kullanılmaz.
- CI'ye üretim kapısı testleri, Docker çalışma zamanı kabulü ve iOS XCTest
  çalıştırması eklendi. **macOS CI burada çalıştırılmadı**; workflow eklenmesi
  başarılı iOS sonucu sayılmaz.

Altı haneli kod yalnız ilk eşleştirmeyi doğrular. Kullanıcının istediği gibi
medya şifrelemesi veya TLS eklenmedi; yayın mevcut yerel HTTP/WS yolunu kullanır.

## Otomatik doğrulama

| Kontrol | Sonuç ve kapsam |
| --- | --- |
| Flutter testleri | **1.418 geçti**, backend → Dart lisans sözleşmesi dahil |
| Backend Python | **99 geçti**; tek test istemcisi kullanım dışı bırakma uyarısı |
| Üretim paket kapısı | **22 geçti**; sandbox/eksik ayar, yanlış anahtar, eski/eksik/imzasız paket ve otomatik upload reddi dahil |
| Android Kotlin/JVM | **17 geçti**, hata veya atlanan test yok |
| Android release lint | **0 hata, 18 uyarı**; API türü, yedekleme ve dil bölme uyarıları düzeltildi |
| Ekran kabulü | **17 geçti**; host üzerinde 17 uygulama ekranı/görünümü |
| Flutter analiz ve biçim | Sorun yok; 415 Dart dosyasında biçim değişikliği gerekmiyor |
| Backend container | Gerçek imajın tüm smoke adımları geçti; yapılandırılmamış giriş noktası erişimi kapalı tutuyor |
| Web sitesi | 8 dil, 266 metin anahtarı, 16 üretilmiş sayfa; Chrome responsive/RTL/dil rotaları/JavaScript kapalı kontrolleri geçti |
| Üretim yapılandırması eksikliği | Gerçek yapılandırma dosyası olmadan üretim komutu beklendiği gibi başarısız |
| Android release AAB | Son kaynaklardan **92.428.425 bayt** paket üretildi; yeni yedekleme kaynağı pakette. İmzasız derleme doğrulamasıdır |

Kalan lint uyarıları bağımlılıkların yeni sürümleri, gereksiz eski SDK koşulları,
ikon/kullanılmayan kaynaklar ve uygulama ömründeki ses oynatıcı referansıyla
ilgilidir. Sonuncusunda tutulan context `applicationContext` olarak doğrulandı;
Activity context tutulmuyor. Bağımlılık sürümleri bu tur yükseltilmedi.

Coverage alınan 1.416 testlik çalıştırmada 194 dosyadaki 21.561 yürütülebilir
Dart satırının 18.484'ü çalıştı: **%85,73**. Sonraki Android XML ve dil bölme
yapılandırma testleriyle toplam 1.418 oldu; bu ek testler üretim Dart kodunu
değiştirmiyor.
Satır coverage değeri fiziksel cihaz veya tüm kullanım koşullarının kapsamı
olarak yorumlanmamalıdır.

## Özellik matrisi

Test adları `test/` altındaki temsilî dosyalardır. “Geçti”, bu tablodaki
otomatik senaryoları ifade eder; sağ sütun gerçek ortamda kalan kabulü gösterir.

| Özellik | Geçen doğrulama | Kalan gerçek ortam kabulü |
| --- | --- | --- |
| QR, PIN ve manuel IP ile eşleştirme | `pairing_code_http`, `client_screen_acceptance`, `media_stream_end_to_end`; süre, hatalı kod, deneme sınırı, QR bağımsızlığı | İki telefon arasında QR tarama ve PIN akışı |
| Ağ keşfi, adres değişimi ve IPv4/IPv6 | `miucam_service_discovery`, `trusted_session_endpoint_resolver` | Gerçek router, DHCP ve istemci izolasyonu |
| Güvenilir cihazlar ve oda limitleri | `trusted_client_limit`, `active_client_limit`, `pairing_session_store` | Beş fiziksel ebeveyn cihazı |
| Cihaz adı, token yenileme ve iptal | `trusted_devices_scenario`, `pairing_revocation_race`, bütünleşik medya testleri | Bağlı telefonun canlı olarak iptal edilmesi |
| Görüntü, ses, susturma ve yeniden bağlantı | `media_stream_end_to_end`, `media_lan_acceptance`, `watch_screen_production_behavior`; LG gerçek kamera/mikrofon ve ses çıkışı | İki telefon gecikmesi, uzun yayın ve akustik kalite |
| Konuşma, rahatlatıcı ses, gece ışığı ve fener | `feature_control_endpoints`, `client_room_controls`, `night_light_controller`, `android_service_media_torch_bridge` | Gerçek hoparlör/mikrofon, Bluetooth ve farklı kamera donanımı |
| Hareket/ağlama analizi ve tekrar uyarı sınırı | `analysis_false_alert_scenario`, `server_alert_delivery_scenario`, `analysis/` | Gerçek odada yanlış alarm ve kaçırılan olay ölçümü |
| Bildirim, geçmiş, tercihler ve uygulamaya dönüş | `client_notification_screen`, `client_alert_delivery_coordinator`, `notification_service`; LG'de gerçek bildirim görüldü | Kilit ekranı, üretici güç yönetimi ve iOS bildirim davranışı |
| Zayıf ağ ve kaynak kullanımı | `adaptive_media_weak_wifi`, `active_client_load_quality`, `backpressure_memory` | Uzun zayıf Wi-Fi, pil ve termal ölçüm |
| Ayarlar ve kalıcı saklama | Sunucu/istemci ayar senaryoları, repository ve secure storage testleri | Farklı cihazlarda işletim sistemi güncellemesi/yeniden kurulum davranışı |
| Deneme, satın alma, geri yükleme ve iade | `store_checkout_ui_acceptance`, `purchase_delivery_lifecycle`, `license_grant`; Python → Dart HTTP ve Docker yaşam döngüsü | Gerçek Play/App Store sandbox işlemleri ve mağaza bildirimi |
| Rol değişimi ve kaynak temizliği | `role_isolation`, `role_switch_transaction`, `server_role_shutdown`; LG'de iki canlı döngü | iOS ve yeni Android sürümlerinde yaşam döngüsü |
| 8 dil/9 locale, RTL ve erişilebilirlik | Metin katalogları, ekran matrisi, erişilebilirlik ve native dil testleri | Gerçek ekran okuyucu kabulü |
| WebRTC pilotu | Sinyal/bağlayıcı testleri; üretim komutu pilotun kapalı olmasını zorunlu tutuyor | Bu sürümde etkin üretim özelliği sayılmıyor |

## Gerçek LG H870 doğrulaması

Android 9 / API 28 cihazında uygulama verisi yedeklendi; test paketleri yalnız
`adb install -r -t` ile güncellendi. Driver çalışan uygulamaya bağlandı.
Uygulama kaldırılmadı ve veri temizlenmedi. Rol testi tercih/token saklamasını
bellekte izole etti; kamera görüntüsü veya ses kaydı dışarı aktarılmadı.

- **Kamera/mikrofon:** iki Client → Server → Client döngüsü geçti. Her döngüde
  gerçek kameradan en az bir kare, mikrofondan 15 ve 14 parça alındı. Geçişler
  3.236 ms ve 2.288 ms sürdü; sonunda tüm native rol kaynakları kapalıydı.
- **Ses:** kontrollü localhost PCM akışı gerçek AudioTrack üzerinden üç kez
  oynatıldı. Yaklaşık üçer saniyelik gözlemlerde oynatma başı 50.880, 49.600 ve
  49.280 örnek ilerledi; kararlı oynatma sırasında underrun artışı **0** oldu.
  Başlangıçta bir underrun sayıldı. İkinci durdurmada artık geçerli olmayan
  bir yazma reddedildi; native yazma hatası oluşmadı ve tüm oynatıcılar kapandı.
  Bu test dış LAN veya akustik kalite ölçümü değildir.
- **Bildirim:** gerçek Android bildirimi gönderildi, aktif bildirim sorgusuyla
  doğrulandı ve test bildirimi temizlendi.
- **Arayüz:** profile modunda slider için 103 karede toplam p95 **34,351 ms**,
  kaydırmada 179 karede **24,870 ms** ölçüldü. İkisi de tanımlı 35 ms hedefinin
  altında; bu sonuç tüm karelerde 60 FPS iddiası değildir.
- **Veri koruma:** son kaynaklardan normal debug uygulaması geri kuruldu.
  Önceden bulunan dokuz dosya
  karşılaştırıldı; yalnız Android'in ürettiği `files/profileInstalled` işareti
  değişti. Mevcut uygulama tercihleri ve eşleştirme tokenları değişmedi.

Özet ölçümler [JSON kanıt kaydında](production_readiness_2026-09-27_evidence.json)
bulunur. Ham yerel cihaz sonuçları `build/production_acceptance/` altındadır.
Son API 30 servis koşulu ve API 31 yedekleme XML değişiklikleri derleme/statik
kontrollerle doğrulandı; bu sürümler fiziksel cihazda çalıştırılmadı.

## Yayından önce tamamlanacaklar

1. Gerçek HTTPS satın alma backend'i, lisans public key'i, mağaza ürünleri ve
   kimlik bilgileri; kalıcı DB/anahtar yedeği ile yayın ayarları sağlanmalı.
2. Android upload key ve Apple Team/dağıtım sertifikalarıyla gerçek imzalı
   paket oluşturulmalı. Buradaki imzasız derleme mağaza paketi değildir.
3. Gerçek mağaza sandbox hesabında satın alma, bekleyen işlem, restore,
   ikinci aile cihazı, iade ve bildirim kabulü yapılmalı.
4. macOS üzerinde iOS derlemesi/XCTest çalışmalı; gerçek iPhone ve yeni Android
   sürümlerinde izin, ses kesintisi, Bluetooth ve arka plan kabulü tamamlanmalı.
5. En az iki fiziksel telefonla 30 dakika yayın; Wi-Fi değişimi/zayıf sinyal,
   ekran kilidi, pil/ısı ve bağlı cihazı iptal etme doğrulanmalı.
6. Mevcut [yayın kontrol listesindeki](../RELEASE_CHECKLIST.md) gizlilik,
   destek adresleri ve mağaza metadata hazırlığı tamamlanmalı.

## Tekrar çalıştırma

Flutter ve Python yolları yerel ortama uyarlanabilir. Release derlemesiyle
debug JVM kontrolünü ayrı çalıştırın: iki varyant aynı anda oluşturulursa
Flutter'ın ürettiği eklenti kayıt dosyası çakışabilir. Cihaz testi sonrasında
normal release derlemesinde `--no-pub` kullanmayın.

```sh
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
MIUCAM_BACKEND_TEST_PYTHON="$PWD/build/purchase_backend_venv/bin/python" \
  flutter test --no-pub test tool/tests/purchase_backend_contract_test.dart
build/purchase_backend_venv/bin/python -m pytest -q backend/tests
python3 -m unittest discover -s tool/tests/release -v
python3 backend/tests/docker_smoke.py
flutter build appbundle --release
(cd android && ./gradlew :app:lintRelease --console=plain)
(cd android && ./gradlew :app:testDebugUnitTest --console=plain)
```

Fiziksel cihaz adımları için [veriyi koruyan cihaz kabul akışını](../RELEASE_CHECKLIST.md#cihaz-kabul-testi)
izleyin. Üretim paketinin gerçek ayar kontrolü için:

```sh
python3 tool/release/build_production.py --platform android \
  --defines-file tool/release/production.json --check-only
```
