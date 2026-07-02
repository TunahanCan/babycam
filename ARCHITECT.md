# MimiCam Architecture

This document describes the current Flutter implementation. The source of truth
is the `lib/` tree and the tests under `test/`.

Older Kotlin plans, UDP discovery, cloud relay, WebRTC, pinned TLS, and direct
Bluetooth media are not active runtime pieces.

## Principles

1. **One app, one active role.** Server and Client live in the same Flutter app,
   but only one runtime graph is mounted at a time.
2. **Local-first transport.** Current media transport is local HTTP plus
   WebSocket.
3. **Pair before private access.** Private routes require trusted tokens.
4. **Short-lived media credentials.** `/video` and `/audio` can use stream
   tokens issued by `/session/start`.
5. **No unbounded queues.** Slow clients skip frames or chunks.
6. **Audio and alerts beat video fidelity.** Weak network decisions prefer
   continued sound and event delivery over high resolution.
7. **Runtime diagnostics are first-class.** `/test/status` and `/test/probe`
   prove delivery paths.
8. **Paid access is enforced in runtime.** Paywall UI is not the only gate.

## Runtime Topology

```text
main.dart
  -> MimiCamApp
  -> AppBootstrap
  -> SharedPreferencesRoleRepository
  -> RoleResolver
  -> ServerCompositionRoot OR ClientCompositionRoot
```

Server graph:

```text
ServerCompositionRoot
  -> BroadcastAccessService
  -> ServerRuntime
  -> MimiCamServer
  -> PairingTokenService
  -> ActiveClientRegistry
  -> MjpegStreamService
  -> WavAudioStreamService
  -> MicrophoneCaptureService
  -> MediaAnalysisCoordinator
```

Client graph:

```text
ClientCompositionRoot
  -> BroadcastAccessService
  -> ClientRuntime
  -> PairingSessionStore
  -> QRPairingClient
  -> TrustedTokenRenewalClient
  -> StreamSessionController
  -> ClientMediaStreamSupervisor
  -> NetworkQualityMonitor
  -> ClientAlertListener
  -> ClientAlertHistory
  -> ClientNotificationService
```

Role switching disposes the old runtime, saves the new role, clears client
pairing state where appropriate, and mounts the new shell.

## Package Map

```text
lib/
├── app/
│   ├── app_bootstrap.dart
│   ├── app_role.dart
│   ├── role_permission_coordinator.dart
│   ├── role_repository.dart
│   └── role_resolver.dart
├── analysis/
│   ├── alert/
│   ├── audio/
│   └── video/
├── core/
│   ├── media/
│   ├── network/
│   ├── protocol/
│   └── security/
├── features/
│   ├── client/
│   ├── server/
│   └── shared/
├── l10n/
└── services/
    ├── mimicam_server.dart
    ├── monetization/
    ├── platform/
    └── server/
```

## Transport

The active transport is intentionally narrow:

| Layer | Current value |
| --- | --- |
| HTTP scheme | `http` |
| WebSocket scheme | `ws` |
| QR transport id | `http_ws` |
| Video codec | MJPEG |
| Audio codec | PCM16LE/WAV |
| Event format | JSON |

There is no active secure server socket, certificate manager, HTTPS fallback,
WSS fallback, relay, WebRTC, H.264, or Opus implementation.

## Pairing

Pairing starts from Server QR/IP screen.

```text
Server.startPairingMode
  -> NetworkAddressProvider chooses local host
  -> ServerQrPayloadBuilder creates PairingPayload
  -> Client scans QR or fetches /status/public
  -> QRPairingClient posts /pair/confirm
  -> PairingTokenService consumes nonce
  -> trusted token returned
  -> PairingSessionStore saves metadata and secure token
```

Pairing payload fields:

- schema version
- host
- port
- server device id
- server display name
- pairing nonce
- expiry timestamp
- transport id
- capabilities map

The payload must not contain trusted tokens.

## Token Model

### Pairing Nonce

- Created by `PairingTokenService.createPairingNonce`.
- Carried in QR/public status.
- Consumed by `/pair/confirm`.
- One-time use.
- Time limited.
- Protected by pruning and rate-limit behavior.

### Trusted Token

- Issued by `/pair/confirm`.
- Renewed by `/auth/renew`.
- Sent as `Authorization: Bearer <token>`.
- Stored on the server as a hash.
- Stored on the client in `flutter_secure_storage`.
- Required by private control routes.

### Stream Token

- Issued by `/session/start`.
- Associated with normalized client id.
- Valid for media endpoints only.
- Accepted by `/video` and `/audio`.
- Rejected by control endpoints.

## Endpoint Routing

`MimiCamServer` owns route selection. Requests go through:

1. Local network guard.
2. Method validation.
3. Auth mode validation.
4. Route handler.
5. Top-level error handling.

| Route | Method | Auth | Responsibility |
| --- | --- | --- | --- |
| `/status/public` | GET | none/local guard | Public pairing status |
| `/pair/confirm` | POST | nonce body | Trusted token issue |
| `/auth/renew` | POST | Bearer | Trusted token renewal |
| `/session/start` | POST | Bearer | Paywall check, active watch slot, stream token |
| `/session/stop` | POST | Bearer | Watch cleanup |
| `/quality/report` | POST | Bearer | Health and battery ingestion |
| `/status` | GET | Bearer | Private runtime status |
| `/video` | GET | Bearer or stream token | MJPEG attach |
| `/audio` | GET | Bearer or stream token | WAV attach |
| `/ws/events` | WebSocket GET | trusted token | Alert event socket |
| `/comfort/state` | GET | Bearer | Comfort state |
| `/comfort/command` | POST | Bearer | Comfort command reducer |
| `/night-light/state` | GET | Bearer | Night light state |
| `/night-light/command` | POST | Bearer | Night light command reducer |
| `/talk/start` | POST | Bearer | Talk token issue |
| `/talk/stop` | POST | Bearer | Talk session stop |
| `/talk/audio` | POST | talk token | Talk audio byte ingest |
| `/talk/video` | POST | talk token | Talk video byte ingest |
| `/test/*` | mixed | debug/test auth | Runtime diagnostics |

## Monetization

`BroadcastAccessService` tracks local free usage and one-time unlock state.

```text
BroadcastAccessService
  -> free limit: 2 hours
  -> price label: 300 TL
  -> product id: mimicam_lifetime_unlock_try_300
  -> storage: SharedPreferences
  -> purchase gateway: in_app_purchase
```

Client enforcement:

```text
ClientRuntime.startWatching
  -> BroadcastAccessService.beginSession("client.watch")
  -> if locked, throw BroadcastAccessLockedException
  -> otherwise start stream session
```

Server enforcement:

```text
MimiCamServer._handleSessionStart
  -> BroadcastAccessService.beginSession("server.stream.<clientId>")
  -> if locked, return 402 Payment Required
  -> otherwise issue stream token
```

When the active free-time timer expires, the runtime stops live media and emits
a locked state.

## Active Client Registry

`ActiveClientRegistry` separates:

- active watch sessions
- attached media stream connections
- quality reports
- stream tokens

Lifecycle:

```text
/session/start
  -> startSession(clientId)
  -> issue stream token

/video or /audio
  -> attachStream(clientId)
  -> stream service owns response

response.done
  -> detachStream(clientId)

/session/stop
  -> cleanupClient(clientId)
```

This avoids deleting an active watch session just because one media socket
reconnected.

## Media Runtime

`MimiCamServer.startMediaRuntime` starts:

- camera permission check
- camera controller
- camera image stream
- media analysis pipeline
- microphone capture
- wakelock
- foreground service on Android

Tests can inject `ServerMediaSource` and set `startMediaOnSessionStart: false`
to avoid hardware dependencies.

## Video Pipeline

Server:

```text
CameraImage
  -> CameraImageJpegEncoder
  -> latest JPEG
  -> MjpegStreamService.broadcast
```

Client:

```text
ClientMediaStreamSupervisor
  -> ClientVideoViewer / MjpegStreamParser
  -> Uint8List frame
  -> WatchScreen surface
```

`MjpegStreamService` owns:

- response set
- response-to-client map
- zero-length keepalive
- backpressure metrics
- detach callback
- diagnostics snapshot

## Audio Pipeline

Server:

```text
MicrophoneCaptureService
  -> raw PCM for analysis
  -> leveled PCM for stream
  -> WavAudioStreamService.broadcast
```

Client:

```text
ClientMediaStreamSupervisor
  -> ClientLiveAudioPipeline
  -> WavPcmStreamParser
  -> ClientAudioJitterBuffer
  -> PcmAudioOutput
  -> Android AudioTrack / iOS AVAudioEngine
```

Audio has timeout, reconnect, native write, and underrun reporting.

## Analysis and Alerts

Video analysis:

- luma downsampling
- motion scoring
- ROI support
- sustained motion threshold
- global light-change rejection

Audio analysis:

- PCM16 sample reading
- ring buffer
- Goertzel band analysis
- cry-like score
- calibration
- hysteresis

Alert layer:

- cooldown policy
- alert event DTOs
- episode aggregation
- localized parent messages
- WebSocket delivery
- local notification fan-out on client

## Quality Reporting

`NetworkQualityMonitor` posts `/quality/report`.

Inputs:

- status RTT
- stream health
- audio chunk gaps
- video frame health
- reconnect attempts
- active watch flag
- server media profile
- battery snapshot

Server selection combines quality reports, active client count, device tier, and
backpressure metrics.

## Battery

Battery snapshots are modeled by `BatterySnapshot` and read through
`BatterySnapshotProvider`.

Server status includes:

- server battery
- client batteries
- transport information
- stream health

Client quality reports can include a client battery snapshot.

## Feature Control Services

`baby_monitor_feature_services.dart` contains:

- `ComfortAudioService`
- `NightLightController`
- `TalkSessionRegistry`

Current implementation status:

- Comfort state and command catalog exist.
- Night light state and torch/screen-glow command model exist.
- Talk session token, busy state, audio byte count, and video byte count exist.

Platform-side comfort playback, native talk playback, and parent-video overlay
must be treated as unfinished until real sinks are implemented and tested.

## UI Architecture

Server:

- `ServerHomeScreen`
- `ServerRuntime`
- QR/IP tab
- stream preview tab
- service status tab
- settings tab
- full screen preview
- broadcast access card

Client:

- `ClientHomeScreen`
- `WatchScreen`
- QR scanner
- manual pairing
- alert history
- night clock
- full screen watch
- broadcast access card

Responsive UI is protected by `test/features/performance/screen_render_budget_test.dart`.

## Diagnostics

Diagnostics are runtime surfaces:

- `/test`
- `/test/dashboard.js`
- `/test/status`
- `/test/start`
- `/test/reset`
- `/test/probe`
- `/test/alert`
- `/test/audio-tone`

`/test/probe` is the most useful end-to-end proof because it starts a real
session and verifies media loopback through `/video` and `/audio`.

## Test Strategy

Core gates:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

High-value suites:

- `test/features/server/media_stream_end_to_end_test.dart`
- `test/features/server/feature_control_endpoints_test.dart`
- `test/features/client/client_runtime_lifecycle_test.dart`
- `test/services/monetization/broadcast_access_service_test.dart`
- `test/features/client/client_live_audio_pipeline_test.dart`
- `test/features/client/client_media_stream_supervisor_test.dart`
- `test/features/performance/screen_render_budget_test.dart`

## Future Work Rules

Do not document a feature as supported until it has:

1. Runtime implementation.
2. Wire contract.
3. Client integration.
4. Server integration.
5. Tests.
6. README and architecture updates.

This rule especially applies to:

- cloud relay
- mobile-data access
- account login
- Apple Watch
- HTTPS/WSS
- WebRTC/H.264/Opus
- direct Bluetooth media
- comfort audio playback
- real two-way talk playback
