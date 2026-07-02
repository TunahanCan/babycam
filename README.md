# MimiCam

MimiCam is a local-first Flutter baby monitor. One phone runs in **Server**
mode in the baby room; another phone runs in **Client** mode for the parent.
The app is designed around local Wi-Fi, explicit pairing, real audio/video
delivery, and runtime diagnostics that can prove whether media actually moves.

The current product intentionally does not include cloud relay, accounts,
internet-wide access, Apple Watch, WebRTC, H.264, Opus, HTTPS/WSS, or mobile
data relay.

## Current Status

| Area | Implementation |
| --- | --- |
| Roles | One active role at a time: Server or Client |
| Pairing | QR payload plus manual `IP:port` fallback |
| Transport | Local HTTP and WebSocket |
| Video | MJPEG over `GET /video` |
| Audio | PCM16LE/WAV over `GET /audio` |
| Events | JSON alert events over `GET /ws/events` WebSocket |
| Auth | Trusted Bearer token plus short-lived stream token |
| Monitoring | Client live watch with audio, alerts, night clock, and full screen controls |
| Publishing | Server live preview with full screen controls |
| Monetization | 2 hours free live broadcast/watch time, then one-time 300 TL unlock |
| Diagnostics | Browser `/test` panel and JSON `/test/*` endpoints |
| Battery | Server/client battery snapshots in status and quality reporting |
| Feature controls | Comfort audio, night light, and talk control endpoints exist |
| Out of scope | Cloud relay, accounts, push backend, Apple Watch, direct Bluetooth media |

## Product Rules

- Media is local network only.
- Bluetooth must not be treated as a video/audio transport.
- Stream tokens are for media endpoints only.
- Control endpoints require trusted Bearer auth.
- Slow video/audio clients skip data instead of building unbounded queues.
- Audio and alerts have priority over video quality.
- Runtime docs must describe shipped code, not planned marketing copy.

## Quick Start

```bash
flutter pub get
flutter run
```

Common verification gate:

```bash
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

Android debug APK output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Linux can run analysis, tests, and Android debug builds. iOS builds require a
Mac or a macOS CI runner.

## User Flow

```text
Open MimiCam
  -> choose Server or Client
  -> Server shows QR/IP pairing details
  -> Client scans QR or enters IP:port manually
  -> Client confirms pairing with one-time nonce
  -> Server issues trusted token
  -> Client stores token securely
  -> Client starts live watch
  -> Server issues short-lived stream token
  -> Client opens video/audio streams and event socket
  -> Client posts quality reports
  -> Server adapts media quality
```

Changing role disposes the active runtime graph and mounts the new role. The app
does not run Server and Client graphs at the same time.

## Pricing Model

MimiCam now has a local one-time unlock model:

- First 2 hours of live broadcast/watch time are free.
- After the free limit is exhausted, live streaming is locked.
- Unlock is a one-time purchase shown as `300 TL`.
- Store product id: `mimicam_lifetime_unlock_try_300`.
- The unlock is stored locally on the device.

The code uses `in_app_purchase` and expects the App Store / Play Console product
to be configured as a non-consumable item with the product id above. The code
cannot create the store product or price by itself.

Enforcement happens in runtime code, not only in UI:

- Client `startWatching` refuses to start after the free limit.
- Server `/session/start` returns `402 Payment Required` without issuing a
  stream token after the free limit.
- Server status/capabilities expose free limit, unlock price, and product id.

## Server Role

Server responsibilities:

- Bind the local HTTP server.
- Generate QR payloads and public pairing status.
- Validate pairing nonce and issue trusted client tokens.
- Start camera, microphone, analysis, wakelock, and foreground service when
  media is needed.
- Encode camera frames to JPEG and broadcast them as MJPEG.
- Capture PCM audio and broadcast it as a WAV stream.
- Run motion/audio analysis and emit alerts.
- Track active watch clients and attached stream sockets.
- Apply adaptive media quality based on client health reports.
- Expose diagnostics under `/test`.
- Enforce the free broadcast limit for incoming watch sessions.

Important files:

- `lib/services/mimicam_server.dart`
- `lib/features/server/server_runtime.dart`
- `lib/features/server/server_composition_root.dart`
- `lib/features/server/media/mjpeg_stream_service.dart`
- `lib/features/server/media/wav_audio_stream_service.dart`
- `lib/features/server/media/microphone_capture_service.dart`
- `lib/features/server/pairing/pairing_token_service.dart`
- `lib/services/server/active_client_registry.dart`
- `lib/services/server/media_quality_selector.dart`
- `lib/services/monetization/broadcast_access_service.dart`

## Client Role

Client responsibilities:

- Scan QR with `mobile_scanner`.
- Pair through `/pair/confirm`.
- Store trusted token in secure storage.
- Restore saved sessions on launch.
- Renew trusted tokens when needed.
- Start and stop live watch sessions.
- Read MJPEG video.
- Read WAV audio and write PCM to native playback.
- Listen to alert WebSocket events.
- Store in-app alert history.
- Show local notifications when permission is granted.
- Report network, stream, and battery health.
- Enforce the free watch limit before opening streams.

Important files:

- `lib/features/client/client_runtime.dart`
- `lib/features/client/client_composition_root.dart`
- `lib/features/client/media/watch_screen.dart`
- `lib/features/client/media/stream_session_controller.dart`
- `lib/features/client/media/client_media_stream_supervisor.dart`
- `lib/features/client/media/client_video_viewer.dart`
- `lib/features/client/media/client_live_audio_pipeline.dart`
- `lib/features/client/media/network_quality_monitor.dart`
- `lib/features/client/alerts/client_alert_listener.dart`
- `lib/features/client/pairing/pairing_session_store.dart`

## Pairing and Storage

The QR payload carries address, nonce, expiry, transport, and capability
metadata. It does not carry the trusted token.

Client storage split:

| Data | Storage |
| --- | --- |
| Trusted token | `flutter_secure_storage` |
| Pairing metadata | `SharedPreferences` |
| Child profiles | `SharedPreferences` plus secure per-child token keys |
| Client identity | Secure storage |
| Alert history | `SharedPreferences` |
| Broadcast unlock and free-time usage | `SharedPreferences` |

Legacy `pairing_session` records are migrated on load. Corrupt records are
cleared instead of crashing startup.

## Auth Model

Trusted token:

- Issued by `/pair/confirm`.
- Renewed by `/auth/renew`.
- Sent as `Authorization: Bearer <token>`.
- Stored on the server as a hash.
- Required for private state-changing endpoints.

Stream token:

- Issued by `/session/start`.
- Short lived.
- Accepted only by `/video` and `/audio`.
- Passed as `?streamToken=...`.
- Not accepted by status, quality, auth, comfort, night-light, or talk control
  routes.

The WebSocket event route accepts trusted auth through Bearer headers or the
`token` query parameter, matching the current client path.

## Media Lifecycle

```text
ClientRuntime.startWatching
  -> BroadcastAccessService.beginSession
  -> StreamSessionController.start
  -> POST /session/start
  -> MimiCamServer checks BroadcastAccessService
  -> ActiveClientRegistry creates active watch slot
  -> Server returns streamToken
  -> ClientMediaStreamSupervisor opens /video and /audio
```

Watch sessions are separate from transient media sockets:

- `/session/start` marks the active watch session.
- `/video` and `/audio` attach stream sockets.
- A media socket disconnect does not immediately delete the watch session.
- Reconnect can reuse the same valid stream token.
- `/session/stop`, token expiry, or explicit cleanup clears the active slot.

## Video

Video is MJPEG over HTTP.

- Server keeps the latest JPEG frame.
- Server broadcasts frames to attached MJPEG responses.
- There is no per-client camera encode.
- There is no per-client frame queue.
- Slow clients skip frames.
- If no frame exists, a zero-length multipart keepalive opens the response.
- Client parser ignores keepalive parts.
- Client validates host and port against the paired server.
- Client supports full screen and `cover` / `contain` fit modes.

Key tests:

- `test/features/server/mjpeg_stream_service_test.dart`
- `test/features/client/client_video_viewer_test.dart`
- `test/features/client/mjpeg_stream_parser_test.dart`
- `test/features/server/media_stream_end_to_end_test.dart`

## Audio

Audio is PCM16LE wrapped in a live WAV stream.

- Server writes a WAV header first.
- Server broadcasts PCM chunks to attached audio responses.
- Client parses WAV in Dart.
- Client writes PCM to native output.
- Android output uses `AudioTrack`.
- iOS output uses `AVAudioEngine` and `AVAudioPlayerNode`.
- Client health tracks underruns, reconnects, and native write failures.

Key tests:

- `test/features/client/client_live_audio_pipeline_test.dart`
- `test/features/client/wav_pcm_stream_parser_test.dart`
- `test/services/server/wav_pcm16_test.dart`
- `test/features/server/media/microphone_capture_service_test.dart`

## Alerts and Notifications

Server analysis emits alert events for audio, motion, battery, and system
conditions. Client alert handling has two surfaces:

- In-app alert history.
- Local OS notifications where permission allows.

Alerts are transported as JSON DTOs. Optional fields such as `battery`,
`transport`, `childId`, and `snapshotAvailable` are backward-compatible.

## Adaptive Quality

The client sends `/quality/report` updates that combine:

- RTT.
- Network tier.
- Video frame health.
- Audio chunk health.
- Reconnect state.
- Battery snapshot.
- Active watch state.

The server uses those reports and backpressure metrics to choose an effective
media profile. Audio and alerts remain preferred when the connection gets weak.

## Diagnostics

Diagnostic surfaces are part of the runtime, not only tests:

| Route | Purpose |
| --- | --- |
| `/test` | Browser dashboard |
| `/test/status` | Runtime diagnostics JSON |
| `/test/probe` | Loopback media probe |
| `/test/alert` | Test alert emission |
| `/test/audio-tone` | Test audio response |

The high-value media proof is:

```text
/session/start
  -> /video first MJPEG payload
  -> /audio first PCM payload
  -> /test/probe loopback status
```

## Feature Controls

These local control surfaces exist:

- `/comfort/state`
- `/comfort/command`
- `/night-light/state`
- `/night-light/command`
- `/talk/start`
- `/talk/stop`
- `/talk/audio`
- `/talk/video`

Important honesty note: these routes currently model protocol state and receive
payloads. Full comfort-audio playback, native talk playback, and parent-video
overlay should be verified as separate platform-media work before being
marketed as complete.

## Bluetooth and Hotspot

Media does not travel over Bluetooth. The current media runtime is HTTP/WS over
a local IP network. Hotspot support is therefore OS/user-managed: if both phones
are on the same local network or hotspot network, the HTTP/WS transport can
work. Direct Bluetooth video/audio is out of scope.

The dependency set includes `bluetooth_low_energy`, but docs and product copy
must not claim production Bluetooth media streaming.

## Known Gaps

- No cloud relay or mobile-data relay.
- No account system.
- No Apple Watch companion.
- No HTTPS/WSS transport.
- No WebRTC/H.264/Opus transport.
- No direct Bluetooth media.
- Comfort audio playback needs a real player/asset sink before release claims.
- Two-way talk needs real native playback and video overlay before release
  claims.
- Multi-child storage exists, but default server identity still needs careful
  real-device validation.

## Test Checklist

Recommended local gate:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Focused media gate:

```bash
flutter test test/features/server/media_stream_end_to_end_test.dart
flutter test test/features/client/client_live_audio_pipeline_test.dart
flutter test test/features/client/client_media_stream_supervisor_test.dart
```

Focused monetization gate:

```bash
flutter test test/services/monetization/broadcast_access_service_test.dart
flutter test test/features/client/client_runtime_lifecycle_test.dart
flutter test test/features/server/feature_control_endpoints_test.dart
```

UI regression gate:

```bash
flutter test test/features/performance/screen_render_budget_test.dart
```

## Release Notes for Stores

Before shipping paid unlock:

1. Create non-consumable product `mimicam_lifetime_unlock_try_300`.
2. Set price to 300 TL or the matching local tier.
3. Test purchase and restore on Android and iOS sandbox accounts.
4. Confirm the app handles unavailable store state.
5. Confirm unlock survives app restart on the same device.

Before shipping iOS:

1. Build on macOS.
2. Check camera, microphone, local network, and notification permissions.
3. Check native PCM playback.
4. Check QR scan permission fallback.
5. Check purchase/restore on sandbox.
