# MimiCam Architecture

This document describes the current Flutter implementation. The source of truth is the `lib/` tree and the tests under `test/`. Older Kotlin architecture, UDP discovery, internet relay, and pinned TLS ideas are not active runtime pieces.

## Architecture Principles

1. **One app, one active role:** Server and Client share one Flutter app, but only one runtime graph is mounted at a time.
2. **Local-first transport:** MVP transport is `http` plus `ws` on the local network.
3. **Pair before private access:** Private routes require trusted tokens, media routes can use short-lived stream tokens.
4. **Audio/events before video:** Video can degrade or skip frames; audio and alerts should stay responsive.
5. **No unbounded backlog:** Slow video/audio clients skip data instead of accumulating queues.
6. **Runtime diagnostics are first-class:** `/test/status`, `/test/probe`, `/test/alert`, and `/test/audio-tone` exist to verify real delivery.
7. **Docs must describe actual code:** Unsupported transports and codecs are marked out of scope, not presented as future-present features.

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
  -> ClientRuntime
  -> PairingSessionStore
  -> QRPairingClient
  -> TrustedTokenRenewalClient
  -> StreamSessionController
  -> NetworkQualityMonitor
  -> ClientAlertListener
  -> ClientAlertHistory
  -> ClientNotificationService
```

Role switching disposes the old runtime, updates the role repository, clears client pairing state where appropriate, and mounts the new shell.

## Package Map

```text
lib/
├── app/
│   ├── app_bootstrap.dart
│   ├── app_role.dart
│   ├── role_permission_coordinator.dart
│   ├── role_repository.dart
│   └── role_resolver.dart
├── core/
│   ├── media/
│   ├── network/
│   ├── protocol/
│   └── security/
├── analysis/
│   ├── alert/
│   ├── audio/
│   └── video/
├── features/
│   ├── client/
│   ├── server/
│   └── shared/
├── l10n/
└── services/
    ├── mimicam_server.dart
    ├── server/
    └── platform/
```

## Transport

The transport config is intentionally narrow:

```dart
enum TransportMode { localHttpWs }
```

The active schemes are:

- HTTP: `http`
- WebSocket: `ws`
- QR payload transport id: `http_ws`

There is no runtime `HttpServer.bindSecure`, TLS context, certificate manager, certificate fingerprint, HTTPS fallback, WSS fallback, WebRTC, H.264, Opus, or relay transport.

## Pairing Payload and Capabilities

Pairing starts from Server QR/IP screen. Public status returns:

```json
{
  "service": "mimicam",
  "pairing": true,
  "serverDeviceId": "server_local",
  "serverName": "Bebek Odası",
  "pairingNonce": "nonce",
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

Capabilities must reflect the MVP transport truth. Unsupported `h264-webrtc` and `opus` claims should not appear unless real support is implemented.

## Token Model

### Pairing Nonce

- Created by `PairingTokenService.createPairingNonce()`.
- Carried in QR/public status.
- Consumed by `/pair/confirm`.
- One-time use.
- Time limited.

### Trusted Client Token

- Issued by `/pair/confirm`.
- Renewed by `/auth/renew`.
- Required as Bearer auth for private routes.
- Stored on Client through `PairingSessionStore`.
- Stored securely in `flutter_secure_storage`.
- Stored on Server as token hash.

Trusted client limit:

```text
maxTrustedClients = 5
```

The sixth trusted pairing fails with `MAX_TRUSTED_CLIENTS_REACHED`.

### Stream Token

- Issued by `/session/start`.
- Default TTL is 90 seconds.
- Valid only for `/video` and `/audio`.
- Associated with a normalized `clientId`.
- Rejected on control endpoints.

Stream token lifecycle is managed by `ActiveClientRegistry` and `PairingTokenService`.

## Endpoint Routing

`MimiCamServer` owns route selection. Each request passes through local-network filtering, method validation, auth mode validation, and route handler execution.

| Route | Method | Auth mode | Handler responsibility |
| --- | --- | --- | --- |
| `/status/public` | GET | none/local guard | Public pairing status |
| `/pair/confirm` | POST | nonce | Trusted token issue |
| `/auth/renew` | POST | Bearer | Trusted token renewal |
| `/session/start` | POST | Bearer | Active watch slot and stream token |
| `/session/stop` | POST | Bearer | Watch cleanup |
| `/quality/report` | POST | Bearer | Client health ingestion |
| `/status` | GET | Bearer | Private runtime status |
| `/video` | GET | Bearer or stream token | MJPEG attach |
| `/audio` | GET | Bearer or stream token | WAV attach |
| `/ws/events` | WebSocket GET | Bearer or query trusted token | Alert event socket |
| `/test/*` | mixed | mostly Bearer | Diagnostic tooling |

Route exceptions are caught at the top-level request handler so responses are not left open.

## Active Client Registry

`ActiveClientRegistry` separates three concerns:

- Active watch sessions.
- Attached media stream connections.
- Quality report lifecycle.

Important internal state:

```text
_sessionClients
_activeClients
_streamConnectionCounts
ClientQualityTracker
PairingTokenService stream tokens
```

Lifecycle rules:

- `/session/start` activates the client and adds it to `_sessionClients`.
- Starting the same client again does not consume another active slot.
- `/video` or `/audio` attach increments stream connection count.
- Media stream disconnect decrements connection count.
- A disconnect does not remove an active watch session while `_sessionClients` contains the client.
- `/session/stop` runs full cleanup for that client.
- Expired stream tokens are pruned; if no stream connection and no valid stream token remain, the client is cleaned up.
- Explicit cleanup removes active slot, session marker, stream counters, quality report, and stream tokens.

This is the core guard against media reconnect loops.

## Media Runtime

`MimiCamServer.startMediaRuntime()` initializes camera, analysis pipeline, microphone capture, wakelock, and foreground service. Tests can construct the server with `startMediaOnSessionStart: false` to avoid camera dependencies in protocol tests.

Media runtime pieces:

| Component | Responsibility |
| --- | --- |
| `CameraController` | Camera image stream |
| `CameraImageJpegEncoder` | Camera frame to JPEG |
| `MjpegStreamService` | MJPEG response lifecycle |
| `MicrophoneCaptureService` | PCM capture |
| `WavAudioStreamService` | WAV response lifecycle |
| `MediaAnalysisCoordinator` | Audio/video analysis fan-in |
| `AlertEngine` | Alert decision and event emission |
| `EpisodeBasedNotificationAggregator` | Parent-facing episode messages |

## MJPEG Service

`MjpegStreamService` owns:

- Attached MJPEG responses.
- Response to `clientId` map.
- Per-stream diagnostics.
- Backpressure metrics.
- Client detach callback.

Attach behavior:

```text
set multipart content type
add response to clients
register response.done cleanup
if latest frame exists: write it
else: write zero-length keepalive and flush
```

Broadcast behavior:

```text
for each client:
  if busy, skip frame
  else write multipart frame and flush
  record success/failure metrics
```

The zero-length keepalive is intentionally not a video frame. Client parser skips it and waits for a real JPEG part.

## WAV Audio Service

`WavAudioStreamService` owns:

- WAV stream response headers.
- Initial WAV header write.
- PCM chunk broadcast.
- Busy client tracking.
- Backpressure metrics.
- Client detach callback.

Audio does not queue unlimited chunks. If a response is busy, new audio chunks for that client are skipped and counted.

## Client Video Pipeline

`ClientVideoViewer`:

- Validates the URL host and port against the paired server.
- Uses HTTP `Accept: multipart/x-mixed-replace, image/jpeg`.
- Supports Bearer auth but normally uses stream token in URL.
- Applies connect timeout.
- Applies response timeout.
- Applies read timeout.
- Parses MJPEG chunks with `MjpegStreamParser`.
- Reports frame receipt to `ClientStreamHealthState`.
- Reports stream timeout and reconnect attempts.
- Cancels retry timer on dispose or restart.

## Client Audio Pipeline

`ClientLiveAudioPipeline`:

- Validates paired host and port.
- Requests `audio/wav, audio/x-wav, application/octet-stream`.
- Applies connect timeout.
- Applies response timeout.
- Applies read timeout.
- Parses WAV with `WavPcmStreamParser`.
- Starts native PCM sink after format detection.
- Uses `ClientAudioJitterBuffer` for recent aligned PCM frames.
- Emits write/error/status updates.

Native sink:

```text
PcmAudioOutput
  -> MethodChannel("mimicam/pcm_audio")
  -> Android AudioTrack
  -> iOS AVAudioEngine + AVAudioPlayerNode
```

## Quality Reporting

Client health state is produced from existing live streams, not from extra media probes.

Inputs:

- Video frame callbacks.
- Audio chunk write callbacks.
- Audio error callbacks.
- WebSocket connect/disconnect/reconnect callbacks.
- RTT/status probe from `NetworkQualityMonitor`.

Quality report path:

```text
ClientStreamHealthState.snapshot
  -> NetworkQualityMonitor
  -> POST /quality/report
  -> ActiveClientRegistry.updateQualityReport
  -> MediaQualitySelector.select
  -> _setActiveMediaProfile
```

Quality selector constraints:

- Fast degrade on critical stream health.
- Slow upgrade after stable period.
- Single-step upgrade.
- Client load caps profile.
- Backpressure can force lower utility.

## Alert Flow

```text
Camera/microphone analysis
  -> MediaAnalysisCoordinator
  -> AlertEngine
  -> AlertEvent
  -> MimiCamServer event broadcast
  -> /ws/events clients
  -> ClientAlertListener
  -> ClientAlertHistory
  -> ClientNotificationService
```

The Client stores alert history separately from OS notifications. Local notification permission affects system notification display, not in-app event history.

## Test Diagnostics

`services/server/mimicam_server_test_endpoints.dart` adds runtime probe endpoints:

- `/test`
- `/test/dashboard.js`
- `/test/status`
- `/test/start`
- `/test/reset`
- `/test/probe`
- `/test/alert`
- `/test/audio-tone`

`/test/status` reports runtime state, active clients, video counters, audio counters, event counters, backpressure, and analysis diagnostics.

## Test Strategy

High-value test groups:

- Role isolation and role switching.
- Pairing payload parsing.
- Secure session storage migration.
- Trusted token and stream token auth.
- Active client limits and reconnect lifecycle.
- MJPEG parser and stream service behavior.
- WAV parser and live audio pipeline behavior.
- Client runtime lifecycle.
- Alert listener, alert history, notification screens.
- Adaptive media selector and backpressure gates.
- Test endpoint behavior.
- Localization fallback and supported locales.
- Compact UI overflow/render budget.

Recommended full gate:

```bash
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

Media-focused gate:

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

## Platform Architecture

Android:

- `MainActivity.kt` implements PCM audio method channel.
- `MimiCamForegroundService.kt` handles foreground service behavior.
- `AudioTrack` is used for low-latency PCM output.
- Gradle is Kotlin DSL and Java 17 targeted.

iOS:

- `AppDelegate.swift` implements PCM audio method channel.
- `AVAudioEngine` and `AVAudioPlayerNode` play PCM.
- `Info.plist` contains camera, microphone, local network, and Bonjour usage strings.
- Local iOS build is not expected from Linux.

## Current Non-Goals

- Internet relay.
- Account system.
- Push notification backend.
- UDP broadcast discovery.
- Telegram automation.
- HTTPS/WSS.
- Certificate pinning.
- WebRTC/H.264.
- Opus.
- Per-client video encoding.
