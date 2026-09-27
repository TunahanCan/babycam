# Website screenshots

These images are WebP encodings of the committed Flutter acceptance captures in
[`docs/reports/app_acceptance_2026-09-27`](../../../docs/reports/app_acceptance_2026-09-27/index.html).
They use the actual app widgets, Turkish labels and demonstration data. The camera
preview is a generated local test stream showing the app icon; it is not footage
of a child. Notification events are sample data, not detection-accuracy claims.

Each image retains the original **390 × 844** canvas. No content is repainted,
cropped, resized or composited. The website should label the screenshots as demo
screens and keep the sample-stream context visible near the gallery.

Regenerate from the repository root using Node.js and `ffmpeg` with `libwebp`:

```sh
node website/scripts/refresh-screens.mjs
```

The script checks source hashes against the committed report, encodes WebP with
the text preset at quality 90, verifies output dimensions and a 100 KB per-image
budget, and writes source/output hashes and byte sizes to `manifest.json`.

| Website file | Source capture |
| --- | --- |
| `role-selection.webp` | `01_role.png` |
| `client-live.webp` | `08_watch_live.png` |
| `room-controls.webp` | `11_room_controls_bottom.png` |
| `connection-recovery.webp` | `12_watch_connection_error.png` |
| `server-preview.webp` | `14_server_preview_on.png` |
| `notifications.webp` | `09_watch_history.png` |
