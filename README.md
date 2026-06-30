# MimiCam

MimiCam is a local-first Flutter baby monitor. One phone runs as the **Server** in the baby room, another phone runs as the **Client** for the parent. The current MVP is intentionally simple and honest:

- Local Wi-Fi only.
- HTTP/WS transport only.
- MJPEG video.
- PCM16LE/WAV audio.
- JSON WebSocket events.
- QR/manual-IP pairing.
- Trusted token plus short-lived stream token auth.

There is no cloud relay, account system, OAuth, UDP discovery, Telegram automation, WebRTC, H.264, Opus, HTTPS/WSS, or certificate pinning in the current runtime.

## What Works Today

| Area | Current implementation |
| --- | --- |
| App roles | Server and Client are isolated runtime graphs |
| Pairing | QR payload or manual `IP:port` fallback |
| Auth | Trusted Bearer token, stream token for media endpoints |
| Video | MJPEG over `GET /video` |
| Audio | PCM16LE/WAV over `GET /audio` |
| Events | JSON alerts over `GET /ws/events` WebSocket |
| Notifications | In-app alert history plus local OS notifications |
| Storage | Secure trusted token, preferences metadata |
| Quality | Client health reports drive adaptive media profiles |
| Diagnostics | Browser `/test` panel and JSON `/test/*` endpoints |

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

Android debug output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Linux can run Flutter analysis, tests, and Android builds. iOS builds require a macOS runner or a local Mac.

## Product Flow

```text
Open app
  -> choose Server or Client
  -> Server opens QR/IP pairing screen
  -> Client scans QR or enters IP:port
  -> Server validates one-time nonce
  -> Client stores trusted token securely
  -> Client restores session on next app launch
  -> Client starts watch session
  -> Server issues short-lived stream token
  -> Client opens video/audio streams and event socket
  -> Client sends quality reports
  -> Server adapts video quality and keeps audio/events prioritized
```

Changing role disposes the old runtime and builds the new role graph. The app does not run Server and Client graphs at the same time.

## Server Role

Server responsibilities:

- Expose local HTTP routes.
- Generate QR pairing payloads.
- Validate pairing nonce and issue trusted tokens.
- Start camera and microphone runtime when needed.
- Encode camera frames into MJPEG.
- Stream PCM16LE/WAV audio.
- Run audio/video analysis and alert aggregation.
- Track active watch clients and stream attachments.
- Select adaptive media profile from client quality reports.
- Expose `/test` diagnostics for runtime validation.

Important Server files:

- `lib/services/mimicam_server.dart`
- `lib/features/server/server_runtime.dart`
- `lib/features/server/server_composition_root.dart`
- `lib/features/server/pairing/pairing_token_service.dart`
- `lib/features/server/media/mjpeg_stream_service.dart`
- `lib/features/server/media/wav_audio_stream_service.dart`
- `lib/features/server/media/microphone_capture_service.dart`
- `lib/services/server/active_client_registry.dart`
- `lib/services/server/media_quality_selector.dart`
- `lib/services/server/utility_based_profile_selector.dart`

## Client Role

Client responsibilities:

- Scan QR payloads with `mobile_scanner`.
- Pair with the Server using `/pair/confirm`.
- Store trusted token in secure storage.
- Restore saved sessions on launch.
- Renew trusted token when needed.
- Start and stop watch sessions.
- Read MJPEG video stream.
- Read WAV audio stream and push PCM to native output.
- Listen to alert WebSocket events.
- Persist in-app alert history.
- Show local OS notifications where permission allows.
- Send quality reports without opening extra media streams.

Important Client files:

- `lib/features/client/client_runtime.dart`
- `lib/features/client/client_composition_root.dart`
- `lib/features/client/pairing/pairing_session_store.dart`
- `lib/features/client/pairing/qr_pairing_client.dart`
- `lib/features/client/media/stream_session_controller.dart`
- `lib/features/client/media/client_video_viewer.dart`
- `lib/features/client/media/client_live_audio_pipeline.dart`
- `lib/features/client/media/network_quality_monitor.dart`
- `lib/features/client/media/client_stream_health_state.dart`
- `lib/features/client/alerts/client_alert_listener.dart`
- `lib/features/client/alerts/client_alert_history.dart`

## Pairing and Storage

The QR payload carries address, nonce, expiry, transport, and capability metadata. It does not carry a trusted token.

Example public status/capability shape:

```json
{
  "service": "mimicam",
  "pairing": true,
  "serverDeviceId": "server_local",
  "serverName": "Bebek Odası",
  "pairingNonce": "one-time-nonce",
  "transport": "http_ws",
  "capabilities": {
    "video": "mjpeg",
    "videoPreferred": "mjpeg",
    "audio": "pcm16le",
    "audioPreferred": "pcm16le",
    "events": "json",
    "maxClients": 5,
    "transportPreferred": "http_ws"
  }
}
```

Client storage split:

| Data | Location |
| --- | --- |
| Trusted token | `flutter_secure_storage` |
| Pairing payload | `SharedPreferences` |
| Client id | `SharedPreferences` |
| Token expiry metadata | `SharedPreferences` |
| Alert history | `SharedPreferences` |

Legacy `pairing_session` JSON records are migrated on load. Corrupt or incomplete session records are cleared instead of crashing startup.

## Auth Model

Trusted token:

- Issued by `/pair/confirm`.
- Renewed by `/auth/renew`.
- Sent as `Authorization: Bearer <token>`.
- Stored on Server as a hash, not as raw token.
- Required for private state-changing endpoints.

Stream token:

- Issued by `/session/start`.
- Short lived, currently 90 seconds by default.
- Accepted only by `/video` and `/audio`.
- Passed as `?streamToken=...`.
- Not accepted by `/status`, `/quality/report`, `/auth/renew`, or other private control routes.

The WebSocket event route accepts trusted auth either through Bearer headers or the `token` query parameter, matching the current client connection path.

## Media Session Lifecycle

```text
ClientRuntime.startWatching
  -> StreamSessionController.start
  -> POST /session/start with Bearer token
  -> Server creates/refreshes active watch slot
  -> Server returns streamToken
  -> ClientVideoViewer opens /video?streamToken=...
  -> ClientAudioStreamPlayer opens /audio?streamToken=...
```

The latest hardening keeps watch sessions separate from transient stream socket state:

- `/session/start` marks a client as an active watch session.
- `/video` and `/audio` attach stream connections to that client.
- A media socket disconnect does not immediately delete the watch session.
- Reconnects can reuse the same still-valid stream token.
- `/session/stop`, token expiry without live stream connections, or explicit cleanup clears the active slot.

This prevents a short Wi-Fi stall or widget rebuild from revoking the media token and trapping the client in a reconnect loop.

## Video Stream

Video is MJPEG over HTTP. The Server keeps a single latest JPEG frame and broadcasts frames to active MJPEG responses.

Video behavior:

- No per-client camera encode.
- No per-client frame queue.
- Slow clients skip frames instead of building backlog.
- Ready latest frame is written immediately on attach.
- If no frame exists yet, a zero-length multipart keepalive is flushed so the HTTP response opens.
- Client parser ignores zero-length keepalive parts.
- Client validates host and port against the paired server.
- Client applies connect, response, and read timeouts.
- Client retry timer is cancelled on dispose.

Key tests:

- `test/features/server/mjpeg_stream_service_test.dart`
- `test/features/client/client_video_viewer_test.dart`
- `test/features/client/mjpeg_stream_parser_test.dart`

## Audio Stream

Audio is PCM16LE wrapped in a WAV stream. The client parses the WAV header in Dart and writes PCM chunks to native low-latency output.

Native output:

- Android: `AudioTrack`
- iOS: `AVAudioEngine` and `AVAudioPlayerNode`

Audio behavior:

- Audio stream sends WAV header first.
- Client jitter buffer keeps recent aligned PCM frames.
- Slow native writes are counted and reported.
- Connect, response, and read timeout guards are applied.
- Audio underrun and reconnect attempts feed quality reporting.

Key tests:

- `test/features/client/client_live_audio_pipeline_test.dart`
- `test/features/client/wav_pcm_stream_parser_test.dart`
- `test/services/server/wav_pcm16_test.dart`
- `test/features/server/media/microphone_capture_service_test.dart`

## Alerts and Notifications

Server analysis emits alert events for audio, motion, and system conditions. Client alert handling has two surfaces:

- In-app alert history.
- Local OS notification.

The in-app history is intentionally independent from OS notification permission. If notification permission is denied, incoming WebSocket alerts should still appear in the app's notification/history surfaces.

Main files:

- `lib/analysis/alert/alert_engine.dart`
- `lib/analysis/alert/episode_notification_aggregator.dart`
- `lib/features/client/alerts/client_alert_listener.dart`
- `lib/features/client/alerts/client_alert_history.dart`
- `lib/features/client/alerts/client_notification_service.dart`
- `lib/services/notification_service.dart`

Key tests:

- `test/analysis/alert/alert_engine_test.dart`
- `test/analysis/alert/episode_notification_aggregator_test.dart`
- `test/features/client/client_alert_listener_test.dart`
- `test/features/client/client_alert_history_test.dart`
- `test/features/client/client_notification_screen_test.dart`

## Adaptive Quality

Client quality reports combine network and stream-health signals:

- RTT.
- Consecutive failures.
- Video frame gap.
- Video stream timeout.
- Audio gap.
- Audio underrun.
- WebSocket disconnect count.
- Reconnect count.
- Watch active state.

The Server combines these signals with client load and stream backpressure. Degradation is fast; upgrade is conservative and requires stable metrics.

Profile targets:

| Tier | Resolution | FPS | JPEG quality | Priority |
| --- | ---: | ---: | ---: | --- |
| Normal | 854x480 | 8 | 52 | Video + audio |
| Weak | 640x360 | 5 | 42 | Audio/events first |
| Critical | 426x240 | 2 | 36 | Audio/events first |
| Survival | 426x240 | 1 | 36 | Snapshot + audio/events |

Client load also caps quality:

- 1 active client can use normal profile on good health.
- 2-3 active clients are capped around weak profile.
- 4-5 active clients are pushed toward critical/survival behavior.

Key tests:

- `test/services/server/media_quality_selector_test.dart`
- `test/services/server/utility_based_profile_selector_test.dart`
- `test/services/server/active_client_load_quality_test.dart`
- `test/core/media/client_quality_tracker_test.dart`
- `test/core/media/adaptive_media_weak_wifi_test.dart`

## Endpoint Matrix

| Endpoint | Method | Auth | Purpose |
| --- | --- | --- | --- |
| `/status/public` | GET | Local network + pairing mode | Public pairing data |
| `/pair/confirm` | POST | Nonce | Trusted token issue |
| `/auth/renew` | POST | Bearer trusted token | Trusted token renewal |
| `/session/start` | POST | Bearer trusted token | Watch slot and stream token |
| `/session/stop` | POST | Bearer trusted token | Watch slot cleanup |
| `/quality/report` | POST | Bearer trusted token | Client quality report |
| `/status` | GET | Bearer trusted token | Private server status |
| `/video` | GET | Bearer or stream token | MJPEG stream |
| `/audio` | GET | Bearer or stream token | WAV/PCM stream |
| `/ws/events` | WebSocket GET | Bearer or trusted query token | Alert events |

All HTTP requests pass through `LocalNetworkGuard`. It accepts private IPv4 ranges and debug loopback; it is a safety guard, not an internet-grade firewall.

## Test and Diagnostic Endpoints

| Endpoint | Purpose |
| --- | --- |
| `/test` | Browser diagnostic dashboard |
| `/test/dashboard.js` | Dashboard script |
| `/test/status` | JSON runtime diagnostics |
| `/test/start` | Start media runtime attempt |
| `/test/reset` | Stop and clear test runtime state |
| `/test/probe` | Probe video/audio/event movement |
| `/test/alert` | Emit synthetic alert |
| `/test/audio-tone` | Deterministic WAV tone |

For media regressions, start with:

```text
/session/start
/video
/audio
/ws/events
/quality/report
/test/status
/test/probe
```

Important `/test/status` fields:

- `runtime.mediaActive`
- `runtime.cameraInitialized`
- `runtime.microphoneActive`
- `clients.activeStreamClients`
- `clients.videoClients`
- `clients.audioClients`
- `video.framesStreamed`
- `video.lastClientWriteAtMs`
- `audio.chunksStreamed`
- `audio.lastStartError`
- `events.totalWebSocketDeliveries`

## Repository Map

```text
lib/
├── app/                    # app bootstrap, role resolver, permissions
├── core/                   # protocol, security, media profile, network guard
├── analysis/               # audio/video analysis and alert engine
├── features/
│   ├── client/             # Client runtime, pairing, media, alerts, UI
│   ├── server/             # Server runtime, pairing, media services, UI
│   └── shared/             # shared presentation primitives
├── l10n/                   # localized text catalogs
└── services/               # MimiCamServer, config, platform/server policies
```

Documentation:

- `README.md`: operator and contributor entry point.
- `ARCHITECT.md`: detailed runtime architecture.
- `docs/kotlin_to_flutter_porting_matrix.md`: old Kotlin responsibility map.
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md`: iOS launch image asset notes.

## Localization

Supported locales:

- `en`
- `tr`
- `zh`
- `hi`
- `es`
- `fr`
- `de`
- `ar_SA`
- `ar_QA`

Unknown locales fall back to English.

## Platform Notes

Android:

- Native PCM sink uses `AudioTrack`.
- Server mode uses wakelock and foreground service integration.
- Gradle uses Java 17 target.
- Current Flutter builds may warn about Kotlin Gradle Plugin migration.

iOS:

- Native PCM sink uses `AVAudioEngine` and `AVAudioPlayerNode`.
- `Info.plist` includes camera, microphone, local network, and Bonjour usage strings.
- Build verification requires macOS.
- Launch image assets live under `ios/Runner/Assets.xcassets/LaunchImage.imageset/`.

## Focused Verification Commands

Media and lifecycle:

```bash
flutter test \
  test/services/server/active_client_registry_test.dart \
  test/features/server/mjpeg_stream_service_test.dart \
  test/features/client/client_video_viewer_test.dart \
  test/features/client/client_live_audio_pipeline_test.dart \
  test/features/client/stream_session_controller_test.dart \
  test/features/client/mjpeg_stream_parser_test.dart \
  test/features/client/wav_pcm_stream_parser_test.dart \
  test/features/server/token_auth_test.dart \
  test/features/server/endpoint_worst_case_test.dart \
  test/features/server/test_endpoints_test.dart
```

UI and compact screens:

```bash
flutter test test/features/performance/screen_render_budget_test.dart
```

Full gate:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

## Troubleshooting

### Video does not start

1. Check `/test/status`.
2. Confirm `clients.activeStreamClients` is non-zero after `/session/start`.
3. Confirm `clients.videoClients` increments after `/video`.
4. Check `video.framesStreamed` and `video.lastClientWriteAtMs`.
5. Check Client logs for video timeout/reconnect events.

### Audio does not play

1. Try `/test/audio-tone`.
2. Check `audio.lastStartError`.
3. Check `audio.chunksStreamed`.
4. Check native `AudioTrack` or `AVAudioEngine` status.
5. Check Client audio read timeout and underrun status.

### Alerts arrive but OS notifications do not show

1. Check Client in-app alert history first.
2. Check OS notification permission.
3. Trigger `/test/alert`.
4. Check `/test/status` event delivery counters.

### Pairing fails

1. Make sure Server QR/IP screen is open.
2. Make sure both devices are on the same local network.
3. Open `http://<server-ip>:<port>/status/public` from the Client network.
4. Refresh the QR if nonce or expiry is stale.

## Out of Scope

Current MVP does not include:

- Internet access outside local Wi-Fi.
- Cloud relay.
- User accounts.
- Push backend.
- UDP discovery.
- Telegram automation.
- HTTPS/WSS and certificate pinning.
- WebRTC, H.264, Opus.
- Per-client video encode pipelines.
