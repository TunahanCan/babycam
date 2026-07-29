from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / os.environ.get('REPORT_CAPTURE_OUTPUT', 'build/screen_report/i18n')
LOG = ROOT / 'build/screen_report/capture_flutter_run.log'
ADB = Path(os.environ.get('REPORT_ADB', '/home/tnnhn/Android/Sdk/platform-tools/adb'))
DEVICE = os.environ.get('REPORT_DEVICE', 'LGH8708da5c4b')
TARGET = 'tool/screen_report_device_app.dart'
SEQUENCE_MODE = os.environ.get('REPORT_SEQUENCE_MODE', '1') != '0'
RESUME_CAPTURE = os.environ.get('REPORT_CAPTURE_RESUME', '0') == '1'

LOCALES = ('tr', 'zh', 'en', 'es', 'fr', 'de', 'hi', 'ar_SA', 'ar_QA')

CAPTURES = (
    ('role', '01_role_selection.png', 0, 0),
    ('client_unpaired', '02_client_watch_empty.png', 0, 0),
    ('client_unpaired', '03_client_find_pair.png', 1, 0),
    ('client_unpaired', '04_client_notifications.png', 2, 0),
    ('client_unpaired', '05_client_settings.png', 3, 0),
    ('client_paired', '06_client_watch_paired.png', 0, 0),
    ('qr_scanner', '07_client_qr_scanner.png', 0, 0),
    ('watch', '08_watch_live.png', 0, 0),
    ('watch', '09_watch_history.png', 1, 0),
    ('watch', '10_watch_settings.png', 2, 0),
    ('watch_controls', '11_watch_room_controls.png', 0, 3),
    ('watch_error', '12_watch_connection_error.png', 0, 0),
    ('server', '13_server_preview_off.png', 0, 0),
    ('server_preview_on', '14_server_preview_on.png', 0, 0),
    ('server', '15_server_qr_ip.png', 1, 0),
    ('server', '16_server_services.png', 2, 0),
    ('server', '17_server_settings.png', 3, 0),
)


def locale_parts(locale: str) -> tuple[str, str]:
    parts = locale.split('_', maxsplit=1)
    language_code = parts[0]
    country_code = parts[1] if len(parts) == 2 else ''
    # Keep the historical `en` report directory stable while rendering the
    # app's canonical American English locale explicitly.
    if language_code == 'en' and not country_code:
        country_code = 'US'
    return language_code, country_code


def run(command: list[str], *, cwd: Path = ROOT, stdout=None) -> None:
    subprocess.run(command, cwd=cwd, check=True, stdout=stdout)


def launch(scene: str, locale: str, tab: int) -> None:
    run([str(ADB), '-s', DEVICE, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'])
    run([str(ADB), '-s', DEVICE, 'shell', 'wm', 'dismiss-keyguard'])
    language_code, country_code = locale_parts(locale)
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
        '--dart-define',
        f'REPORT_TAB={tab}',
        '--no-pub',
        '--no-resident',
    ]
    build_mode = os.environ.get('REPORT_BUILD_MODE')
    if build_mode:
        command.insert(2, f'--{build_mode}')
    print(f'launch {locale}/{scene}/tab-{tab}', flush=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open('a', encoding='utf-8') as log:
        log.write(f'\n=== {locale}/{scene}/tab-{tab} ===\n')
        subprocess.run(command, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(float(os.environ.get('REPORT_CAPTURE_WAIT_SECONDS', '25')))


def launch_sequence(locale: str) -> None:
    run([str(ADB), '-s', DEVICE, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'])
    run([str(ADB), '-s', DEVICE, 'shell', 'wm', 'dismiss-keyguard'])
    run([str(ADB), '-s', DEVICE, 'logcat', '-c'])
    language_code, country_code = locale_parts(locale)
    command = [
        'flutter',
        'run',
        '-d',
        DEVICE,
        '-t',
        TARGET,
        '--dart-define',
        'REPORT_SEQUENCE=true',
        '--dart-define',
        f'REPORT_LOCALE={language_code}',
        '--dart-define',
        f'REPORT_LOCALE_COUNTRY={country_code}',
        '--no-pub',
        '--no-resident',
    ]
    build_mode = os.environ.get('REPORT_BUILD_MODE')
    if build_mode:
        command.insert(2, f'--{build_mode}')
    print(f'launch sequence {locale}', flush=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open('a', encoding='utf-8') as log:
        log.write(f'\n=== sequence/{locale} ===\n')
        subprocess.run(command, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    wait_for_sequence_scene(0)


def wait_for_sequence_scene(index: int) -> None:
    marker = f'MIUCAM_REPORT_READY index={index} '
    timeout = float(os.environ.get('REPORT_SEQUENCE_READY_TIMEOUT_SECONDS', '45'))
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = subprocess.run(
            [str(ADB), '-s', DEVICE, 'logcat', '-d'],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
            errors='replace',
        )
        if marker in result.stdout:
            time.sleep(
                float(os.environ.get('REPORT_SEQUENCE_SCENE_WAIT_SECONDS', '3'))
            )
            return
        time.sleep(.5)
    raise TimeoutError(f'report scene did not become ready: index={index}')


def advance_sequence(index: int) -> None:
    run([
        str(ADB), '-s', DEVICE, 'shell', 'input', 'swipe',
        '1240', '1420', '180', '1420', '360',
    ])
    wait_for_sequence_scene(index)


def scroll_down(times: int) -> None:
    for _ in range(times):
        run([
            str(ADB), '-s', DEVICE, 'shell', 'input', 'swipe',
            '720', '1900', '720', '560', '420',
        ])
        time.sleep(.7)


def is_probably_splash(path: Path) -> bool:
    image = Image.open(path).convert('RGB')
    width, height = image.size
    crop = image.crop((0, int(height * 0.08), width, int(height * 0.90)))
    pixels = list(crop.resize((80, 160), Image.Resampling.BILINEAR).get_flattened_data())
    black = sum(1 for r, g, b in pixels if r + g + b < 25) / len(pixels)
    if black > 0.90:
        return True
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
    try:
        display_path = path.relative_to(ROOT)
    except ValueError:
        display_path = path
    print(display_path, flush=True)


def write_manifest(locales: tuple[str, ...], started_at: datetime) -> None:
    files = {}
    for locale in locales:
        for _, filename, _, _ in CAPTURES:
            path = OUT / locale / filename
            if not path.exists():
                raise FileNotFoundError(path)
            with path.open('rb') as source:
                digest = hashlib.sha256(source.read()).hexdigest()
            image = Image.open(path)
            files[str(path.relative_to(OUT))] = {
                'bytes': path.stat().st_size,
                'sha256': digest,
                'width': image.width,
                'height': image.height,
            }
    manifest = {
        'schemaVersion': 1,
        'capturedAt': datetime.now(timezone.utc).isoformat(),
        'startedAt': started_at.isoformat(),
        'device': DEVICE,
        'deviceModel': read_device_model(),
        'locales': list(locales),
        'screensPerLocale': len(CAPTURES),
        'expectedFileCount': len(locales) * len(CAPTURES),
        'files': files,
    }
    (OUT / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding='utf-8',
    )


def read_device_model() -> str:
    result = subprocess.run(
        [str(ADB), '-s', DEVICE, 'shell', 'getprop', 'ro.product.model'],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        errors='replace',
    )
    return result.stdout.strip() or 'Android device'


def main() -> None:
    if not ADB.exists():
        raise SystemExit(f'adb not found: {ADB}')
    if RESUME_CAPTURE:
        raise SystemExit(
            'REPORT_CAPTURE_RESUME is disabled: a resumed run cannot yet prove '
            'that existing screenshots belong to the same capture session.'
        )
    locale_filter = os.environ.get('REPORT_CAPTURE_LOCALES')
    scene_filter = os.environ.get('REPORT_CAPTURE_SCENES')
    file_filter = os.environ.get('REPORT_CAPTURE_FILES')
    locales = tuple(locale_filter.split(',')) if locale_filter else LOCALES
    scenes = set(scene_filter.split(',')) if scene_filter else None
    files = set(file_filter.split(',')) if file_filter else None
    full_capture = locales == LOCALES and scenes is None and files is None
    started_at = datetime.now(timezone.utc)
    if full_capture and OUT.exists() and not RESUME_CAPTURE:
        shutil.rmtree(OUT)
    run([str(ADB), '-s', DEVICE, 'get-state'])
    for locale in locales:
        locale_dir = OUT / locale
        if SEQUENCE_MODE:
            launch_sequence(locale)
            for index, (scene, filename, _, scrolls) in enumerate(CAPTURES):
                if index:
                    advance_sequence(index)
                if scenes is not None and scene not in scenes:
                    continue
                if files is not None and filename not in files:
                    continue
                if scrolls:
                    scroll_down(scrolls)
                screenshot(locale_dir / filename)
        else:
            for scene, filename, tab, scrolls in CAPTURES:
                if scenes is not None and scene not in scenes:
                    continue
                if files is not None and filename not in files:
                    continue
                launch(scene, locale, tab)
                if scrolls:
                    scroll_down(scrolls)
                screenshot(locale_dir / filename)
    if full_capture:
        write_manifest(locales, started_at)
        print(OUT / 'manifest.json', flush=True)


if __name__ == '__main__':
    main()
