# MimiCam

MimiCam is a local-first Flutter baby monitor. One phone runs in **Server**
mode in the baby room; another phone runs in **Client** mode for the parent.
The app is designed around local Wi-Fi, explicit pairing, real audio/video
delivery, and runtime diagnostics that can prove whether media actually moves.

The current product intentionally does not include cloud relay, accounts,
internet-wide access, Apple Watch, HTTPS/WSS, or mobile-data relay. Local media
uses MJPEG/WAV by default and now has an opt-in, one-peer WebRTC H.264 + Opus
pilot. A failed or unsupported pilot negotiation falls back to MJPEG/WAV.

## Current Status

| Area | Implementation |
| --- | --- |
| Roles | One active role at a time: Server or Client |
| Pairing and discovery | QR/manual `IP:port`, plus `_mimicam._tcp` DNS-SD/NSD discovery |
| Transport | Local HTTP/WebSocket; opt-in WebRTC pilot for media |
| Video | MJPEG over `GET /video`; H.264 in the WebRTC pilot |
| Audio | PCM16LE/WAV over `GET /audio`; Opus in the WebRTC pilot |
| Events | JSON alert events over `GET /ws/events` WebSocket |
| Auth | Trusted Bearer token plus short-lived stream token |
| Monitoring | Client live watch with audio, alerts, night clock, and full screen controls |
| Publishing | Server live preview with full screen controls |
| Monetization | Hidden and unenforced by default; opt-in paywall build flag |
| Diagnostics | Browser `/test` panel and JSON `/test/*` endpoints |
| Resource policy | Demand-owned legacy/analyzer camera/microphone plus thermal, power and backpressure governor |
| Platform lifecycle | Android service-owned engine; iOS foreground-camera pause/recovery contract |
| Audio lifecycle | Android audio focus/noisy-route handling; iOS interruption/route recovery |
| Telemetry | Bounded session counters and p50/p95/p99 latency distributions |
| Feature controls | Generated comfort sounds, night light, and parent-to-room PCM talk audio |
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

The WebRTC pilot is off by default. Enable it on the room/server build with:

```bash
flutter run --dart-define=MIMICAM_WEBRTC_PILOT=true
```

The server advertises WebRTC only after both H.264 and Opus capability probes
succeed. The client performs its own capability probe and automatically starts
a new MJPEG/WAV session if WebRTC negotiation fails.

The broadcast paywall is also off by default so development and device tests
never show a price card or purchase prompt. Enable it only for an explicit
store/paywall verification build:

```bash
flutter run --dart-define=MIMICAM_BROADCAST_PAYWALL_ENABLED=true
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
  -> Server issues short-lived stream token and selected media transport
  -> Client opens WebRTC or MJPEG/WAV media plus the event socket
  -> Client posts quality reports
  -> Server adapts media quality and device resource policy
```

Changing role disposes the active runtime graph and mounts the new role. The app
does not run Server and Client graphs at the same time.

## Pricing Model

The pricing implementation is behind
`MIMICAM_BROADCAST_PAYWALL_ENABLED`, which defaults to `false`. With the flag
off, no purchase service is created, no trial timer is enforced, price fields
are not advertised, and Server/Client screens do not render purchase UI.

When the flag is explicitly enabled, MimiCam uses this local one-time unlock
model:

- First 2 hours of live broadcast/watch time are free.
- After the free limit is exhausted, live streaming is locked.
- Unlock is a one-time purchase shown as `300 TL`.
- Store product id: `mimicam_lifetime_unlock_try_300`.
- Only a verified unlock result is stored locally on the device.

The code uses `in_app_purchase` and expects the App Store / Play Console product
to be configured as a non-consumable item with the product id above. The code
cannot create the store product or price by itself.

Enforcement happens in runtime code, not only in UI:

- Client `startWatching` refuses to start after the free limit.
- Server `/session/start` returns `402 Payment Required` without issuing a
  stream token after the free limit.
- Server status/capabilities expose free limit, unlock price, and product id.

`StorePayloadPurchaseVerifier` rejects the wrong product, unknown store source,
non-deliverable state, or missing local/server verification data. It persists a
SHA-256 fingerprint and verification metadata, never the raw receipt or purchase
token. This is a fail-closed local envelope check, not Apple/Google server-side
receipt authenticity validation; a production backend verifier is still needed
for that stronger guarantee.

## Server Role

Server responsibilities:

- Bind the local HTTP server.
- Prefer a dual-stack IPv6 bind and fall back to IPv4 when unavailable.
- Advertise the active room as `_mimicam._tcp` through Bonjour/NSD.
- Generate QR payloads and public pairing status.
- Validate pairing nonce and issue trusted client tokens.
- Reconcile legacy MJPEG/WAV camera and microphone independently from actual
  video/audio and analyzer demand.
- Apply the native background contract: Android foreground-service ownership
  and controlled iOS camera pause/recovery.
- Encode camera frames to JPEG and broadcast them as MJPEG.
- Capture PCM audio and broadcast it as a WAV stream.
- Offer one-peer H.264 + Opus WebRTC when the pilot is enabled and available.
- Run motion/audio analysis and emit alerts.
- Track active watch clients and attached stream sockets.
- Apply adaptive media quality based on client health reports.
- Apply thermal, low-power, battery, encode and backpressure degradation policy.
- Play generated comfort audio and parent talk PCM through native room output.
- Expose diagnostics under `/test`.
- Enforce the free broadcast limit for incoming watch sessions.

Important files:

- `lib/services/mimicam_server.dart`
- `lib/features/server/server_runtime.dart`
- `lib/features/server/server_composition_root.dart`
- `lib/features/server/media/mjpeg_stream_service.dart`
- `lib/features/server/media/wav_audio_stream_service.dart`
- `lib/features/server/media/microphone_capture_service.dart`
- `lib/features/server/media/media_runtime_controller.dart`
- `lib/features/server/media/webrtc/flutter_webrtc_server_gateway.dart`
- `lib/features/server/pairing/pairing_token_service.dart`
- `lib/services/server/active_client_registry.dart`
- `lib/services/server/media_quality_selector.dart`
- `lib/services/server/media_resource_governor.dart`
- `lib/services/server/baby_monitor_feature_controller.dart`
- `lib/services/discovery/mimicam_service_discovery.dart`
- `lib/services/monetization/broadcast_access_service.dart`

## Client Role

Client responsibilities:

- Scan QR with `mobile_scanner`.
- Discover rooms through DNS-SD/NSD, including IPv6 endpoints.
- Pair through `/pair/confirm`.
- Store trusted token in secure storage.
- Restore saved sessions on launch.
- Renew trusted tokens when needed.
- Start and stop live watch sessions.
- Negotiate WebRTC and fall back to MJPEG/WAV without leaving a pilot session
  active.
- Read MJPEG video.
- Read WAV audio and write PCM to native playback.
- Listen to alert WebSocket events.
- Store in-app alert history.
- Show local notifications when permission is granted.
- Report network, stream, and battery health.
- Capture push-to-talk microphone PCM and control room comfort audio.
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
- `lib/features/client/media/webrtc/flutter_webrtc_client_connector.dart`
- `lib/features/client/controls/client_room_controls.dart`
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
| Server trusted-client token hashes | `SharedPreferences` |
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
- Required by `/video` and `/audio`; a trusted Bearer token alone cannot bypass
  it.
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
  -> Server returns streamToken and accepted mediaTransport
  -> WebRTC: HTTP signaling opens H.264/Opus peer media
  -> fallback: ClientMediaStreamSupervisor opens /video and /audio
```

Watch sessions are separate from transient media sockets:

- `/session/start` marks the active watch session.
- `/video` and `/audio` attach stream sockets.
- A media socket disconnect does not immediately delete the watch session.
- Reconnect can reuse the same valid stream token.
- `/session/stop`, token expiry, or explicit cleanup clears the active slot.

Legacy MJPEG/WAV camera and microphone ownership is demand based. Video-only
operation does not request the microphone; audio-only operation does not
request the camera. `MediaRuntimeController` serializes transitions so late
starts and stops cannot leave a privacy-sensitive resource active. Analyzer
demand is folded into the same resource decision. The WebRTC pilot owns its
`getUserMedia` tracks inside the gateway; its session demand is merged into the
native service contract, legacy capture is suspended while the peer owns the
hardware, and platform pause closes pilot tracks. Physical-device validation is
still required for codec, thermal and background behavior.

Platform lifecycle is explicit:

- Android keeps the existing Flutter engine under foreground-service ownership
  for active media demand. The service is `START_NOT_STICKY`; after process
  death it does not silently reacquire while-in-use camera/microphone access.
- iOS does not claim background camera capture. Entering background emits a
  controlled media-pause request; returning active restores retained demand.

## Video

The default/fallback video path is MJPEG over HTTP.

- Server keeps the latest JPEG frame.
- Server broadcasts frames to attached MJPEG responses.
- There is no per-client camera encode.
- Active media profile dimensions are applied during JPEG conversion and JPEG
  uses 4:2:0 chroma sampling.
- Each client has a one-slot latest-frame mailbox; stale pending frames are
  overwritten instead of queued.
- Client decoding is one-in-flight plus one-latest-pending; live frames stay
  outside Flutter's global `ImageCache` and replaced `ui.Image` handles are
  disposed.
- Camera capture uses a device-tier FPS ceiling and active-profile frame pacing.
  iOS NV12/BGRA plane layouts are handled explicitly.
- JPEG conversion runs in one persistent worker isolate with one in-flight
  encode and one replaceable pending frame.
- Multipart frames include sequence, capture-time, and send-time metadata.
- Client rendering keeps only the newest complete frame in a network burst and
  reports sequence gaps, relative queue delay, and RFC-style jitter.
- If no frame exists, a zero-length multipart keepalive opens the response.
- Client parser ignores keepalive parts.
- Client validates host and port against the paired server.
- Client supports full screen and `cover` / `contain` fit modes.

Key tests:

- `test/features/server/mjpeg_stream_service_test.dart`
- `test/features/client/client_video_viewer_test.dart`
- `test/features/client/mjpeg_stream_parser_test.dart`
- `test/features/server/media_stream_end_to_end_test.dart`

## WebRTC H.264 + Opus Pilot

The pilot is deliberately additive to the legacy path:

- Off by default; enable with `MIMICAM_WEBRTC_PILOT=true`.
- Server and client both require H.264 and Opus runtime capabilities.
- HTTP signaling uses `/webrtc/offer`, `/webrtc/ice`, and `/webrtc/close`.
- The pilot currently allows one active peer and uses host ICE only on the
  local LAN (`iceServers` is empty).
- If capability probing or negotiation fails, the client closes the pilot
  session and starts a fresh `mjpeg_wav` session.
- MJPEG/WAV remains the compatibility and diagnostic path.

Focused tests:

- `test/features/server/webrtc_signaling_endpoints_test.dart`
- `test/features/client/stream_session_controller_test.dart`

## Audio

The default/fallback audio path is PCM16LE wrapped in a live WAV stream.

- Server writes a WAV header first.
- Server converts arbitrary recorder chunks to fixed 20 ms PCM frames.
- Every client has a bounded 160 ms sender queue. Overflow or a stalled flush
  closes that stream so the client reconnects with a clean timeline.
- Client parses WAV in Dart.
- Client uses fixed 20 ms frames, an adaptive 60-220 ms jitter target, and an
  80-100 ms native high-water pump; its hard Dart buffer limit is 320 ms.
- Client writes fixed PCM frames to native output.
- Android output uses `AudioTrack`.
- iOS output uses `AVAudioEngine` and `AVAudioPlayerNode`.
- Android requests audio focus, pauses on focus loss or becoming-noisy events,
  observes device-route changes, and reports focus/interrupt metrics.
- iOS reacts to AVAudioSession interruption, route change and media-services
  reset notifications and reports those events through the platform runtime.
- Client health tracks underruns, reconnects, and native write failures.

The research and parameter rationale are recorded in
`docs/media_transport_algorithms.md`.

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

The server uses those reports, bounded session telemetry, device thermal/power
state, encoder pressure and stream backpressure to choose an effective media
profile. The governor moves through `normal`, `constrained`, `survival`, and
audio-first modes. Audio and alerts remain preferred when the connection or
device gets weak.

## Diagnostics

Diagnostic surfaces are part of the runtime, not only tests:

| Route | Purpose |
| --- | --- |
| `/test` | Browser dashboard |
| `/test/status` | Runtime diagnostics JSON |
| `/test/probe` | Loopback media probe |
| `/test/alert` | Test alert emission |
| `/test/audio-tone` | Test audio response |

`/test/status` also exposes `sessionTelemetry`, `deviceResources`,
`resourceGovernor`, room-audio status, transport state and stream health.
Telemetry sample windows are bounded and publish counters plus p50/p95/p99
durations, so long-running sessions do not create an unbounded metric buffer.

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

Comfort playback generates 16 kHz mono PCM for white noise, pink noise, rain,
and a procedural soft lullaby, then writes it through the same native PCM sink
used by client playback. Push-to-talk captures parent microphone PCM and streams
it to the room device; talk temporarily preempts comfort playback and comfort
resumes after talk ends. Talk video is intentionally reported as unsupported:
`/talk/video` remains a compatibility ingest route, but there is no parent-video
overlay.

## Local Discovery and IPv6

- The room advertises `_mimicam._tcp` while pairing is active.
- The client starts an NSD/Bonjour browser with automatic resolution and
  IPv4/IPv6 lookup.
- The HTTP server first attempts an IPv6 dual-stack bind (`v6Only: false`) and
  falls back to IPv4.
- URI construction uses IPv6-safe authorities.
- Discovery failure does not remove QR or manual `IP:port` fallback.

This is service discovery only. Media is still local IP traffic, not Bluetooth.

## Bluetooth and Hotspot

Media does not travel over Bluetooth. The current media runtime uses local-IP
HTTP/WS or the opt-in WebRTC pilot. Hotspot support is therefore OS/user-managed:
if both phones are on the same local network or hotspot network, local media can
work. Direct Bluetooth video/audio is out of scope.

The dependency set includes `bluetooth_low_energy`, but docs and product copy
must not claim production Bluetooth media streaming.

## Known Gaps

- No cloud relay or mobile-data relay.
- No account system.
- No Apple Watch companion.
- No HTTPS/WSS transport.
- No direct Bluetooth media.
- WebRTC is an opt-in, one-peer LAN pilot, not the default or a relay/NAT
  traversal solution.
- Parent-to-room talk is audio-only; parent video overlay is not implemented.
- Purchase verification is local-envelope validation; release-grade App
  Store/Google Play server verification is not implemented.
- Physical-device test scenarios and release gates are defined in
  `docs/physical_device_test_matrix.md`, but simulator/unit tests do not count
  as completed physical-device evidence.
- The requested security bundle was intentionally excluded for this local-LAN
  scope: public pairing-nonce redesign, centralized request-body limits,
  socket lease/revoke, and secure session tickets are not implemented here.
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
flutter test test/features/client/stream_session_controller_test.dart
flutter test test/features/server/webrtc_signaling_endpoints_test.dart
flutter test test/features/server/media_runtime_controller_test.dart
flutter test test/services/server/media_resource_governor_test.dart
flutter test test/core/media/media_session_telemetry_test.dart
flutter test test/services/platform/platform_runtime_contract_test.dart
flutter test test/services/discovery/mimicam_service_discovery_test.dart
flutter test test/services/server/room_audio_coordinator_test.dart
flutter test test/features/client/client_room_controls_test.dart
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
5. Confirm verification failures do not grant or persist entitlement.
6. Integrate an Apple/Google server-side receipt verifier before treating local
   receipt-envelope validation as fraud-resistant.
7. Confirm unlock survives app restart on the same device.

Before shipping iOS:

1. Build on macOS.
2. Check camera, microphone, local network, and notification permissions.
3. Check native PCM playback.
4. Check QR scan permission fallback.
5. Check purchase/restore on sandbox.
