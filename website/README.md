# MimiCam tanıtım sitesi

MimiCam mobil uygulamasından bağımsız, derleme adımı ve üçüncü taraf çalışma
zamanı bağımlılığı olmayan statik tanıtım sitesidir.

## Yerelde çalıştırma

Repo kökünden:

```bash
python3 -m http.server 8080 --directory website
```

Ardından `http://localhost:8080` adresini açın. Dosyayı doğrudan
`file://` ile açmak yerine HTTP sunucusu kullanmak, dağıtım davranışını daha
doğru temsil eder. Çeviri katalogları çalışma anında `fetch` ile yüklendiği
için çok dilli yapı `file://` altında güvenilir biçimde çalışmaz.

## Çok dilli yapı

Site sekiz dili destekler:

| Kod | Dil | Yön |
| --- | --- | --- |
| `tr` | Türkçe | Soldan sağa |
| `en` | İngilizce | Soldan sağa |
| `de` | Almanca | Soldan sağa |
| `fr` | Fransızca | Soldan sağa |
| `es` | İspanyolca | Soldan sağa |
| `zh` | Çince | Soldan sağa |
| `hi` | Hintçe | Soldan sağa |
| `ar` | Arapça | Sağdan sola (RTL) |

Dil, üst menüdeki seçiciden değiştirilebilir veya URL'de `?lang=` parametresiyle
doğrudan belirtilebilir:

```text
http://localhost:8080/?lang=en
http://localhost:8080/privacy.html?lang=ar
```

Geçerli bir `?lang=` değeri ilk tercihtir. Parametre yoksa son seçim
`mimicam.website.language` anahtarıyla `localStorage` üzerinden geri yüklenir;
ikisi de yoksa Türkçe kullanılır. Seçiciden yapılan değişiklik hem URL'yi hem
de bu yerel tercihi günceller; site içi sayfa bağlantıları da seçili dili
`lang` parametresiyle taşır. Böylece depolamanın kapalı olduğu tarayıcılarda da
sayfa geçişinde dil korunur. Arapça seçildiğinde belgeye `lang="ar"` ve
`dir="rtl"`, diğer dillerde `dir="ltr"` uygulanır.

Türkçe kaynak katalog `locales/tr.json` dosyasıdır. Diğer yedi JSON dosyası
aynı anahtar kümesini eksiksiz taşımalıdır. Yeni bir metin eklerken anahtarı
sekiz kataloğa da ekleyin; `{year}` gibi çalışma anında biçimlendirilen
belirteçleri çevirilerde aynen koruyun. Dil listesi veya kodları değişirse
`i18n.js`, iki sayfadaki dil seçiciler, kataloglar ve doğrulayıcı birlikte
güncellenmelidir.

## Doğrulama

```bash
node --check website/app.js
node --check website/i18n.js
node website/scripts/validate.mjs
```

Doğrulama; sayfa yapısını, yerel bağlantıları, görsel boyut/alt metinlerini,
JSON-LD verisini, manifest ikonlarını ve temel erişilebilirlik korumalarını
kontrol eder. Ayrıca iki sayfada dil seçicinin ve `i18n.js` bağlantısının
bulunduğunu; sekiz locale dosyasının geçerli JSON olduğunu; tüm değerlerin boş
olmayan stringlerden oluştuğunu; anahtar kümeleriyle `{year}` belirteçlerinin
Türkçe kaynakla birebir eşleştiğini doğrular.

Dağıtım artifact'i gibi farklı bir kökü aynı kurallarla kontrol etmek için:

```bash
SITE_ROOT=/path/to/site node website/scripts/validate.mjs
```

Chrome yüklü bir geliştirme ortamında gerçek tarayıcı smoke testi de çalışır:

```bash
node --experimental-websocket website/scripts/browser-smoke.mjs http://127.0.0.1:8080
```

Bu kontrol masaüstü, mobil ve gizlilik sayfası senaryolarında kırık görsel,
JavaScript hatası, yatay taşma, görünmeden kalan animasyon öğesi ve mobil menü
davranışını denetler; tam sayfa ekran görüntülerini `/tmp/mimicam-browser-smoke`
altına yazar.

## Dağıtım

`.github/workflows/website.yml`, `website/` klasörünü GitHub Pages artifact'i
olarak yayınlar. Artifact; HTML/CSS/JavaScript dosyalarının yanında `assets/`
ve çalışma anında gereken `locales/` klasörünü de içerir. Repo ayarlarında
**Settings → Pages → Source → GitHub Actions** seçili olmalıdır. Aynı klasör
Netlify, Cloudflare Pages veya benzeri statik hosting servislerine de doğrudan
verilebilir; `_headers` dosyası bu servislerde güvenlik ve cache başlıklarını
etkinleştirir. Locale JSON dosyaları kısa süreli ayrı bir cache kuralı kullanır,
böylece çeviri düzeltmeleri statik görsellere göre daha hızlı yayılır. GitHub
Pages `_headers` dosyasını uygulamaz; bu hedefte aynı başlıklar ancak önüne
destekleyen bir proxy/CDN konularak sağlanabilir.

Özel alan adı belli olduğunda:

1. `index.html` içindeki geçici GitHub Pages canonical, `og:url`, sosyal görsel
   ve JSON-LD URL'lerini yeni alan adıyla güncelleyin.
2. `sitemap.xml` ve `robots.txt` içindeki GitHub Pages URL'sini değiştirin.
3. Gizlilik metni nihai hale geldiğinde `privacy.html` için canonical ekleyip
   `noindex` değerini kaldırın.
4. Hosting sağlayıcısında HTTPS ve alan adı yönlendirmesini etkinleştirin.

App Store ve Google Play bağlantıları doğrulanana kadar sahte mağaza rozeti
eklenmemelidir. Gerçek bağlantılar geldiğinde ana CTA alanı güncellenebilir.

## İçerik sınırları

Tanıtım metni mevcut ürün davranışına göre hazırlanmıştır: MimiCam aynı yerel
ağda çalışır; uzak internet izleme, APNs/FCM bildirimi, TLS/uçtan uca şifreleme,
iOS arka plan kamera veya tıbbi cihaz iddiası içermez. Bu özelliklerden biri
değişirse site metni, SSS ve gizlilik bildirimi birlikte güncellenmelidir.
