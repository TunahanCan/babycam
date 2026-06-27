from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCREENS = ROOT / 'build/screen_report/i18n'
OUT = ROOT / 'docs/reports/mimicam_cok_dilli_ekranlar_usecase_raporu.pdf'
OUT.parent.mkdir(parents=True, exist_ok=True)

W, H, M = 1240, 1754, 72
BG = (247, 250, 255)
INK = (7, 20, 47)
NAVY = (18, 57, 120)
SLATE = (92, 104, 128)
CYAN = (99, 247, 247)
BLUE = (78, 133, 255)
VIOLET = (184, 108, 255)
CARD = (255, 255, 255)
LINE = (211, 226, 240)
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
BOLD = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'

LOCALES = [
    ('tr', 'Türkçe', 'Türkçe ekran görüntüleri'),
    ('zh', '中文', '中文界面截图'),
    ('en', 'English', 'English screenshots'),
    ('es', 'Español', 'Capturas en español'),
    ('fr', 'Français', 'Captures en français'),
    ('de', 'Deutsch', 'Deutsche Screenshots'),
    ('hi', 'Hintçe', 'Hintçe ekran görüntüleri'),
    ('ar_SA', 'Arapça - Suudi Arabistan', 'Arapça (Suudi Arabistan) ekran görüntüleri'),
    ('ar_QA', 'Arapça - Katar', 'Arapça (Katar) ekran görüntüleri'),
]

SCREEN_META = [
    ('01_role_selection.png', '01', 'Rol seçimi / Role selection', 'UC-01'),
    ('02_client_watch_empty.png', '02', 'Client izleme boş durum', 'UC-02'),
    ('03_client_find_pair.png', '03', 'QR/IP ile eşleşme', 'UC-02'),
    ('04_client_notifications.png', '04', 'Bildirimler', 'UC-04'),
    ('05_client_settings.png', '05', 'Client ayarları', 'UC-05'),
    ('06_client_watch_paired.png', '06', 'Eşleşmiş client ana ekranı', 'UC-04'),
    ('07_client_qr_scanner.png', '07', 'QR scanner', 'UC-02'),
    ('08_watch_live.png', '08', 'Canlı izleme', 'UC-04'),
    ('09_watch_history.png', '09', 'Uyarı geçmişi', 'UC-04'),
    ('10_watch_settings.png', '10', 'İzleme ayarları', 'UC-04'),
    ('11_server_stream.png', '11', 'Server yayın', 'UC-03'),
    ('12_server_qr_ip.png', '12', 'Server QR/IP', 'UC-03'),
    ('13_server_services.png', '13', 'Server servisleri', 'UC-03'),
    ('14_server_settings.png', '14', 'Server ayarları', 'UC-03'),
]

USE_CASES = [
    (
        'UC-01 İlk rol seçimi',
        'Kullanıcı cihazın görevini seçer. Bebek odası cihazı server olur; ebeveyn cihazı client olur.',
        'Screens 01',
    ),
    (
        'UC-02 Eşleşme',
        'Ebeveyn cihazı QR tarar veya IP:port girer. Server pairing bileti trusted session oluşturur.',
        'Screens 02, 03, 07, 12',
    ),
    (
        'UC-03 Server operasyonu',
        'Bebek odası telefonu kamera, mikrofon, QR/IP bileti, servis durumu ve algılama eşiklerini yönetir.',
        'Screens 11, 12, 13, 14',
    ),
    (
        'UC-04 Canlı izleme ve uyarılar',
        'Ebeveyn canlı yayına girer, kalite/metrikleri izler, uyarı geçmişini kontrol eder.',
        'Screens 04, 06, 08, 09, 10',
    ),
    (
        'UC-05 Çok dilli kullanım',
        'Aynı ana ekranlar Türkçe, Çince, İngilizce, İspanyolca, Fransızca, Almanca, Hintçe ve Arapça locale ile doğrulanır.',
        'All localized pages',
    ),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(BOLD if bold else FONT, size)


F = {
    'cover': font(64, True),
    'h1': font(38, True),
    'h2': font(28, True),
    'h3': font(22, True),
    'body': font(19),
    'bodyb': font(19, True),
    'small': font(15),
    'smallb': font(15, True),
    'tiny': font(12),
}


def page(color=BG) -> Image.Image:
    return Image.new('RGB', (W, H), color)


def wrap(draw: ImageDraw.ImageDraw, text: str, font_: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    current = ''
    for token in text.split():
        candidate = f'{current} {token}'.strip()
        if not current or draw.textlength(candidate, font=font_) <= width:
            current = candidate
        else:
            lines.append(current)
            current = token
    if current:
        lines.append(current)
    return lines


def draw_text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], value: str, font_, fill=INK, width=None, gap=8) -> int:
    x, y = xy
    lines = [value] if width is None else wrap(draw, value, font_, width)
    for line in lines:
        draw.text((x, y), line, font=font_, fill=fill)
        y += font_.size + gap
    return y


def rounded(draw, box, radius, fill, outline=None, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def header(draw, title: str, subtitle: str | None = None) -> int:
    draw.text((M, 48), 'MimiCam', font=F['smallb'], fill=BLUE)
    draw.text((M, 84), title, font=F['h1'], fill=INK)
    y = 140
    if subtitle:
        y = draw_text(draw, (M, y), subtitle, F['body'], SLATE, W - 2 * M) + 8
    draw.line((M, y, W - M, y), fill=LINE, width=2)
    return y + 32


def footer(draw, page_no: int):
    draw.text((M, H - 48), 'MimiCam çok dilli ekran ve use-case raporu', font=F['tiny'], fill=SLATE)
    draw.text((W - M - 42, H - 48), str(page_no), font=F['tiny'], fill=SLATE)


def paste_screen(target: Image.Image, path: Path, box: tuple[int, int, int, int]):
    x1, y1, x2, y2 = box
    image = Image.open(path).convert('RGB')
    image.thumbnail((x2 - x1, y2 - y1), Image.Resampling.LANCZOS)
    x = x1 + (x2 - x1 - image.width) // 2
    y = y1 + (y2 - y1 - image.height) // 2
    target.paste(image, (x, y))


pages: list[Image.Image] = []


def add(image: Image.Image):
    pages.append(image)


cover = page(INK)
draw = ImageDraw.Draw(cover)
icon_path = ROOT / 'assets/branding/mimicam_launcher_icon.png'
if icon_path.exists():
    icon = Image.open(icon_path).convert('RGBA')
    icon.thumbnail((230, 230), Image.Resampling.LANCZOS)
    cover.paste(icon, (M, 140), icon)
draw.text((M, 430), 'MimiCam', font=F['cover'], fill=(255, 255, 255))
draw_text(
    draw,
    (M, 520),
    'Çok Dilli Ekran Görüntüleri ve Use-Case Raporu',
    F['h1'],
    (245, 250, 255),
    W - 2 * M,
)
draw_text(
    draw,
    (M, 650),
    'Türkçe, Çince, İngilizce, İspanyolca, Fransızca, Almanca, Hintçe ve Arapça (Suudi Arabistan/Katar) locale ile LG H870 Android cihazından alınan ana ekran görüntüleri ve ürün use-case özeti.',
    F['body'],
    (210, 226, 242),
    W - 2 * M,
)
y = 820
for label, color in [('9 locale', CYAN), ('126 ekran', BLUE), ('5 use-case', VIOLET), ('LG H870', CYAN)]:
    width = int(draw.textlength(label, font=F['smallb'])) + 44
    rounded(draw, (M, y, M + width, y + 48), 24, color)
    draw.text((M + 22, y + 12), label, font=F['smallb'], fill=INK)
    y += 68
footer(draw, 1)
add(cover)

p = page()
draw = ImageDraw.Draw(p)
y = header(draw, 'Use-Case Özeti', 'Rapordaki ekranların kapsadığı ana kullanıcı senaryoları.')
for index, (title, body, screens) in enumerate(USE_CASES):
    yy = y + index * 255
    rounded(draw, (M, yy, W - M, yy + 216), 28, CARD, LINE)
    rounded(draw, (M + 22, yy + 22, M + 76, yy + 76), 18, [CYAN, BLUE, VIOLET][index % 3])
    draw.text((M + 94, yy + 24), title, font=F['h3'], fill=INK)
    draw_text(draw, (M + 94, yy + 64), body, F['small'], SLATE, W - 2 * M - 116, 4)
    draw.text((M + 94, yy + 154), screens, font=F['smallb'], fill=BLUE)
footer(draw, len(pages) + 1)
add(p)

for locale, language, subtitle in LOCALES:
    p = page()
    draw = ImageDraw.Draw(p)
    y = header(draw, language, subtitle)
    for idx, (_, number, title, uc) in enumerate(SCREEN_META):
        yy = y + idx * 93
        rounded(draw, (M, yy, W - M, yy + 74), 20, CARD, LINE)
        rounded(draw, (M + 18, yy + 15, M + 74, yy + 59), 16, [CYAN, BLUE, VIOLET][idx % 3])
        draw.text((M + 34, yy + 27), number, font=F['tiny'], fill=INK)
        draw.text((M + 92, yy + 13), title, font=F['smallb'], fill=INK)
        draw.text((M + 92, yy + 42), uc, font=F['tiny'], fill=SLATE)
    footer(draw, len(pages) + 1)
    add(p)

    for filename, number, title, uc in SCREEN_META:
        path = SCREENS / locale / filename
        if not path.exists():
            raise FileNotFoundError(path)
        p = page()
        draw = ImageDraw.Draw(p)
        y = header(draw, f'{language} · {number}', f'{title} · {uc}')
        rounded(draw, (M, y, W - M, H - 112), 36, (232, 242, 252), LINE)
        paste_screen(p, path, (M + 34, y + 32, W - M - 34, H - 150))
        footer(draw, len(pages) + 1)
        add(p)

pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=150.0)
print(OUT)
print('pages', len(pages))
print('bytes', OUT.stat().st_size)
