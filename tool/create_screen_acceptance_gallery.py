"""Build an inspectable gallery from Flutter host-rendered acceptance captures."""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import shutil
from pathlib import Path


SCREEN_NAMES = {
    '01_role': 'Mod seçimi',
    '02_parent_unpaired': 'Ebeveyn · eşleştirilmemiş',
    '03_find_room': 'Oda bul · QR / IP',
    '04_notifications': 'Bildirimler · geçmiş ve filtreler',
    '05_parent_settings': 'Ebeveyn ayarları',
    '06_parent_paired': 'Ebeveyn · bağlı oda',
    '07_qr_permission_denied': 'QR · kamera izni yok / manuel giriş',
    '08_watch_live': 'Canlı izleme',
    '09_watch_history': 'Olay geçmişi',
    '10_watch_settings': 'İzleme ayarları',
    '11_room_controls': 'Oda kontrolleri',
    '12_watch_connection_error': 'İzleme · bağlantı hatası',
    '13_server_preview_off': 'Oda · yerel önizleme kapalı',
    '14_server_preview_on': 'Oda · yerel önizleme açık',
    '15_server_qr_ip': 'Oda · QR / IP eşleştirme',
    '16_server_services': 'Oda · servis durumu',
    '17_server_settings': 'Oda ayarları',
}
PURCHASE_NAMES = {
    'ready': 'Satın almaya hazır',
    'purchasing': 'Mağaza işlemi sürüyor',
    'pending': 'Mağaza onayı bekleniyor',
    'verification_pending': 'Satın alma doğrulanmayı bekliyor',
    'activating': 'Oda lisansı etkinleştiriliyor',
    'activation_pending': 'Oda çevrimdışı · lisans teslimi bekliyor',
    'active': 'Aile lisansı etkin',
    'revoked': 'Mağaza iadesi / iptali',
    'unavailable': 'Satın alma kullanılamıyor',
    'room_update_required': 'Oda uygulaması güncellenmeli',
    'no_purchase_found': 'Geri yüklenecek satın alma bulunamadı',
    'failed': 'Satın alma başarısız',
    'canceled': 'Kullanıcı satın almayı iptal etti',
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--screens', type=Path, default=Path('build/app_acceptance/screens'))
    parser.add_argument('--purchases', type=Path, default=Path('build/purchase_ui'))
    parser.add_argument('--output', type=Path, default=Path('build/app_acceptance/gallery'))
    args = parser.parse_args()
    items: list[dict[str, object]] = []

    def capture(source: Path, category: str, title: str) -> None:
        if not source.is_file():
            raise FileNotFoundError(f'Required Flutter capture is missing: {source}')
        destination = args.output / category / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        items.append({
            'title': title,
            'category': category,
            'path': destination.relative_to(args.output).as_posix(),
            'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
        })

    for name, title in SCREEN_NAMES.items():
        capture(args.screens / f'{name}.png', 'screens', title)
        bottom = args.screens / f'{name}_bottom.png'
        if bottom.is_file():
            capture(bottom, 'screens', f'{title} · aşağı kaydırılmış')
        else:
            (args.output / 'screens' / bottom.name).unlink(missing_ok=True)
    for name, title in PURCHASE_NAMES.items():
        capture(args.purchases / f'{name}.png', 'purchases', title)

    manifest = {
        'renderer': 'Flutter host widget renderer',
        'locale': 'tr',
        'screens': len(SCREEN_NAMES),
        'purchaseStates': len(PURCHASE_NAMES),
        'viewport': {'screens': [390, 844], 'purchases': [320, 568]},
        'fixtures': 'Generated loopback media; mocked native output and store states; no real charges.',
        'items': items,
    }
    (args.output / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    cards = '\n'.join(
        f'<article data-category="{item["category"]}"><h2>{html.escape(str(item["title"]))}</h2>'
        f'<a href="{item["path"]}" target="_blank" rel="noopener">'
        f'<img src="{item["path"]}" alt="{html.escape(str(item["title"]))}"></a></article>'
        for item in items
    )
    page = '''<!doctype html>
<html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MiuCam · Ekran ve ödeme kabul galerisi</title>
<style>
*{box-sizing:border-box}body{margin:0;padding:28px;background:#f4f3fa;color:#162033;font:15px/1.5 system-ui,sans-serif}
main{max-width:1160px;margin:auto}h1{font-size:28px;margin:0 0 8px}p{max-width:850px;margin:6px 0;color:#526071}
nav{display:flex;flex-wrap:wrap;gap:8px;margin:20px 0}button{font:inherit;min-height:44px;padding:8px 16px;border:1px solid #cbc7e2;border-radius:12px;background:white;color:#34266f;cursor:pointer}
button[aria-pressed=true]{background:#6257c8;color:white}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px;align-items:start}
article{padding:12px;background:white;border:1px solid #ddd9eb;border-radius:16px}article[hidden]{display:none}h2{font-size:14px;min-height:42px;margin:0 0 10px}
img{display:block;width:100%;height:auto;border-radius:8px}a:focus-visible,button:focus-visible{outline:3px solid #157961;outline-offset:3px}
footer{margin-top:24px;color:#687083;font-size:13px}@media(max-width:800px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:520px){.grid{grid-template-columns:1fr}}
</style><main>
<h1>MiuCam · Ekran ve ödeme kabul galerisi</h1>
<p>17 ekran/durum ve 13 ödeme durumu. Görseller gerçek uygulama widget'larından hostta üretildi; donanım, oda ve mağaza sınırlarında kontrollü test verisi kullanıldı.</p>
<p>Görüntü alanındaki ikon test yayınıdır. Fiyat ve ödeme sonuçları simülasyondur; gerçek mağaza penceresi veya fiziksel cihaz görüntüsü değildir. Görsele tıklayarak tam boyutta açabilirsiniz.</p>
<nav aria-label="Galeri filtresi"><button data-filter="all" aria-pressed="true">Tümü</button><button data-filter="screens" aria-pressed="false">Ekranlar</button><button data-filter="purchases" aria-pressed="false">Ödeme durumları</button></nav>
<div class="grid">CARDS</div>
<footer>Bu görseller davranış testlerini tamamlar. Mağazanın kendi ödeme penceresi, gerçek hoparlör/kamera ve uzun süreli pil kabulü ayrı doğrulamalardır.</footer>
</main><script>
const cards=[...document.querySelectorAll('article')];
const buttons=[...document.querySelectorAll('[data-filter]')];
function filter(value){cards.forEach(c=>c.hidden=value!=='all'&&c.dataset.category!==value);buttons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===value)));}
buttons.forEach(b=>b.addEventListener('click',()=>filter(b.dataset.filter)));
const group=new URLSearchParams(location.search).get('group');
if(group!==null&&/^\\d+$/.test(group)){const start=Number(group)*6;cards.forEach((c,i)=>c.hidden=i<start||i>=start+6);}
</script></html>'''.replace('CARDS', cards)
    (args.output / 'index.html').write_text(page, encoding='utf-8')
    print(f'{len(items)} captures written to {args.output / "index.html"}')


if __name__ == '__main__':
    main()
