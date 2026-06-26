from __future__ import annotations

import subprocess
import time
import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/screen_report/i18n'
LOG = ROOT / 'build/screen_report/capture_flutter_run.log'
ADB = Path('/home/tnnhn/Android/Sdk/platform-tools/adb')
DEVICE = 'LGH8708da5c4b'
TARGET = 'tool/screen_report_device_app.dart'

LOCALES = ('tr', 'zh', 'en', 'es', 'fr', 'de', 'ar_SA', 'ar_QA')
NAV_Y = 2600
CLIENT_NAV = (180, 540, 900, 1260)
WATCH_NAV = (240, 720, 1200)

CAPTURES = (
    ('role', (('01_role_selection.png', None),)),
    (
        'client_unpaired',
        (
            ('02_client_watch_empty.png', None),
            ('03_client_find_pair.png', CLIENT_NAV[1]),
            ('04_client_notifications.png', CLIENT_NAV[2]),
            ('05_client_settings.png', CLIENT_NAV[3]),
        ),
    ),
    ('client_paired', (('06_client_watch_paired.png', None),)),
    ('qr_scanner', (('07_client_qr_scanner.png', None),)),
    (
        'watch',
        (
            ('08_watch_live.png', None),
            ('09_watch_history.png', WATCH_NAV[1]),
            ('10_watch_settings.png', WATCH_NAV[2]),
        ),
    ),
    (
        'server',
        (
            ('11_server_stream.png', None),
            ('12_server_qr_ip.png', CLIENT_NAV[1]),
            ('13_server_services.png', CLIENT_NAV[2]),
            ('14_server_settings.png', CLIENT_NAV[3]),
        ),
    ),
)


def run(command: list[str], *, cwd: Path = ROOT, stdout=None) -> None:
    subprocess.run(command, cwd=cwd, check=True, stdout=stdout)


def launch(scene: str, locale: str) -> None:
    parts = locale.split('_', maxsplit=1)
    language_code = parts[0]
    country_code = parts[1] if len(parts) == 2 else ''
    command = [
        'flutter',
        'run',
        '-d',
        DEVICE,
        '-t',
        TARGET,
        '--dart-define',
        f'REPORT_SCENE={scene}',
        '--dart-define',
        f'REPORT_LOCALE={language_code}',
        '--dart-define',
        f'REPORT_LOCALE_COUNTRY={country_code}',
        '--no-pub',
        '--no-resident',
    ]
    print(f'launch {locale}/{scene}', flush=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open('a', encoding='utf-8') as log:
        log.write(f'\n=== {locale}/{scene} ===\n')
        subprocess.run(command, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(12)


def tap(x: int) -> None:
    run([str(ADB), '-s', DEVICE, 'shell', 'input', 'tap', str(x), str(NAV_Y)])
    time.sleep(1.6)


def is_probably_splash(path: Path) -> bool:
    image = Image.open(path).convert('RGB')
    width, height = image.size
    crop = image.crop((0, int(height * 0.08), width, int(height * 0.90)))
    pixels = list(crop.resize((80, 160), Image.Resampling.BILINEAR).get_flattened_data())
    dark = sum(1 for r, g, b in pixels if r + g + b < 115) / len(pixels)
    light = sum(1 for r, g, b in pixels if r > 210 and g > 210 and b > 210) / len(pixels)
    saturated_cyan = sum(1 for r, g, b in pixels if g > 150 and b > 150 and r < 140) / len(pixels)
    return dark > 0.78 and light < 0.018 and saturated_cyan < 0.11


def screenshot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(5):
        with path.open('wb') as output:
            run([str(ADB), '-s', DEVICE, 'exec-out', 'screencap', '-p'], stdout=output)
        if not is_probably_splash(path):
            break
        if attempt == 4:
            raise RuntimeError(f'app stayed on splash while capturing {path}')
        time.sleep(3)
    print(path.relative_to(ROOT), flush=True)


def main() -> None:
    if not ADB.exists():
        raise SystemExit(f'adb not found: {ADB}')
    locale_filter = os.environ.get('REPORT_CAPTURE_LOCALES')
    scene_filter = os.environ.get('REPORT_CAPTURE_SCENES')
    locales = tuple(locale_filter.split(',')) if locale_filter else LOCALES
    scenes = set(scene_filter.split(',')) if scene_filter else None
    for locale in locales:
        locale_dir = OUT / locale
        for scene, captures in CAPTURES:
            if scenes is not None and scene not in scenes:
                continue
            launch(scene, locale)
            for filename, tap_x in captures:
                if tap_x is not None:
                    tap(tap_x)
                screenshot(locale_dir / filename)


if __name__ == '__main__':
    main()
