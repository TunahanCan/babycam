# iOS Launch Image Asset Set

This directory is the Xcode asset catalog entry for the native iOS launch image. It is shown before Flutter renders the first frame.

Files:

- `Contents.json`
- `LaunchImage.png`
- `LaunchImage@2x.png`
- `LaunchImage@3x.png`

Rules:

- Keep this asset static and lightweight.
- Do not place pairing state, QR codes, connection status, localization-dependent text, or role-specific UI here.
- Do not use it as an onboarding surface.
- Keep filenames in sync with `Contents.json`.
- Verify changes with an iOS build on macOS or CI.

Replacement flow:

1. Export the same artwork at 1x, 2x, and 3x.
2. Replace the three PNG files.
3. Keep names unchanged, or update `Contents.json`.
4. Open `ios/Runner.xcworkspace` in Xcode if visual asset inspection is needed.
5. Build on macOS and check the launch transition into Flutter UI.

Flutter runtime screens such as role selection, Server QR/IP, Client pairing, and alert history belong in Dart UI, not in this native launch asset.
