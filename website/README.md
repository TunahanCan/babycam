# MiuCam tanıtım sitesi

MiuCam mobil uygulamasından bağımsız, üçüncü taraf çalışma zamanı bağımlılığı
olmayan statik tanıtım sitesidir. Küçük bir Node.js derleme adımı, sekiz dil
için taranabilir HTML sayfaları ve dile özel web manifestleri üretir.

## Yerelde çalıştırma

Dağıtımla aynı yapıyı yerelde görmek için repo kökünden:

```bash
node website/scripts/build.mjs /tmp/miucam-site
python3 -m http.server 8080 --directory /tmp/miucam-site
```

Ardından Türkçe için `http://localhost:8080/`, İngilizce için
`http://localhost:8080/en/` adresini açın. Dosyayı doğrudan `file://` ile
açmak yerine HTTP sunucusu kullanın; dil değişiminde kataloglar `fetch` ile
yüklendiği için çok dilli yapı `file://` altında güvenilir çalışmaz.

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

Her dilin bağımsız ve paylaşılabilir bir URL'si vardır:

```text
http://localhost:8080/                 # Türkçe
http://localhost:8080/en/             # İngilizce
http://localhost:8080/de/             # Almanca
http://localhost:8080/ar/privacy.html # Arapça gizlilik sayfası
```

Dil seçici kullanıcıyı ilgili dil rotasına geçirir ve seçimi
`miucam.website.language` anahtarıyla `localStorage` içinde saklar. Eski
`?lang=` bağlantıları geriye dönük olarak okunur ve dil rotasına dönüştürülür.
Arapça sayfalarda `lang="ar"` ve `dir="rtl"`, diğerlerinde `dir="ltr"`
kullanılır. Kullanıcılar IP veya tarayıcı diliyle otomatik olarak başka bir
sayfaya yönlendirilmez; uluslararası kampanyalar doğrudan doğru dil URL'sine
bağlanmalıdır.

Derleme; her dil için yerelleştirilmiş title, description, Open Graph,
JSON-LD, self-canonical ve karşılıklı `hreflang` etiketlerini HTML kaynağına
yazar. `sitemap.xml` tüm dil rotalarını bildirir. Böylece içerik yalnız
JavaScript sonrasında değil, arama ve sosyal paylaşım botlarının aldığı ilk
HTML içinde de yerelleştirilmiş olur.

Üretim taban URL'si varsayılan olarak `index.html` içindeki canonical'dan
alınır. Geçici veya özel alan adı derlemelerinde açıkça değiştirilebilir:

```bash
SITE_URL=https://www.example.org/miucam/ node website/scripts/build.mjs /tmp/miucam-site
```

Bu değer canonical, `hreflang`, Open Graph, JSON-LD, sitemap ve robots
adreslerine birlikte uygulanır.

Türkçe kaynak katalog `locales/tr.json` dosyasıdır. Diğer yedi JSON dosyası
aynı anahtar kümesini eksiksiz taşımalıdır. Yeni bir metin eklerken anahtarı
sekiz kataloğa da ekleyin; `{year}` gibi çalışma anında biçimlendirilen
belirteçleri çevirilerde aynen koruyun. Dil listesi veya kodları değişirse
`i18n.js`, `language-init.js`, `scripts/build.mjs`, iki sayfadaki dil
seçiciler, kataloglar, sitemap ve doğrulayıcı birlikte güncellenmelidir.

## Doğrulama

```bash
node --check website/app.js
node --check website/language-init.js
node --check website/i18n.js
node --check website/scripts/build.mjs
node website/scripts/validate.mjs
node website/scripts/build.mjs /tmp/miucam-site
SITE_ROOT=/tmp/miucam-site node website/scripts/validate.mjs
```

Doğrulama; sayfa yapısını, yerel bağlantıları, görsel boyut/alt metinlerini,
JSON-LD verisini, manifest ikonlarını ve temel erişilebilirlik korumalarını
kontrol eder. Derlenmiş artifact üzerinde ayrıca 16 yerelleştirilmiş sayfanın
varlığını, doğru `lang`/`dir`, self-canonical, karşılıklı `hreflang` ve sekiz
yerel manifesti denetler. Locale dosyalarının anahtar kümeleriyle `{year}`
belirteçleri Türkçe kaynakla birebir eşleşmelidir.

Chrome yüklü bir geliştirme ortamında gerçek tarayıcı smoke testi de çalışır:

```bash
node --experimental-websocket website/scripts/browser-smoke.mjs http://127.0.0.1:8080
```

Bu kontrol Türkçe masaüstü, İngilizce tablet, Arapça RTL mobil, 320 px Almanca
ve Almanca/Arapça gizlilik sayfası senaryolarında kırık görsel, JavaScript
hatası, yatay taşma, görünmeden kalan animasyon öğesi, dil rotası ve mobil menü
davranışını denetler; tam sayfa ekran görüntülerini
`/tmp/miucam-browser-smoke` altına yazar.

## Dağıtım

`.github/workflows/website.yml`, yerelleştirilmiş siteyi `_site/` içine üretir,
kaynak ve artifact doğrulamalarını çalıştırır, gerçek tarayıcıyla sınar ve
GitHub Pages'a yayınlar. Repo ayarlarında bir kez **Settings → Pages → Source →
GitHub Actions** seçilmelidir; bu ayar kapalıysa `configure-pages` adımı siteyi
oluşturamaz. Yayından sonra workflow hem ana sayfayı hem `/en/` rotasını HTTP
ile doğrular.

Aynı artifact Netlify, Cloudflare Pages veya benzeri statik hosting
servislerine verilebilir. `_headers` bu servislerde güvenlik ve cache
başlıklarını etkinleştirir. GitHub Pages `_headers` dosyasını uygulamaz; aynı
başlıklar ancak destekleyen bir proxy/CDN ile sağlanabilir.

Özel alan adı belli olduğunda:

1. CI derleme komutuna sonu `/` ile biten üretim `SITE_URL` değerini ekleyin
   veya `index.html` içindeki canonical tabanını güncelleyin.
2. Gizlilik metni ve sorumlu kişi bilgileri nihai hale geldiğinde
   `privacy.html` üzerindeki `noindex` değerini kaldırın.
3. Hosting sağlayıcısında HTTPS ve alan adı yönlendirmesini etkinleştirin.

App Store ve Google Play bağlantıları doğrulanana kadar sahte mağaza rozeti
eklenmemelidir. Gerçek bağlantılar geldiğinde ana CTA alanı güncellenebilir.

## İçerik sınırları

Tanıtım metni mevcut ürün davranışına göre hazırlanmıştır: MiuCam aynı yerel
ağda çalışır; uzak internet izleme, APNs/FCM bildirimi, TLS/uçtan uca şifreleme,
iOS arka plan kamera veya tıbbi cihaz iddiası içermez. Bu özelliklerden biri
değişirse site metni, SSS ve gizlilik bildirimi birlikte güncellenmelidir.
