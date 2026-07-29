# MiuCam Gizlilik Bildirimi

Son güncelleme: 15 Temmuz 2026

> Bu metin mağaza yayını öncesi taslaktır. Nihai yayında geliştirici/veri
> sorumlusu kimliği ve özel gizlilik başvuru kanalı eklenecektir.

MiuCam, bebek odası ile ebeveyn cihazı arasında aynı yerel ağ üzerinden
çalışan bir kamera ve ses izleme uygulamasıdır. Varsayılan kullanımda hesap,
reklam, analiz SDK'sı veya bulut medya aktarımı kullanılmaz.

## İşlenen veriler

- Kamera görüntüsü ve mikrofon sesi; yayın ile yerel ağlama benzeri ses, yüksek
  ses, hareket ve ışık değişimi analizi için oda cihazında işlenir.
- Canlı görüntü, ses, kontrol mesajları ve uyarılar yalnızca kullanıcının
  eşleştirdiği yerel ağ cihazlarına gönderilir.
- Eşleşme bilgileri, cihaz tercihleri ve bildirim geçmişi uygulama verisi olarak
  cihazda saklanır.
- Client erişim anahtarları işletim sisteminin güvenli anahtar deposunda
  saklanır. Server tarafında ham erişim anahtarı yerine doğrulama özeti tutulur.

## İnternet ve üçüncü taraflar

MiuCam'in temel izleme işlevi internet bağlantısı olmadan çalışır. İsteğe bağlı
uygulama içi satın alma etkinleştirilirse Apple App Store veya Google Play ödeme
altyapısı kullanılır. Satın alma doğrulama verisi yalnızca yapılandırılmış,
güvenilir HTTPS doğrulama servisine gönderilebilir. Kamera ve mikrofon medyası bu
servise gönderilmez.

## Saklama ve silme

Eşleşmeler uygulama içinden kaldırıldığında ilgili güvenli erişim anahtarları da
silinir. Bildirim geçmişi uygulama içinden temizlenebilir. Güvenli erişim
anahtarları cihaz yedeklerine veya başka bir cihaza taşınacak şekilde
yapılandırılmaz. iOS bir uygulama kaldırıldığında Keychain kayıtlarını korursa,
MiuCam temiz kurulumun ilk açılışında önceki kuruluma ait kayıtları temizler.

## İzinler

Kamera, mikrofon, yerel ağ, bildirim ve Android arka plan servisi izinleri
yalnızca ilgili MiuCam işlevleri için kullanılır. İzinler işletim sistemi
ayarlarından geri alınabilir; geri alınan izne bağlı özellikler çalışmayı
durdurur.

## Çocuk güvenliği

MiuCam yetişkin gözetiminin, tıbbi cihazların veya acil durum hizmetlerinin
yerini almaz. Kullanıcı, cihaz yerleşimi ve güvenli kullanımından sorumludur.

## İletişim

Teknik geri bildirim için herkese açık GitHub Issues kanalı kullanılabilir;
kişisel, hassas veya çocuğa ait veri burada paylaşılmamalıdır. Gizlilik ve veri
talepleri için mağaza yayınıyla birlikte duyurulacak özel geliştirici destek
kanalı kullanılacaktır.
