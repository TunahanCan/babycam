from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
WORDMARK = ROOT / "assets/branding/mimicam_wordmark.png"
BEAR_ICON = ROOT / "assets/branding/mimicam_bear_icon.png"

IOS_ICON_DIR = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES_DIR = ROOT / "android/app/src/main/res"

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_SIZES = {
    "mipmap-mdpi": (48, 108),
    "mipmap-hdpi": (72, 162),
    "mipmap-xhdpi": (96, 216),
    "mipmap-xxhdpi": (144, 324),
    "mipmap-xxxhdpi": (192, 432),
}


def _extract_bear(wordmark: Image.Image) -> Image.Image:
    if wordmark.size != (760, 139):
        raise ValueError(f"Unexpected wordmark size: {wordmark.size}")

    # The bear replaces the `a` glyph between the C and final m.
    bear = wordmark.crop((500, 0, 624, 139))
    bounds = bear.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Bear glyph was not found in the wordmark")
    return bear.crop(bounds)


def _brand_background(size: int) -> Image.Image:
    coral = Image.new("RGB", (size, size), "#FFD9D6")
    mint = Image.new("RGB", (size, size), "#D7F6EB")
    cream = Image.new("RGB", (size, size), "#FFF9F2")

    gradient = Image.linear_gradient("L").resize((size, size))
    gradient = gradient.rotate(-38, resample=Image.Resampling.BICUBIC)
    color = Image.composite(mint, coral, gradient)
    return Image.blend(color, cream, 0.46)


def _place_bear(canvas: Image.Image, bear: Image.Image, scale: float) -> None:
    target = int(canvas.width * scale)
    resize_scale = target / max(bear.size)
    placed = bear.resize(
        (
            round(bear.width * resize_scale),
            round(bear.height * resize_scale),
        ),
        Image.Resampling.LANCZOS,
    )
    x = (canvas.width - placed.width) // 2
    y = (canvas.height - placed.height) // 2

    shadow_alpha = placed.getchannel("A").filter(
        ImageFilter.GaussianBlur(max(2, canvas.width // 96))
    )
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_patch = Image.new("RGBA", placed.size, (91, 55, 34, 55))
    shadow_patch.putalpha(shadow_alpha.point(lambda value: value * 55 // 255))
    shadow.alpha_composite(shadow_patch, (x, y + max(1, canvas.width // 80)))

    canvas.alpha_composite(shadow)
    canvas.alpha_composite(placed, (x, y))


def _make_master(bear: Image.Image) -> Image.Image:
    master = _brand_background(1024).convert("RGBA")
    _place_bear(master, bear, 0.68)
    return master.convert("RGB")


def _make_foreground(bear: Image.Image, size: int) -> Image.Image:
    foreground = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    _place_bear(foreground, bear, 0.58)
    return foreground


def main() -> None:
    wordmark = Image.open(WORDMARK).convert("RGBA")
    bear = _extract_bear(wordmark)
    master = _make_master(bear)
    master.save(BEAR_ICON, optimize=True)

    for filename, size in IOS_SIZES.items():
        icon = master.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(IOS_ICON_DIR / filename, optimize=True)

    for folder, (legacy_size, foreground_size) in ANDROID_SIZES.items():
        destination = ANDROID_RES_DIR / folder
        legacy = master.resize(
            (legacy_size, legacy_size), Image.Resampling.LANCZOS
        )
        legacy.save(destination / "ic_launcher.png", optimize=True)
        _make_foreground(bear, foreground_size).save(
            destination / "ic_launcher_foreground.png", optimize=True
        )

    print(BEAR_ICON)
    print("Updated Android and iOS launcher icon sets")


if __name__ == "__main__":
    main()
