# Satın alma ve cihazlar arası lisans incelemesi

> Bu belge düzeltmelerden önceki inceleme kaydıdır. Sonraki uygulama, regresyon
> testleri ve kalan dış kurulum adımları
> [satın alma uygulama raporunda](purchase_implementation_2026-09-27.md) izlenir.
> Aşağıdaki “mevcut durum” sütunu inceleme anını anlatır.

Tarih: 27 Eylül 2026. İncelenen ürün kodu: `d8c4905`.

## Sonuç

Ebeveynin kendi telefonunda ödeme yapıp eşleşmiş oda telefonunda lisansı kullanması şu an desteklenmiyor. Satın alma yalnız oda/server rolünde açılıyor ve hak o telefonun yerel kaydına yazılıyor. Ebeveyn telefonunu geçici olarak server rolüne çevirmek de diğer telefona lisans sağlamaz.

Bu senaryo ürünün normal satın alma yolu olmalı: **ödemeyi yapabilen telefon ile yayını yapan telefon farklı olabilir.** Oda telefonunda kart, ödeme yapabilen mağaza hesabı veya satın alma sırasında internet bulunması şart olmamalı. İlk ödeme ve mağaza doğrulaması için ebeveyn telefonunun internete erişmesi gerekir; doğrulanmış hak odaya yerel ağdan aktarılabilir.

Önerim tek satın almayı aynı ailenin birden fazla eşleşmiş oda telefonunda kullanabilmesidir. Lisans kapsamı için kullanıcıya iki seçenek sunuldu; rapor hazırlanırken yanıt gelmedi. Bu nedenle çoklu oda kapsamı bir tasarım önerisidir, onaylanmış veya uygulanmış ürün kuralı değildir. Mevcut dört oda profili ve beş eşzamanlı izleyici sınırı, lisansın kaç oda içerdiğini tanımlamaz.

Bu tur ürün koduna dokunulmadı. Kod, mağaza entegrasyonu, mevcut testler ve yeni hata senaryoları incelendi. Mimari belgedeki eski fiyat, varsayılan paywall bayrağı ve doğrulama açıklamaları mevcut kodla eşitlendi. Gerçek tahsilat, sandbox mağaza işlemi veya iki fiziksel telefonla satın alma yapılmadı.

## Öncelikli bulgular

| Öncelik | Bulgu ve etkisi | Kanıt / gereken değişiklik |
| --- | --- | --- |
| P1 | **Ebeveynden ödeme → odaya aktivasyon yolu yok.** Kart tanımlanmayan eski oda telefonu ödeme engeline takılıyor. | [Client composition](../../lib/features/client/client_composition_root.dart#L90), [yalnız GET /status yapan istemci](../../lib/features/client/media/remote_broadcast_access_client.dart#L20), [server composition](../../lib/features/server/server_composition_root.dart#L41). Her iki rolden kullanılabilen satın alma koordinatörü ve odaya doğrulanmış hak teslimi gerekiyor. |
| P1 | **Doğrulama sürerken rol/uygulama akışı kapanırsa mağaza işlemi tamamlanıp yerel lisans kaydı oluşmayabiliyor.** Kullanıcı ödeme yapmış olmasına rağmen erişimi alamayabilir; manuel restore gerekebilir. | [Mağazayı tamamlama](../../lib/services/monetization/broadcast_access_service.dart#L599), [kapatılan yayım](../../lib/services/monetization/broadcast_access_service.dart#L621), [rol değişimi](../../lib/app/role_switch_transaction.dart#L17). Repro: `acknowledged=1`, `persistedUnlock=null`. Kalıcı hak/teslimat kaydı, mağaza tamamlamasından önce güvenceye alınmalı. |
| P1 | **Takılan native completePurchase kapanışı bloke ediyor.** Rol değişimi de runtime kapanışını bekliyor. | [Doğrudan await](../../lib/services/monetization/broadcast_access_service.dart#L600), [kuyruk drain](../../lib/services/monetization/broadcast_access_service.dart#L644). Repro, sahte native çağrı serbest bırakılana kadar kapanamadı. Süre sınırı, geç sonucun sahipliği ve kalıcı yeniden deneme birlikte çözülmeli. |
| P1 | **Bozuk deneme kaydı, geçerli satın almayı geri yüklemeyi de engelliyor.** | [restore öncesi initialization](../../lib/services/monetization/broadcast_access_service.dart#L820). Repro'da bozuk `trial_ledger_v1`, mağazaya hiç gidilmeden `FormatException` üretti; `restoreCalls=0`. Deneme muhasebesi arızası ücretli hak kurtarmasını kapatmamalı. |
| P2 | **Oda A'nın lisans durumu oda B'ye taşınıyor.** B adı altında A'nın süre bitti mesajı veya lifetime durumu gösterilebiliyor. | [Pair](../../lib/features/client/client_runtime.dart#L350), [restoreSession](../../lib/features/client/client_runtime.dart#L273). Gerçek runtime ve ana ekranla iki repro. Sunucu B'nin erişim kontrolü çalışıyor; erişim aşımı gözlenmedi. Snapshot oda kimliğine bağlanmalı ve oda değişince temizlenmeli. |
| P2 | **Açık restore işlemi eski başarı önbelleğini kullanıyor.** Doğrulayıcı artık reddedecek olsa bile aynı kanıt tekrar doğrulanmıyor. | [Evidence cache](../../lib/services/monetization/broadcast_access_service.dart#L569). Repro: `verifierCalls=1`, restore sonucu hâlâ `unlocks=true`. Restore'da güncel doğrulama yapılmalı; aynı işlemin iki kez teslim edilmemesi ayrı bir kayıtla sağlanmalı. |
| P2 | **Bekleyen ödeme, UI zaman aşımından sonra ikinci checkout girişimine izin veriyor.** | [Active completer temizliği](../../lib/services/monetization/broadcast_access_service.dart#L511). Repro: onay hâlâ pending iken `buyCalls=2`. Bu çift tahsilat kanıtı değildir; tekrar mağaza sayfası açma ve yanlış yönlendirme kanıtıdır. UI bekleme süresi ile mağazadaki işlem durumu ayrılmalı. |
| P2 | **Kapanışta tamamlanan ödeme için açılış/ön plana dönüş mutabakatı eksik.** Dinleyici yalnız server runtime ömründe var. | [Gateway stream aboneliği](../../lib/services/monetization/broadcast_access_service.dart#L313); production client'ta gateway yok. Android'de mevcut alımların sorgulanması, iOS'ta güncel hakların okunması gerekir; yalnız canlı event akışı yeterli değildir. Kod incelemesi ve kurulu platform paketleriyle doğrulandı, gerçek mağaza testi yapılmadı. |
| P2 | **İade/geri alınmış hak için ayrı durum ve eşitleme yok.** Kayıtlı hak süresiz geçerli sayılıyor; geçici doğrulama bağlantı hatası ile gerçek hak reddi aynı sonuç ailesinde. | [Yerel kalıcı hak kontrolü](../../lib/services/monetization/broadcast_access_service.dart#L1008), [verifier sonucu](../../lib/services/monetization/purchase_verification.dart#L34). Ağ arızasında geçerli kullanıcı kilitlenmemeli; mağazanın kesin iptal ettiği hak da yeni aktivasyon üretmemeli. |
| P2 | **Ebeveyndeki refreshBroadcastAccess uzak odayı yenilemiyor.** Production'da yerel servis null olduğu için işlem yapmadan dönüyor. | [Refresh](../../lib/features/client/client_runtime.dart#L224). Aktivasyon sonrası uzak durumu okuyup cevabın hâlâ aynı odaya ait olduğunu kontrol etmeli. |
| Koşullu | **Canceled/error işlemlerinde pendingCompletePurchase dikkate alınmıyor.** | [Terminal durumlar](../../lib/services/monetization/broadcast_access_service.dart#L551). İki sahte-store repro başarısız. Kurulu StoreKit1, bu durumlarda bayrağı true yapıyor; varsayılan StoreKit2 için aynı koşul geçerli değil. Eski StoreKit yolu kullanılacaksa kapsanmalı. |

Depoda bir satın alma doğrulama backend'i değil, onun HTTP istemcisi bulunuyor. `MIUCAM_PURCHASE_VERIFIER_URL` eksik veya geçersiz olduğunda checkout açılmaması doğru. Mağaza ürünleri ve backend yapılandırması, bu kod incelemesiyle çalışır kabul edilemez.

## Önerilen satın alma akışı

```mermaid
sequenceDiagram
    participant P as Ebeveyn telefonu
    participant S as Google Play / App Store
    participant B as Lisans doğrulama servisi
    participant R as Eşleşmiş oda telefonu
    P->>R: Oda kimliği, mevcut hak ve aktivasyon desteği
    R-->>P: Seçili oda durumu
    P->>S: Tek seferlik satın alma veya geri yükleme
    S-->>P: İşlem sonucu / kanıtı
    P->>B: Mağaza kanıtı ve lisans bağlamı
    B-->>P: Doğrulanmış kalıcı hak ve oda aktivasyon belgesi
    P->>P: Hakkı ve bekleyen teslimatı kalıcı kaydet
    P->>S: İşlemi tamamla; gerekirse kalıcı yeniden deneme
    P->>R: Eşleşmiş bağlantı üzerinden aktivasyon
    R->>R: Belgeyi doğrula ve kalıcı kaydet
    R-->>P: Bu oda için lisans etkin
```

Bu diyagram hedef tasarımdır. Mağaza tamamlama, kalıcı teslimat kaydı güvenceye alındıktan sonra yapılır; oda telefonunun yeniden çevrimiçi olmasını beklemeye bağlanmaz. Mağazadan ücret alınması, hakkın doğrulanması ve oda aktivasyonu ayrı durumlar olarak tutulur.

- **Satın alma sahipliği uygulama düzeyinde yaşar.** Ekran veya server/client rolünün kapanması mağaza dinleyicisini ve işlem günlüğünü yok etmez. `PurchaseCoordinator`, satın alma/restore ve sonuç teslimini yönetir.
- **Oda erişim kontrolü odada kalır.** Parent'a mevcut `BroadcastAccessService` doğrudan verilmemeli: [client.watch](../../lib/features/client/client_runtime.dart#L475) ikinci yerel deneme sayacı başlatır; [yerel sonucun önceliği](../../lib/features/client/client_runtime.dart#L557) uzak odaya ait durumla karışır.
- **Lisans Wi-Fi adına, IP adresine veya ödeme kartına bağlanmaz.** Satın alınan hak ve oda/kurulum kimliği kullanılır. Aynı ağda olmak tek başına aile üyeliği veya lisans yönetme yetkisi değildir. Mevcut eşleştirme yerel teslim yetkisini sağlar; satın alma sahipliği ve cihaz ekleme yetkisi ayrıca backend'de doğrulanır.
- **Oda aktivasyonu küçük ve tekrar gönderilebilir bir işlemdir.** Örneğin `POST /broadcast-access/activate`, hedef oda kimliği, entitlement kimliği, aktivasyon kimliği ve backend'in doğrulanabilir imzasını taşıyan bir belge alır. Aynı aktivasyon tekrar gelirse tekrar ücret veya yeni hak üretilmez. Ham mağaza makbuzu odaya taşınmaz.
- **Kartı olmayan oda internet istemeden etkinleşebilir.** Mağaza doğrulaması internetli ebeveyn üzerinden backend'de yapılır; oda imzalı belgeyi yerelde doğrular. Bu işlem yalnız aktivasyonda yapılır, video veya ses karelerine eklenmez.
- **Ödemeden sonra LAN koparsa hak kaybolmaz.** Kalıcı teslimat, aynı oda kimliği için yeniden bağlanınca devam eder. IP değişmesi yeni satın alma nedeni olmaz. Telefonun verileri silinip kimliği değişirse yeniden bağlama gerekir.
- **Ödeme sırasında başka oda seçilirse hedef değişmez.** İşlem başlangıcındaki oda/entitlement bağlamı saklanır; geç gelen sonuç güncel ekrana göre rastgele B odasına uygulanmaz.
- **Aile kapsamı ayrı ürün politikasıdır.** Tek oda seçilirse transfer ve eski odayı devre dışı bırakma kuralları gerekir. Çoklu oda seçilirse bir aile üyeliği ve satın alma sahibini kurtarma yolu gerekir. Uygulamada şu an ortak aile hesabı yok; aynı mağaza hesabıyla restore, eşleşmiş sahip üzerinden aktivasyon ve platform değişiminde kurtarma yöntemi tanımlanmalı.
- **Yerel kullanım devam eder.** Aktif yayında sürekli lisans sunucusu sorgusu veya ebeveynin ağda kalma zorunluluğu eklenmemeli. Uzun süre tamamen çevrimdışı cihazın iadesini anında öğrenmek mümkün değildir; bunun kabul edilen gecikmesi ürün kuralı olmalı. Tek aktif oda transferi ile sınırsız çevrimdışı geçerlilik aynı anda kesin garanti edilemez.

## Senaryo matrisi

“Test var” gerçek mağaza tahsilatı anlamına gelmez; aksi belirtilmedikçe otomatik test veya kod incelemesidir. “Eksik” hedef davranışın uygulanmadığını belirtir.

| No | Senaryo | Beklenen davranış | Mevcut durum |
| --- | --- | --- | --- |
| 01 | Oda telefonunda kart yok; ebeveynde var | Ebeveyn öder, seçili oda açılır. | Eksik; ana ihtiyaç. |
| 02 | Oda telefonunda mağaza hesabı yok veya ödeme kısıtlı | Ebeveynin mağaza hesabı yeterli; odada kart ekletilmez. | Uzak aktivasyon eksik. |
| 03 | Oda internetsiz, ebeveyn internete çıkabiliyor | Ebeveyn doğrular, LAN üzerinden belge teslim eder. | İmzalı offline aktivasyon eksik. |
| 04 | İki telefon da internetsiz, ilk satın alma | Ödeme başlatılamadığı açık gösterilir; geçerli mevcut lisans varsa kullanılmaya devam eder. | Yeni ödeme mağazaya bağlı; uzak akış yok. |
| 05 | Android ebeveyn → iPhone oda veya tersi | Hakkı MiuCam doğrular; oda mağazası üzerinden tekrar satın alma istenmez. | Mağazalar arası aktivasyon/kurtarma eksik. |
| 06 | Farklı mağaza hesabına sahip ikinci ebeveyn | Lisanslı odadan izler; ikinci satın alma gerekmez. | Oda yerel olarak açılmışsa destekleniyor; lisans sahipliği paylaşımı ayrı. |
| 07 | İki veya daha fazla oda telefonu | Lisansın oda kapsamı satın almadan önce açık gösterilir. | Ürün kararı ve oda bağlama modeli eksik. |
| 08 | İki ebeveyn aynı anda satın almaya basıyor | Aynı aile için ortak işlem durumu/ön kontrol; iki mağaza işlemi oluşursa açık destek/iade yolu. | Aile kimliği ve ortak satın alma koordinasyonu yok. |
| 09 | Kullanıcı satın alma düğmesine art arda basıyor | Tek mağaza akışı; diğer tıklamalar yeni işlem açmaz. | Aktif çağrı sırasında koruma var; pending timeout sonrasında hata var. |
| 10 | Kart reddi veya kullanıcı iptali | Lisans açılmaz, tekrar deneme mümkün; gerekirse terminal mağaza işlemi temizlenir. | Genel sonuçlar var; StoreKit1 terminal completion eksik. |
| 11 | Ask to Buy / bekleyen ödeme | “Mağaza onayı bekleniyor”; hak verilmez, yeni ödeme başlatılmaz. | Hak verilmemesi doğru; timeout sonrası ikinci girişim repro ile doğrulandı. |
| 12 | Pending günler sonra uygulama kapalıyken tamamlanıyor | Açılışta mevcut alımlar bulunur ve kalıcı hak teslim edilir. | Açılış/ön plan mutabakatı eksik; canlı stream testi bunu kanıtlamaz. |
| 13 | Mağaza başarılı, verifier bağlantısı kesiliyor | “Ödeme kontrol ediliyor”; kalıcı tekrar deneme, yeniden satın alma önerilmez. | Doğrulama reddi/genel hata var; kalıcı pending verification kuyruğu yok. |
| 14 | Verifier geçici 5xx/timeout veriyor | Geçerli eski lisans korunur; yeni işlem doğrulanana kadar bekler. | Hata ile kesin hak reddi ayrımı eksik. |
| 15 | Mağaza işlemi uygulamaya iki kez geliyor | Aynı hak bir kez kaydedilir; gereken mağaza completion tekrar denenebilir. | Aynı runtime içinde duplicate/ack retry testleri var; kalıcı süreçler arası teslimat günlüğü eksik. |
| 16 | Ödeme sırasında uygulama kapanıyor veya rol değişiyor | Hak ya kalıcı teslim edilmiştir ya da yeniden bulunabilecek pending durumdadır. | Ack var, yerel hak yok yarışı repro ile doğrulandı. |
| 17 | completePurchase takılıyor | UI/rol kapanışı takılmaz; tamamlanacak işlem kaybolmadan tekrar denenir. | Repro ile başarısız. |
| 18 | Ödeme tamamlandı, oda telefonu kapandı | “Satın alındı, odaya aktarım bekliyor”; tekrar ücret yok. | Uzak teslimat ve kuyruk eksik. |
| 19 | Oda hakkı kaydetti, başarı yanıtı LAN'da kayboldu | Aynı aktivasyon tekrar gönderilir; oda mevcut başarıyı döner. | Uzak aktivasyonun idempotency sözleşmesi eksik. |
| 20 | A odası için ödeme sürerken B seçiliyor | İşlem A bağlamında tamamlanır; B'ye yanlış durum/hak gösterilmez. | Uzak satın alma yok; normal oda geçişinde bile stale snapshot repro'su var. |
| 21 | Kilitli A'dan ücretsiz B'ye geçiliyor | B'nin kendi deneme süresi gösterilir. | A'nın kilitli mesajı B kartına taşınıyor; B izlemeye başlayınca düzeliyor. |
| 22 | Lisanslı A'dan kilitli B'ye geçiliyor | B lisanslı görünmez; gerekiyorsa sahip olduğu hakla B'yi etkinleştir seçeneği çıkar. | A'nın açık snapshot'ı taşınıyor; B sunucusu erişimi yine reddediyor. |
| 23 | Eski sürüm oda uzak aktivasyonu desteklemiyor | Mağaza açılmadan güncelleme gereği gösterilir. | Capability/uyumluluk denetimi eksik. |
| 24 | Telefon yeniden başladı, lisans zaten doğrulanmış | Yerel lisansla yayın açılır; deneme dosyasının yazılabilir olması şart olmaz. | Mevcut testlerle kapsanıyor. |
| 25 | Uygulama silindi veya oda telefonu değiştirildi | Sahip restore yapar, yeni kurulum eşleştirilir; satın alma tekrar istenmez. | Aynı telefonda/store hesabında restore yolu var; uzak yeniden bağlama eksik. |
| 26 | Ebeveyn telefonu kayboldu; yeni telefonda aynı mağaza hesabı | Restore'dan aynı entitlement bulunur; oda cihazları yeniden bağlanır. | Parent restore ve aile kurtarma eksik. |
| 27 | Ebeveyn platform değiştirdi; eski telefon da yok | Ortak hesap veya kurtarma yöntemiyle sahiplik kanıtlanır. | Mevcut Apple/Google restore tek başına bu bağı sağlamıyor. |
| 28 | Farklı mağaza hesabıyla restore, alım bulunamıyor | “Bu hesapta satın alma bulunamadı”; tekrar ödeme zorunluymuş gibi sunulmaz. | Restore var; boş restore timeout sonunda unavailable ve UI genel mesajına düşüyor. |
| 29 | Restore sırasında ürün satışı durdurulmuş veya mağaza kataloğu yok | Önceden alınmış hak, yeni ürün satışından bağımsız geri yüklenebilir. | Restore kataloğa bağımlı değil; mağaza sandbox kabul testi gerekiyor. |
| 30 | İade / chargeback / hak geri alınması | Kesin mağaza sonucu işlenir; yeni aktivasyon reddedilir; geçici internet yokluğu ayrı tutulur. | Revocation yolu yok; explicit restore cache kusuru testle doğrulandı. |
| 31 | Deneme kaydı bozuk, kullanıcı satın almasını geri yüklemek istiyor | Ücretli hak kurtarma çalışır; deneme verisi ücretsiz erişim açılmadan onarılır. | Restore mağazaya gitmeden hata veriyor; repro var. |
| 32 | Disk dolu veya lisans kaydı yazılamıyor | Yanlış başarı mesajı verilmez; doğrulanmış alım kaybolmadan tekrar teslim edilir. | Başarısız grant'i açık göstermeme testleri var; ack öncesi kalıcı teslimat garantisi eksik. |
| 33 | Deneme yayın sırasında bitiyor | Sunucu medya/bildirim takibini kapatır; eşleştirme ve aktivasyon yolu erişilebilir kalır. | Enforcement testleri geçiyor; yeni aktivasyon endpointi henüz yok. |
| 34 | Deneme bitmek üzereyken ödeme onaylanıyor | Odanın güncel lisansı esas alınır; eski ebeveyn sayacı lisanslı yayını kesmez. | İstemci sayaç sonunda uzak durumu tekrar okuyor; uzak aktivasyon yarışı henüz test edilemez. |
| 35 | Beş ebeveyn aynı odayı bir dakika izliyor | Deneme bir dakika azalır; beş dakika azalmaz. | Mevcut trial testleri kapsıyor. |
| 36 | QR ekranı, yerel preview, bağlantısız bekleme | Deneme tüketilmez. | Mevcut politika ve testlerle kapsanıyor. |
| 37 | Altıncı ebeveyn lisanslı odayı açıyor | Mevcut beş izleyici sınırı açık hata ile korunur. | Lifetime restore sonrası sınırın korunduğu test var. |
| 38 | Wi-Fi adı/IP/router değişiyor | Aynı oda kimliği lisansını korur; yeniden bağlantı satın alma gerektirmez. | Yerel hak IP'ye bağlı değil; otomatik endpoint rebind ayrı kısıt, yeniden eşleştirme gerekebilir. |
| 39 | Oda başka aileye veriliyor veya sahip eşleşmeyi kaldırıyor | İzleme izni, lisans sahipliği ve cihaz lisansından çıkarma ayrı yönetilir. | Aile/cihaz lisans yönetimi eksik; eşleştirme silmek mağaza alımını silmek değildir. |
| 40 | Fiyat/ülke/para birimi değişiyor | Checkout mağazanın güncel fiyatını gösterir; eski satın alma geçerli kalır. | Yerelleştirilmiş fiyat mevcut; uzun süreli ürün cache'i için yenileme ve sandbox testi gerekli. |
| 41 | SKU adı eski fiyatı içeriyor | SKU değiştirilmez; eski hak ve restore korunur. | `miucam_lifetime_unlock_try_300` korunuyor; Türkiye hedefi 350 TL. |
| 42 | Backend yapılandırması yok veya ürün mağazada yok | Ödeme sayfası açılmadan anlaşılır durum; denemeden sonra çalışır satın alma yolu olmadan release yapılmaz. | Yapılandırmasız checkout'u açmama testi geçiyor; gerçek mağaza/backend kabulü yapılmadı. |
| 43 | Süresi dolmuş/iptal eşleştirme ile aktivasyon | Önce yeniden yetkili eşleştirme; para tekrar alınmaz. | Mevcut trusted pairing yeniden kullanılabilir; aktivasyon akışı eksik. |
| 44 | Sürekli çevrimdışı eski odaya tek-oda lisansı taşınıyor | Eski cihazın ne zamana kadar çalışabileceği satın alma kuralında açık olur. | Tam offline kullanım ile anlık uzaktan iptal birlikte garanti edilemez; ürün kararı gerekir. |

## Kullanıcıya gösterilecek durumlar

Tek “başarılı/başarısız” mesajı bu akış için yeterli değildir. Önerilen kısa metinler:

| Durum | Örnek metin |
| --- | --- |
| Ödeme başlamadan | “Bu telefondan satın al · Bebek Odası'nda kullan” |
| Mevcut hak bulundu | “Satın alman bulundu. Bu oda telefonunda etkinleştir.” |
| Mağaza bekletiyor | “Ödeme mağaza onayı bekliyor.” |
| Mağaza başarılı, doğrulama tamamlanmadı | “Satın alma kontrol ediliyor. Tekrar satın alman gerekmiyor.” |
| Hak var, oda bağlantısı yok | “Satın alındı. Oda telefonuna bağlanınca etkinleştirilecek.” |
| Oda kalıcı kaydı onayladı | “Bebek Odası için ömür boyu kullanım etkin.” |
| Yanlış mağaza hesabıyla restore | “Bu mağaza hesabında satın alma bulunamadı. Satın aldığın hesabı kontrol et.” |

Mesajlar ödeme gerçekliğine dayanmalı: yalnız mağaza sayfasının kapanması “satın alındı” demek değildir. Lisans olayları bebek hareketi/ağlama bildirim kanalıyla karıştırılmamalı; işlem durumu satın alma ekranında gösterilmeli, tekrar deneyen her LAN isteği ayrı bildirim üretmemeli.

## Doğrulama sonuçları ve sınırlar

- Monetization, verifier transport, checkout configuration, uzak durum ve sunucu enforcement: **49 mevcut test geçti** (`build/purchase_review_2026-09-27/existing_purchase_tests.log`).
- Satın alma kartları, client composition ve bildirim erişim ekranları: **18 mevcut test geçti** (`purchase_ui_tests.log`). Böylece bu tur seçilen mevcut testlerde toplam **67 başarılı test** var.
- `purchase_edge_cases_test.dart`: **6 beklenen davranış testi başarısız**. Bunlar yeni keşfedilen kusurları görünür kılıyor; dördü genel yaşam döngüsü/restore/pending sorunları, ikisi StoreKit1 terminal işlem koşulu. Log: `purchase_edge_cases.log`.
- `client_room_license_review_test.dart`: **2 test mevcut oda durumu karışıklığını yeniden üretti**. Bunların geçmesi bug'ın çözüldüğü anlamına gelmez.
- `trial_restore_review_test.dart`: **1 test bozuk deneme kaydının restore'u bloke ettiğini yeniden üretti**. Yine bug'ı tespit eden bir testtir.
- Yeni reproducer ve loglar `build/purchase_review_2026-09-27/` altında. Native completion ve verifier sonuçları kontrol edilen sahte mağazayla üretildi; gerçek tahsilat veya gerçek iade yapılmadı.
- Tüm uygulama test paketi bu tur tekrar çalıştırılmadı; ürün kodu değişmedi. Bu sonuçlar Google Play/App Store sandbox kabulünün yerine geçmez.

## Uygulama sırası

1. Satın alma günlüğü, ack/teslimat sırası, kapanış, pending ve restore kusurlarını düzelt; ilgili reproducer'ları kalıcı regresyon testine dönüştür.
2. Parent satın alma koordinatörünü oda enforcement servisinden ayır; açılış/ön plan hak mutabakatını ekle.
3. Lisans kapsamını tanımla; backend hak/oda bağlama ve imzalı aktivasyon sözleşmesini uygula. Başarılı ödeme + başarısız LAN teslimini kalıcı olarak kurtar.
4. Oda bazlı UI durumunu düzelt; parent satın al/restore/etkinleştir akışını ve dillerdeki “yalnız oda telefonundan satın al” metinlerini güncelle.
5. Android↔Android, iOS↔iOS ve iki çapraz platform yönünde sandbox kabulü; rol değişimi, süreç öldürme, internet/LAN kaybı ve geri yükleme/iade senaryolarını fiziksel cihazlarla tamamla.

## Mağaza belgeleriyle kontrol edilen noktalar

- Google, uygulama açılışında/bağlantı kurulunca mevcut alımları sorgulamayı; tamamlanan işlemi doğrulayıp hakkı teslim ettikten sonra acknowledge etmeyi anlatıyor. Pending durumunda hak verilmez. [Google Play entegrasyonu](https://developer.android.com/google/play/billing/integrate).
- Android'de satın alınmış işlemin zamanında acknowledge edilmemesi otomatik iadeye yol açabilir; kalıcı hak teslimi ile mağaza tamamlaması birlikte tasarlanmalıdır. [Google Play satın alma doğrulaması](https://developer.android.com/google/play/billing/security).
- Flutter paketi restore sonuçlarının purchase stream'den geldiğini ve doğrulama/içerik tesliminden sonra `completePurchase` gerektiğini belirtiyor. [Resmî in_app_purchase paketi](https://pub.dev/packages/in_app_purchase).
- Apple, normal hak okuması ile kullanıcı tarafından başlatılan zorunlu sync'i ayırıyor; `sync()` kimlik doğrulama istemi açabileceğinden yalnız açık kullanıcı eyleminde çağrılmalı. Bu nedenle iOS'ta her resume'da restore düğmesine basılmış gibi davranılmamalı. [AppStore.sync](https://developer.apple.com/documentation/storekit/appstore/sync()).
- İade ve Family Sharing değişiklikleri hak kaybı üretebilir. Aile lisansı tasarımı, mağazanın Family Sharing özelliğiyle otomatik olarak aynı şey değildir. [Apple hak geri alma bildirimi](https://developer.apple.com/documentation/storekit/skpaymenttransactionobserver/paymentqueue(_:didrevokeentitlementsforproductidentifiers:)).
