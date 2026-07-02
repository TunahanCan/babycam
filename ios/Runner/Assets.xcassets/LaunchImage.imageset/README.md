# iOS Launch Image Asset Set

This directory is the Xcode asset catalog entry for the native iOS launch image.
It is shown before Flutter renders the first frame.

## Files

- `Contents.json`
- `LaunchImage.png`
- `LaunchImage@2x.png`
- `LaunchImage@3x.png`

## Rules

- Keep this asset static and lightweight.
- Do not put QR codes here.
- Do not put pairing state here.
- Do not put server/client role UI here.
- Do not put localization-dependent text here.
- Do not use it as onboarding or a paywall surface.
- Keep filenames in sync with `Contents.json`.

## Replacement Flow

1. Export the same artwork at 1x, 2x, and 3x.
2. Replace the three PNG files.
3. Keep names unchanged, or update `Contents.json`.
4. Open `ios/Runner.xcworkspace` in Xcode if visual inspection is needed.
5. Build on macOS or CI.
6. Check the launch transition into Flutter UI.

Runtime screens such as role selection, Server QR/IP, Client pairing, live
watch, paid unlock, and alert history belong in Dart UI, not in this native
launch asset.
