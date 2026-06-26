from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCREENS = ROOT / 'build/screen_report/screens'
OUT = ROOT / 'docs/reports/mimicam_ekranlar_akislar_usecase_raporu.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)

W, H, M = 1240, 1754, 72
BG = (250, 248, 245)
NAVY = (31, 25, 49)
SLATE = (108, 116, 134)
PINK = (255, 86, 126)
MINT = (112, 215, 198)
AMBER = (255, 210, 116)
CARD = (255, 255, 255)
LINE = (232, 222, 216)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def f(size: int, bold: bool = False):
    return ImageFont.truetype(BOLD if bold else FONT, size)

F = {
    'cover': f(76, True), 'h1': f(42, True), 'h2': f(30, True),
    'h3': f(24, True), 'body': f(21), 'bodyb': f(21, True),
    'small': f(17), 'smallb': f(17, True), 'tiny': f(14),
}

def new_page(color=BG):
    return Image.new('RGB', (W, H), color)

def text(draw, xy, s, font, fill=NAVY, max_width=None, gap=8):
    x, y = xy
    if max_width is None:
        draw.text((x, y), s, font=font, fill=fill)
        return y + font.size + gap
    words, lines, cur = s.split(), [], ''
    for word in words:
        candidate = f'{cur} {word}'.strip()
        if not cur or draw.textlength(candidate, font=font) <= max_width:
            cur = candidate
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        y += font.size + gap
    return y

def round_rect(draw, box, radius, fill, outline=None, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)

def header(draw, title, subtitle=None):
    draw.text((M, 54), 'MimiCam', font=F['smallb'], fill=PINK)
    draw.text((M, 90), title, font=F['h1'], fill=NAVY)
    y = 148
    if subtitle:
        y = text(draw, (M, y), subtitle, F['body'], SLATE, W - 2 * M, 8) + 8
    draw.line((M, y, W - M, y), fill=LINE, width=2)
    return y + 34

def footer(draw, page_no):
    draw.text((M, H - 52), 'MimiCam ekran tasarımları ve akış raporu', font=F['tiny'], fill=SLATE)
    draw.text((W - M - 48, H - 52), str(page_no), font=F['tiny'], fill=SLATE)

def paste_screen(page, path, box):
    x1, y1, x2, y2 = box
    img = Image.open(path).convert('RGB')
    img.thumbnail((x2 - x1, y2 - y1), Image.Resampling.LANCZOS)
    page.paste(img, (x1 + (x2 - x1 - img.width)//2, y1 + (y2 - y1 - img.height)//2))

pages = []
page_no = 1

def add_page(img):
    global page_no
    ImageDraw.Draw(img)
    pages.append(img)
    page_no += 1

# Cover
p = new_page((20, 16, 45)); d = ImageDraw.Draw(p)
for box, c in [((-140, -100, 420, 420), MINT), ((850, -80, 1400, 460), PINK), ((-120, 1260, 480, 1880), AMBER)]:
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=c + (48,))
    p = Image.alpha_composite(p.convert('RGBA'), layer).convert('RGB')
    d = ImageDraw.Draw(p)
icon_path = ROOT / 'assets/branding/mimicam_icon_wordmark.png'
if icon_path.exists():
    icon = Image.open(icon_path).convert('RGBA')
    icon.thumbnail((250, 250), Image.Resampling.LANCZOS)
    p.paste(icon, (M, 160), icon)
d.text((M, 450), 'MimiCam', font=F['cover'], fill=(255, 255, 255))
text(d, (M, 555), 'Ekran Tasarımları, Use Case ve Akış Raporu', F['h1'], (255, 255, 255), W - 2*M)
text(d, (M, 690), 'LG G6 Android cihaz üzerinde gerçek uygulama widget’larıyla alınan 14 ekran görüntüsü, ürün use-case özetleri ve uçtan uca akış diyagramları.', F['body'], (225, 230, 238), W - 2*M)
y = 835
for label, color in [('14 ekran', PINK), ('Server + Client', MINT), ('QR/IP eşleşme', AMBER), ('Canlı izleme', PINK), ('Çok dilli ürün', MINT)]:
    tw = int(d.textlength(label, font=F['smallb'])) + 40
    round_rect(d, (M, y, M + tw, y + 48), 24, color)
    d.text((M + 20, y + 13), label, font=F['smallb'], fill=NAVY)
    M_plus = M + tw + 14
    M = M_plus
M = 72
d.text((M, 1040), 'Kapsam', font=F['h2'], fill=(255, 255, 255))
items = [
    'İlk açılış rol seçimi ve LAN/Wi‑Fi güvenlik notu',
    'Ebeveyn cihazı: izleme, bul/eşleş, bildirim ve ayarlar',
    'QR scanner, canlı izleme, uyarı geçmişi ve izleme ayarları',
    'Bebek odası/server cihazı: yayın, QR/IP, servis ve algılama ayarları',
    'Ana use-case senaryoları ve akışlar',
]
for i, item in enumerate(items):
    yy = 1115 + i * 58
    d.ellipse((M, yy + 8, M + 18, yy + 26), fill=MINT)
    text(d, (M + 34, yy), item, F['body'], (235, 238, 245), W - 2*M - 34, 4)
footer(d, page_no); add_page(p)

# Inventory
inventory = [
('01','Rol seçimi','İlk açılış; cihaz server mı client mı olacak?'),
('02','Client İzle / boş','Eşleşme yokken ebeveyn cihazının yönlendirmesi.'),
('03','Client Bul','QR tara veya IP:port ile manuel bağlan.'),
('04','Client Bildirim','Ağlama, hareket ve sistem olayları listesi.'),
('05','Client Ayarlar','Dil, bildirim ve cihaz uyanık kalma tercihleri.'),
('06','Client İzle / eşleşmiş','Bebek odası kartı, canlı preview ve durum özetleri.'),
('07','QR Scanner','Native kamera viewport + manuel QR metni fallback.'),
('08','Canlı izleme','Video paneli, kalite/latency metrikleri, aksiyonlar.'),
('09','Uyarı geçmişi','Canlı izleme içi olay zaman çizgisi.'),
('10','İzleme ayarları','Otomatik kalite ve uyarı eşikleri.'),
('11','Server Yayın','Bebek odası medya runtime ve algılama durumu.'),
('12','Server QR/IP','Ebeveyn cihazı eşleştirme bileti ve QR.'),
('13','Server Servis','Kamera, mikrofon, WebSocket ve client sayısı.'),
('14','Server Ayarlar','Algılama eşikleri, cooldown ve süre ayarları.'),
]
p = new_page(); d = ImageDraw.Draw(p)
y = header(d, 'Ekran Envanteri', 'Rapora dahil edilen tüm ana ekranlar ve temsil ettikleri ürün durumu.')
for i, (no, name, desc) in enumerate(inventory):
    yy = y + i * 93
    round_rect(d, (M, yy, W - M, yy + 76), 22, CARD, LINE)
    color = [PINK, MINT, AMBER][i % 3]
    round_rect(d, (M + 18, yy + 16, M + 74, yy + 60), 18, color)
    d.text((M + 33, yy + 31), no, font=F['tiny'], fill=NAVY)
    d.text((M + 92, yy + 15), name, font=F['smallb'], fill=NAVY)
    text(d, (M + 92, yy + 42), desc, F['small'], SLATE, W - 2*M - 110, 2)
footer(d, page_no); add_page(p)

# Use-cases
use_cases = [
('UC-01 İlk rol seçimi','Kullanıcı uygulamayı ilk kez açar. Telefonun “Bebek Odası Cihazı” ya da “Ebeveyn Cihazı” olacağı seçilir. Uygulama LAN/Wi‑Fi kapsamını görünür uyarıyla anlatır.', ['Rol seçimi', 'Rol izni', 'Server veya Client shell']),
('UC-02 Ebeveyn cihazı eşleşir','Anne/ebeveyn cihazı Bul sekmesine gider. QR tarar ya da IP:port girer. Server public status/pairing bilgisi ile güvenli tokenlı oturum oluşur.', ['Client Bul', 'QR Scanner veya IP', 'Pairing session', 'Client İzle / eşleşmiş']),
('UC-03 Bebek odası cihazı yayın açar','Server rolündeki telefon kamera/mikrofon runtime’ını yönetir. QR/IP bileti üretir, aktif client sayılarını izler ve medya/alert servislerini ayırır.', ['Server Yayın', 'Server QR/IP', 'Servis durumu', 'Algılama ayarları']),
('UC-04 Canlı izleme ve uyarı takibi','Ebeveyn canlı yayına girer. Video/audio stream, ağ kalitesi ve server medya profili izlenir; ağ zayıflarsa kalite adaptasyonu devrededir.', ['Client İzle', 'Watch Live', 'Watch History', 'Watch Settings']),
('UC-05 Çok dilli anne odaklı kullanım','Metinler locale catalog üzerinden gelir; dil seçimi ve ebeveyn mesajları farklı dillerde sürdürülebilir olacak şekilde tasarlanır.', ['AppStrings', 'Client Ayarlar', 'Bildirim metinleri']),
]
p = new_page(); d = ImageDraw.Draw(p)
y = header(d, 'Use Case Özeti', 'Ana kullanıcı amaçları, tetikleyiciler ve ilgili ekran kümeleri.')
for i, (title, body, steps) in enumerate(use_cases):
    yy = y + i * 250
    round_rect(d, (M, yy, W-M, yy+218), 28, CARD, LINE)
    d.text((M+28, yy+24), title, font=F['h3'], fill=NAVY)
    by = text(d, (M+28, yy+66), body, F['small'], SLATE, W-2*M-56, 5)
    x = M + 28
    for step in steps:
        tw = int(d.textlength(step, font=F['tiny'])) + 28
        round_rect(d, (x, by+12, x+tw, by+46), 17, (245, 239, 249))
        d.text((x+14, by+21), step, font=F['tiny'], fill=NAVY)
        x += tw + 10
footer(d, page_no); add_page(p)

# Flow pages
flows = [
('Akış 1 · İlk Açılış ve Rol Kararı','Rol seçimi uygulama mimarisini iki ayrı çalışma alanına kilitler.',[
('Rol seçimi','Kullanıcı telefonun görevini seçer.'),('Server rolü','Kamera/mikrofon bu telefonda açılır; QR/IP üretilir.'),('Client rolü','QR/IP ile oda cihazına bağlanır; izleme ve uyarı alır.'),('Rol rozeti','Sonraki ekranlarda küçük badge ile rol değişimi başlatılır.'),('İzin politikası','Kamera, mikrofon, bildirim ve batarya izinleri role göre istenir.')]),
('Akış 2 · Pairing ve Canlı İzleme','Ebeveyn cihazı aynı Wi‑Fi/LAN içinde server cihazına bağlanır.',[
('Client Bul','QR Tara veya Manuel IP ile bağlan kartları.'),('Server QR/IP','Server pairing nonce ve bağlantı bileti üretir.'),('Tokenlı oturum','Trusted token + stream token ile özel endpointler korunur.'),('Watch Live','Video, audio ve event pipeline aynı gerçek oturumu besler.'),('Kalite raporu','Client RTT/frame/audio/WS sinyallerini /quality/report ile iletir.'),('Adaptif kalite','Server 1, 2–3, 4–5 client yüküne ve zayıf Wi‑Fi’ye göre profil seçer.')]),
('Akış 3 · Bildirim ve Ayar Döngüsü','Anne odaklı uyarılar server analizi ve client deneyimi arasında akar.',[
('Server algılama','Ağlama ve hareket eşikleri server ayarlarından beslenir.'),('Alert event','Cry/motion/system event WebSocket üzerinden client’a gelir.'),('Client Bildirim','Öncelikli uyarı kartları ve filtreler gösterilir.'),('Watch Geçmiş','Canlı izleme içi zaman çizgisi son olayları gösterir.'),('Cooldown','Tekrarlı bildirimler cooldown ile sakinleştirilir.'),('Dil / locale','Catalog tüm ana ekran metinlerini çok dilli yönetir.')])
]
for title, subtitle, nodes in flows:
    p = new_page(); d = ImageDraw.Draw(p)
    y = header(d, title, subtitle)
    positions = [(M, 260), (720, 260), (M, 540), (720, 540), (M, 820), (720, 820)]
    for i, (label, desc) in enumerate(nodes):
        x, yy = positions[i]
        round_rect(d, (x, yy, x+420, yy+170), 28, CARD, LINE)
        round_rect(d, (x+18, yy+18, x+66, yy+66), 18, [PINK, MINT, AMBER][i % 3])
        d.text((x+84, yy+18), label, font=F['h3'], fill=NAVY)
        text(d, (x+84, yy+58), desc, F['small'], SLATE, 300, 4)
    for yline in [345, 625, 905]:
        d.line((M+440, yline, 700, yline), fill=(180,184,196), width=4)
        d.polygon([(700,yline),(684,yline-10),(684,yline+10)], fill=(180,184,196))
    footer(d, page_no); add_page(p)

# Screen pages
screen_meta = [
('01_role_selection.png','01 · İlk Açılış / Rol Seçimi','Telefonun server/client rolü seçilir; LAN/Wi‑Fi kullanım notu görünür tutulur.','UC-01'),
('02_client_watch_empty.png','02 · Client İzle / Eşleşme Yok','Ebeveyn cihazı henüz oda seçilmediğinde bağlantı CTA’sı gösterir.','UC-02'),
('03_client_find_pair.png','03 · Client Bul / QR + IP','QR tarama ve manuel IP:port fallback’i aynı kart akışında sunulur.','UC-02'),
('04_client_notifications.png','04 · Client Bildirim','Ağlama, hareket ve sistem olayları anne için filtrelenebilir kartlar halinde görünür.','UC-04'),
('05_client_settings.png','05 · Client Ayarlar','Client tarafında dil, bildirim ve cihaz uyanık kalma tercihleri bulunur.','UC-05'),
('06_client_watch_paired.png','06 · Client İzle / Eşleşmiş','Bebek odası kartı, canlı preview ve son durum özetleri ana ekrana gelir.','UC-04'),
('07_client_qr_scanner.png','07 · QR Scanner','Native kamera alanı ve manuel QR metni fallback yüzeyi. Rapor için kamera preview mock alanı kullanıldı.','UC-02'),
('08_watch_live.png','08 · Canlı İzleme','Video paneli, ses/hareket/gecikme metrikleri ve izleme aksiyonları.','UC-04'),
('09_watch_history.png','09 · Watch Uyarı Geçmişi','Canlı izleme içinde ağlama/hareket/sistem zaman çizgisi.','UC-04'),
('10_watch_settings.png','10 · Watch Ayarları','Otomatik kalite, cooldown ve algılama eşiklerini izleme bağlamında gösterir.','UC-04'),
('11_server_stream.png','11 · Server Yayın','Bebek odası cihazı medya runtime, izleyici sayısı ve algılama durumunu gösterir.','UC-03'),
('12_server_qr_ip.png','12 · Server QR/IP','QR/IP bağlantı bileti ebeveyn cihazı eşleşmesi için okunabilir boyutta sunulur.','UC-03'),
('13_server_services.png','13 · Server Servis','Kamera, mikrofon, WebSocket ve bağlı client sayıları operasyonel olarak izlenir.','UC-03'),
('14_server_settings.png','14 · Server Ayarlar','Ağlama/hareket eşiği, cooldown ve süre ayarları server tarafında yönetilir.','UC-03'),
]
for fname, title, desc, uc in screen_meta:
    p = new_page(); d = ImageDraw.Draw(p)
    y = header(d, title, desc)
    round_rect(d, (M, y, W-M, H-120), 40, (242,241,246), LINE)
    paste_screen(p, SCREENS / fname, (M+34, y+34, W-M-34, H-154))
    round_rect(d, (M, H-104, W-M, H-64), 20, (255,245,248))
    d.text((M+22, H-95), f'İlgili use-case: {uc} · Kaynak: LG G6 Android native screenshot', font=F['tiny'], fill=SLATE)
    footer(d, page_no); add_page(p)

# Notes
p = new_page(); d = ImageDraw.Draw(p)
y = header(d, 'Üretim Notları ve Kapsam Dışı', 'PDF’in nasıl üretildiği ve hangi sınırlamaları olduğu.')
notes = [
('Kaynak ekranlar','Ekran görüntüleri LG H870 Android cihazda Flutter debug build çalıştırılarak alındı. Her sayfa uygulamadaki gerçek widget ağaçlarını demo runtime state ile gösterir.'),
('QR scanner','Native kamera preview test ortamında bağımsız capture edilemediği için QR scanner sayfasında aynı layout’u temsil eden kamera alanı/mock ikon kullanıldı; alt manuel giriş alanı gerçek tasarımla aynı yapıyı taşır.'),
('Debug chrome','Ekranlarda Android status/navigation bar ve debug cihaz görünümü korunmuştur; bu, “bire bir cihaz ekranı” amacıyla bilinçli bırakıldı.'),
('Yakalanan iyileştirme','Watch canlı metric kartında LG font ölçeğinde görülen 2px overflow düzeltildi ve screenshotlar yeniden alındı.'),
('Kapsam dışı','Gerçek kamera görüntüsü, gerçek ağ/video stream içeriği, fiziksel QR scan senaryosu ve mağaza görselleri bu PDF’in kapsamı dışında tutuldu.'),
]
for i, (title, body) in enumerate(notes):
    yy = y + i * 210
    round_rect(d, (M, yy, W-M, yy+170), 28, CARD, LINE)
    d.text((M+26, yy+22), title, font=F['h3'], fill=NAVY)
    text(d, (M+26, yy+64), body, F['small'], SLATE, W-2*M-52, 5)
footer(d, page_no); add_page(p)

pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=150.0)
print(OUT)
print('pages', len(pages))
print('bytes', OUT.stat().st_size)
