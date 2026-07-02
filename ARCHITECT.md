# MimiCam Architecture

Bu dokuman MimiCam Flutter uygulamasinin mevcut mimari gercegini anlatir.
Kaynak kodun asil sahibi `lib/` agacidir; test davranisinin asil sahibi
`test/` agacidir. Bu dosya, eski Kotlin planlarini veya pazarlama hedeflerini
degil, bu repodaki calisan Flutter uygulamasini tarif eder.

MimiCam tek Flutter uygulamasi icinde iki rol tasir:

- **Server:** Bebek odasindaki cihazdir. Kamera, mikrofon, analiz, alert
  uretimi, HTTP media server, WebSocket event server ve runtime diagnostics
  burada calisir.
- **Client:** Ebeveyn cihazidir. Pairing yapar, video izler, PCM sesi native
  cikisa yazar, alert dinler, local notification uretir ve server'a kalite
  raporu gonderir.

Aktif runtime modeli local-first'tur. Bulut relay, hesap sistemi, internetten
sinirsiz erisim, Apple Watch, WebRTC, H.264, Opus, HTTPS/WSS ve dogrudan
Bluetooth video/ses tasima bu mimarinin aktif parcasi degildir.

## Architectural Truths

1. **Tek app, tek aktif rol.** `Server` ve `Client` runtime grafikleri ayni
   process icinde tanimli olsa da ayni anda sadece biri mount edilir.
2. **Local HTTP/WS transport.** Kontrol ve media HTTP uzerinden, alert/event
   akisi WebSocket uzerinden akar.
3. **Pairing once, private access sonra.** Pairing olmadan private route'lara
   erisilmez.
4. **Trusted token ve stream token farklidir.** Trusted Bearer token state
   degistiren endpointler icindir. Stream token sadece `/video` ve `/audio`
   media endpointleri icindir.
5. **Media backpressure bounded kalir.** Slow client icin eski frame/chunk
   biriktirilmez; skip ve failure metric yazilir.
6. **Ses ve kritik alert video kalitesinden onceliklidir.** Ag kotulesirse
   video profili dusurulur; audio ve alert delivery korunmaya calisilir.
7. **Runtime diagnostics urun davranisinin parcasidir.** `/test/status`,
   `/test/probe` ve `/test/audio-tone` gercek endpoint davranisini kanitlar.
8. **Ucretli erisim UI'dan ibaret degildir.** 2 saat ucretsiz yayin/izleme
   siniri hem Client runtime hem Server `/session/start` katmaninda uygulanir.
9. **Docs shipped code'u anlatir.** Bitmemis ozellikler "destekleniyor" diye
   yazilmaz; partial veya out-of-scope olarak ayrilir.

## Current Transport Matrix

| Concern | Current runtime |
| --- | --- |
| Control transport | HTTP |
| Video transport | HTTP streaming |
| Audio transport | HTTP streaming |
| Event transport | WebSocket |
| QR transport id | `http_ws` |
| Video codec | MJPEG |
| Audio codec | PCM16LE inside WAV stream |
| Alert payload | JSON DTO |
| Private auth | Trusted Bearer token |
| Media auth | Stream token or trusted Bearer where allowed |
| Test surface | `/test/*` |
| Local network exposure guard | `LocalNetworkGuard` |

## Out Of Scope In This Runtime

Bu maddeler kodda bazi dependency, model veya plan izleri olsa bile aktif
production davranisi olarak yazilmamalidir:

- cloud relay
- mobile-data relay
- account/login backend
- Apple Watch companion
- HTTPS/WSS socket
- certificate pinning
- WebRTC
- H.264
- Opus
- direct Bluetooth media
- automatic hotspot creation
- native comfort-audio playback sink
- real parent talk playback and parent video overlay

`bluetooth_low_energy` dependency'si vardir, fakat mevcut media akisinda
Bluetooth video/ses tasimaz. Media hala local IP network veya kullanicinin/OS'in
olusturdugu hotspot network uzerinden HTTP/WS ile akar.

## Dependency Map

Runtime acisindan onemli dependency'ler:

| Package | Ownership |
| --- | --- |
| `camera` | Server camera preview/image stream |
| `record` | Server microphone PCM16 stream |
| `image` | Camera image to JPEG encoding support |
| `web_socket_channel` | Client/event tests and WS support |
| `flutter_local_notifications` | Client local notification |
| `shared_preferences` | Role, config, alert history, child metadata, paid usage |
| `flutter_secure_storage` | Trusted token storage |
| `qr_flutter` | Server QR rendering |
| `mobile_scanner` | Client QR scanning |
| `permission_handler` | Permission coordination |
| `wakelock_plus` | Server runtime keep-awake |
| `battery_plus` | Battery snapshots |
| `in_app_purchase` | One-time unlock purchase/restore |
| `just_audio` | Comfort-audio dependency, full playback sink not complete |
| `bluetooth_low_energy` | BLE capability dependency, media transport not active |

Flutter assets:

- `assets/branding/mimicam_launcher_icon.png`
- `assets/branding/mimicam_wordmark.png`
- `assets/test_dashboard/index.html`
- `assets/test_dashboard/dashboard.js`

## Source Tree Ownership

```text
lib/
├── main.dart
├── app/
│   ├── app_bootstrap.dart
│   ├── app_lifecycle_observer.dart
│   ├── app_role.dart
│   ├── mimicam_app.dart
│   ├── role_permission_coordinator.dart
│   ├── role_repository.dart
│   └── role_resolver.dart
├── analysis/
│   ├── alert/
│   ├── audio/
│   └── video/
├── core/
│   ├── bytes/
│   ├── media/
│   ├── network/
│   ├── protocol/
│   ├── security/
│   └── theme/
├── features/
│   ├── client/
│   ├── role_selection/
│   ├── server/
│   └── shared/
├── l10n/
└── services/
    ├── mimicam_server.dart
    ├── monetization/
    ├── platform/
    └── server/
```

Package ownership:

- `app/`: App bootstrap, role resolution, role switching, permission entry.
- `analysis/`: Pure-ish motion/audio/alert scoring logic.
- `core/`: DTOs, protocol constants, security helpers, theme, transport values.
- `features/client/`: Client UI, Client runtime, pairing, media receive path,
  alert receive path.
- `features/server/`: Server UI, Server runtime facade, pairing QR builder,
  stream services near UI/runtime boundaries.
- `services/`: HTTP server, platform facades, monetization, media-quality
  selectors, test dashboard, backpressure utilities.

## App Bootstrap

Startup flow:

```text
main.dart
  -> runApp(MimiCamApp)
  -> MaterialApp
  -> AppBootstrap
  -> SharedPreferences.getInstance()
  -> SharedPreferencesRoleRepository
  -> RoleResolver
  -> ServerAppShell OR ClientAppShell OR RoleSelectionScreen
```

`MimiCamApp` owns:

- app title
- theme
- supported locales
- localization delegates
- `AppBootstrap` as home

`AppBootstrap` owns:

- loading `SharedPreferences`
- resolving stored `AppRole`
- requesting permissions for selected role
- creating one runtime graph per active role
- disposing old runtime before switching role
- clearing pairing session storage during role switch
- guarding server-to-client role switch with confirmation UI

Role switching is intentionally destructive for the previous runtime. When
roles change:

```text
_switchRole
  -> increment role switch generation
  -> remove active runtime from widget tree
  -> dispose ServerRuntime or ClientRuntime
  -> clear PairingSessionStore
  -> save or clear AppRole
  -> mount the new composition root
```

This prevents a Server HTTP runtime and a Client media runtime from remaining
alive at the same time.

## Role Permission Policy

`RolePermissionCoordinator` is the permission entry point at role selection.
Server role needs camera/microphone/local notification oriented permissions.
Client role needs camera only for QR scanning and notification permission for
alerts. Permission denial should not crash role selection; the runtime layer and
UI still expose fallback/manual paths where possible.

Important permission boundaries:

- iOS QR scanning must not rely on implicit scanner autostart only.
- Server microphone capture is best-effort; video runtime must not crash only
  because microphone permission is denied.
- Microphone failure must appear in `/test/status` or `/test/probe`.

## Composition Roots

The app uses small composition roots instead of global singletons.

Server creation:

```text
ServerCompositionRoot.create
  -> PairingTokenService
  -> BroadcastAccessService
  -> MimiCamServer
  -> ServerQrPayloadBuilder
  -> MediaRuntimeController
  -> ServerRuntime
```

Client creation:

```text
ClientCompositionRoot.create
  -> ClientIdentityStore
  -> QRPairingClient
  -> TrustedTokenRenewalClient
  -> PairingSessionStore
  -> ClientStreamHealthState
  -> StreamSessionController
  -> NetworkQualityMonitor
  -> ClientAlertHistory
  -> BroadcastAccessService
  -> ClientNotificationService
  -> ClientAlertListener
  -> ClientRuntime
```

Composition roots wire dependencies and callbacks. They do not own business
behavior directly. That keeps tests able to inject token stores, media sources,
HTTP clients and runtime callbacks.

## Server Runtime Facade

`ServerRuntime` is a UI-facing state facade around lower-level services.

It owns:

- `ServerRuntimeState`
- pairing phase state
- media phase state
- local preview demand
- active stream-session demand
- notification demand
- server resource counters
- broadcast-access snapshot refresh
- runtime state stream for widgets

It does not directly implement HTTP routing, camera encoding, token issuing or
stream writes. Those live in `MimiCamServer` and service classes.

Important state fields:

- `phase`
- `powerMode`
- `activeClients`
- `activeVideoClients`
- `activeAudioClients`
- `activeEventClients`
- `cameraActive`
- `microphoneActive`
- `motionAnalyzerActive`
- `cryAnalyzerActive`
- `qrPayload`
- `lastAlert`
- `errorMessage`
- `mediaProfile`
- `broadcastAccess`

Server phases:

```text
stopped
pairingIdle
pairingActive
clientPaired
mediaIdle
mediaStarting
mediaActive
error
```

Media resource demand:

```text
local preview
  -> video capture needed

active watch session with video
  -> video capture needed

active watch session with audio
  -> audio capture needed

notification demand for cry
  -> audio analysis needed

notification demand for motion
  -> video analysis needed
```

`MediaResourceCounter` folds those demands into camera/microphone active flags.

## Client Runtime Facade

`ClientRuntime` is the UI-facing state facade for pairing, watching, alerts,
network quality and paywall state.

It owns:

- `ClientRuntimeState`
- current `PairingSession`
- active stream session
- network quality subscription
- alert history facade
- broadcast-access snapshot
- token renewal lifecycle
- watch start/stop lifecycle

Client phases:

```text
unpaired
scanningQr
pairing
pairedIdle
renewingToken
watching
alertOnly
reconnecting
offline
revoked
error
```

Watch start flow:

```text
ClientRuntime.startWatching(audioEnabled: true)
  -> BroadcastAccessService.beginSession("client.watch")
  -> StreamSessionController.start(session, audioEnabled)
  -> /session/start
  -> ActiveStreamSession(streamToken)
  -> WatchScreen mounts ClientMediaStreamSupervisor
  -> /video stream
  -> /audio stream if audio enabled
```

Alert start flow:

```text
ClientRuntime.startAlertListening
  -> ClientNotificationService.initialize
  -> ClientAlertListener.start
  -> WebSocket /ws/events
  -> ClientAlertHistory.add
  -> ClientNotificationService.showAlert
```

Token renewal:

- `PairingSession.shouldRenew` returns true when trusted token is within 7 days
  of expiry.
- `TrustedTokenRenewalClient` calls `/auth/renew`.
- If renew returns null or is rejected, runtime moves to `revoked` and clears
  stored session.

## Protocol Constants

`MimiCamProtocolV2` owns the current route names:

| Constant | Path |
| --- | --- |
| `pairConfirm` | `/pair/confirm` |
| `authRenew` | `/auth/renew` |
| `sessionStart` | `/session/start` |
| `sessionStop` | `/session/stop` |
| `qualityReport` | `/quality/report` |
| `comfortState` | `/comfort/state` |
| `comfortCommand` | `/comfort/command` |
| `nightLightState` | `/night-light/state` |
| `nightLightCommand` | `/night-light/command` |
| `talkStart` | `/talk/start` |
| `talkStop` | `/talk/stop` |
| `talkAudio` | `/talk/audio` |
| `talkVideo` | `/talk/video` |
| `video` | `/video` |
| `audio` | `/audio` |
| `events` | `/ws/events` |
| `status` | `/status` |
| `statusPublic` | `/status/public` |
| `testDashboard` | `/test` |
| `testDashboardScript` | `/test/dashboard.js` |
| `testStatus` | `/test/status` |
| `testStart` | `/test/start` |
| `testReset` | `/test/reset` |
| `testProbe` | `/test/probe` |
| `testAlert` | `/test/alert` |
| `testAudioTone` | `/test/audio-tone` |

`ServerEndpointBuilder` builds HTTP and WS URIs from `PairingSession` and keeps
path/query normalization centralized on the client.

## HTTP Server Ownership

`MimiCamServer` is the runtime owner for:

- local HTTP server socket
- WebSocket upgrade
- route table
- local network exposure guard
- auth checks
- pairing nonce consumption
- trusted token renewal
- session token issuing
- media runtime start/stop
- media stream attach/detach
- quality report ingestion
- status and diagnostics JSON
- comfort/night-light/talk control endpoints
- alert broadcast

Request flow:

```text
HttpRequest
  -> disposed guard
  -> LocalNetworkGuard
  -> WebSocket upgrade branch for /ws/events
  -> route lookup
  -> method check
  -> auth mode check
  -> route handler
  -> top-level error logging/500 fallback
```

`LocalNetworkGuard` is not a firewall. It reduces accidental exposure if the
socket becomes reachable from a non-local address.

Auth modes:

| Mode | Meaning |
| --- | --- |
| `none` | No trusted token needed; route may have its own nonce/body token |
| `bearer` | Requires trusted `Authorization: Bearer <token>` |
| `streamToken` | Accepts media stream token or trusted token for media attach |
| `testAccess` | Debug mode open; otherwise trusted Bearer token required |

Stream tokens intentionally stop at `/video` and `/audio`. State-changing
routes must use trusted Bearer auth.

## Route Table

| Route | Method | Auth mode | Owner behavior |
| --- | --- | --- | --- |
| `/status/public` | GET | none | Pairing-only public descriptor |
| `/pair/confirm` | POST | none | Nonce validation and trusted token issue |
| `/auth/renew` | POST | none/body token | Trusted token renewal |
| `/session/start` | POST | bearer | Paywall, active slot, stream token |
| `/session/stop` | POST | bearer | Active session cleanup |
| `/quality/report` | POST | bearer | Client quality/battery/audio metrics |
| `/status` | GET | bearer | Private server runtime status |
| `/video` | GET | streamToken | MJPEG stream attach |
| `/audio` | GET | streamToken | WAV/PCM stream attach |
| `/ws/events` | WebSocket GET | trusted token | JSON alert socket |
| `/comfort/state` | GET | bearer | Comfort state JSON |
| `/comfort/command` | POST | bearer | Comfort reducer command |
| `/night-light/state` | GET | bearer | Night light state JSON |
| `/night-light/command` | POST | bearer | Night light reducer command |
| `/talk/start` | POST | bearer | Short talk token and busy check |
| `/talk/stop` | POST | bearer | Stop active talk session |
| `/talk/audio` | POST | talk token in body/query/header | Audio byte ingest |
| `/talk/video` | POST | talk token in body/query/header | Video byte ingest |
| `/test` | GET | debug or bearer | Browser test dashboard |
| `/test/dashboard.js` | GET | debug or bearer | Dashboard script asset |
| `/test/status` | GET | bearer | Diagnostics JSON |
| `/test/start` | POST | bearer | Start media runtime for tests |
| `/test/reset` | POST | bearer | Reset streams/metrics/test state |
| `/test/probe` | POST | bearer | End-to-end loopback probe |
| `/test/alert` | POST | bearer | Synthetic alert event |
| `/test/audio-tone` | GET | bearer | Deterministic WAV tone |

## Pairing Architecture

Server pairing flow:

```text
ServerHomeScreen QR/IP tab
  -> ServerRuntime.startPairingMode
  -> MimiCamServer.startPairingMode
  -> NetworkAddressProvider chooses local address
  -> PairingTokenService.createPairingNonce
  -> ServerQrPayloadBuilder.build
  -> PairingPayload.toUriString
  -> QrImageView renders payload
```

Client pairing flow:

```text
ClientHomeScreen
  -> QR scanner or manual IP
  -> PairingPayload.fromUriString OR /status/public
  -> QRPairingClient.pair
  -> POST /pair/confirm
  -> trusted token response
  -> PairingSessionStore.saveChild
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

Payload must not contain trusted token or stream token.

Manual IP fallback:

```text
user enters host:port
  -> client fetches /status/public
  -> server returns pairing descriptor if pairing mode active
  -> client posts /pair/confirm with nonce
```

## Token And Identity Model

Pairing nonce:

- created by `PairingTokenService`
- included in QR/public status
- consumed by `/pair/confirm`
- one-time use
- time limited
- pruned/rate-limited

Trusted token:

- issued by `/pair/confirm`
- renewed by `/auth/renew`
- sent as `Authorization: Bearer <token>`
- stored server-side as hash
- stored client-side in `flutter_secure_storage`
- required by private control endpoints

Stream token:

- issued by `/session/start`
- associated with normalized client id
- short-lived
- accepted by `/video` and `/audio`
- rejected by control endpoints
- revoked/expired with active client cleanup

Client identity:

- `ClientIdentityStore` generates a stable client id in secure storage.
- The old `client_local` fixed id pattern must not be reintroduced.
- `PairingSession.clientId` is the trusted runtime identity for session start,
  quality report and media stream ownership.

## Pairing And Child Profile Storage

`PairingSessionStore` stores:

- legacy selected session metadata in `SharedPreferences`
- trusted tokens in `flutter_secure_storage`
- up to 4 `ChildProfile` records
- selected child id
- one secure token per child profile

Important keys:

- `pairing_session`
- `pairing_session_token`
- `pairing_children`
- `pairing_selected_child_id`
- `pairing_child_token.<childId>`

`save(session)` delegates to `saveChild(session)`.

Child profile rules:

- maximum 4 profiles
- saving an existing child replaces it
- selecting a child mirrors its token into the legacy selected-token key
- legacy single-session storage migrates into child profile storage
- removing the selected child selects the first remaining profile

Production caveat: multi-child storage exists, but default server identity and
real multi-child UX must be validated carefully before marketing it as complete
multi-child monitoring.

## Monetization Architecture

`BroadcastAccessService` owns local usage and one-time unlock state.

Config:

```text
free limit: 2 hours
price label: 300 TL
product id: mimicam_lifetime_unlock_try_300
storage: SharedPreferences
store gateway: in_app_purchase
```

Client enforcement:

```text
ClientRuntime.startWatching
  -> BroadcastAccessService.beginSession("client.watch")
  -> if locked: BroadcastAccessLockedException
  -> else: start stream session
```

Server enforcement:

```text
POST /session/start
  -> BroadcastAccessService.beginSession("server.stream.<clientId>")
  -> if locked: HTTP 402 + BROADCAST_ACCESS_LOCKED
  -> else: ActiveClientRegistry.startSession
  -> stream token response
```

Server local preview enforcement:

```text
ServerRuntime.startLocalPreview
  -> beginSession("server.localPreview")
  -> if locked: UI error/paywall card
  -> else: media runtime start
```

Timer behavior:

- Active free session schedules a timer for remaining free time.
- Expiry clears active client registry, ends sessions and stops media runtime.
- UI receives updated `BroadcastAccessSnapshot`.

Store caveat: app code references the product id; Play Console/App Store
Connect must define the non-consumable product separately.

## Active Client Registry

`ActiveClientRegistry` separates concepts that are easy to accidentally mix:

- active watch sessions
- attached media stream sockets
- stream tokens
- client quality reports

Lifecycle:

```text
/session/start
  -> startSession(clientId)
  -> active client slot
  -> stream token

/video or /audio
  -> clientIdForStreamToken
  -> attachStream(clientId)
  -> stream service owns HttpResponse

response.done / stream close
  -> detachStream(clientId)

/session/stop
  -> stopSession(clientId)
  -> cleanup if no streams remain
```

Why this matters:

- closing `/video` must not end an active watch session if `/audio` reconnects
- reconnecting media sockets should reuse the same active client slot
- max active watchers applies to logical clients, not raw TCP sockets
- quality reports are attached to normalized active client ids

## Server Media Runtime

`MimiCamServer.startMediaRuntime` has two branches:

1. **Injected media source branch:** used by tests with `ServerMediaSource`.
2. **Hardware branch:** uses camera and microphone plugins.

Hardware branch:

```text
startMediaRuntime
  -> _ensureCameraPermission
  -> availableCameras
  -> _initializeAnalysisPipeline
  -> CameraController(..., enableAudio: false)
  -> controller.initialize
  -> controller.startImageStream(_handleCameraFrame)
  -> _startAudioAnalysisBestEffort
  -> WakelockPlus.enable
  -> ForegroundServiceController.startServer
```

Stop branch:

```text
stopMediaRuntime
  -> stop foreground service
  -> disable wakelock
  -> stop injected media source if any
  -> stop microphone capture
  -> cancel alert subscription
  -> dispose analysis coordinator
  -> dispose camera controller
  -> close video clients
  -> close audio clients
  -> reset diagnostics and selectors
```

Injected media branch:

```text
ServerMediaSource.start
  -> deterministic video frames
  -> deterministic audio chunks
  -> same MjpegStreamService / WavAudioStreamService path
```

This seam is central to reliable `/test/probe` and end-to-end tests because it
does not require real hardware.

## Video Pipeline

Server path:

```text
CameraImage
  -> MediaFramePolicy / FrameRateGate
  -> CameraImageJpegEncoder
  -> latest JPEG cache
  -> MjpegStreamService.broadcast
  -> HttpResponse multipart MJPEG clients
```

Injected test path:

```text
DeterministicServerMediaSource
  -> JPEG bytes
  -> _handleInjectedVideoFrame
  -> MjpegStreamService.broadcast
```

Client path:

```text
ClientMediaStreamSupervisor
  -> GET /video?streamToken=...
  -> MjpegStreamParser
  -> onVideoFrame(Uint8List)
  -> WatchScreen / ClientVideoViewer
```

`MjpegStreamService` owns:

- connected `HttpResponse` set
- response-to-client id mapping
- first frame delivery
- busy-client backpressure
- skip/failure metrics
- detach callback
- diagnostics snapshot
- close/reset behavior

Video invariants:

- no unbounded per-client frame queue
- slow client skips instead of blocking all clients
- frame encode is avoided when no stream client needs video except probe paths
- active media profile controls target fps, JPEG quality and camera preset
- stream teardown must not wait forever on long-lived MJPEG responses

## Audio Pipeline

Server microphone path:

```text
MicrophoneCaptureService
  -> record.startStream(PCM16)
  -> rawPcm16le for analysis
  -> AudioStreamLeveler.processPcm16le
  -> streamPcm16le for client playback
  -> WavAudioStreamService.broadcast
```

Server injected/test path:

```text
ServerMediaSource audio chunk
  -> _handleInjectedAudioChunk
  -> analysis coordinator
  -> WavAudioStreamService.broadcast
```

Client path:

```text
ClientMediaStreamSupervisor
  -> ClientLiveAudioPipeline
  -> GET /audio?streamToken=...
  -> WavPcmStreamParser
  -> ClientAudioJitterBuffer
  -> PcmAudioOutput.write
  -> Android AudioTrack / iOS AVAudioEngine
```

WAV stream contract:

- `/audio` responds with `Content-Type: audio/wav`
- response is chunked
- WAV header is written first
- PCM16LE chunks follow
- sample rate defaults to 16000
- channel count defaults to 1
- bits per sample defaults to 16

Server audio diagnostics:

- `recorderCreated`
- `permissionGranted`
- `microphoneStarted`
- `lastStartAttemptAtMs`
- `chunksCaptured`
- `bytesCaptured`
- `chunksStreamed`
- `bytesStreamed`
- `sourceChunksAccepted`
- `sourceBytesAccepted`
- `lastSequence`
- `lastSourceChunkAtMs`
- `lastClientWriteAtMs`
- `failureReason`
- `captureFailureReason`
- `lastError`
- `underruns`
- backpressure metrics

Failure reasons:

- `permissionDenied`
- `captureStartFailed`
- `captureStreamError`
- `captureNotActive`
- `noPcmCaptured`
- `noPcmBytesAfterWavHeader`
- `invalidWavHeader`
- `wavHeaderTimeout`
- `wavHeaderNotReceived`

Client audio diagnostics:

- `wavHeaderParsed`
- `networkBytesReceived`
- `pcmChunksParsed`
- `pcmBytesParsed`
- `bufferedBytes`
- `jitterBufferedBytes`
- `droppedBufferBytes`
- `jitterDroppedBytes`
- `nativeWriteAttempts`
- `nativeWriteCallsAccepted`
- `nativeWriteCallsDropped`
- `nativeBytesWritten`
- `nativeStatusBytesWritten`
- `droppedNativeWrites`
- `reconnects`
- `lastWriteAtMs`
- native sink status map

Those client metrics are emitted by `ClientLiveAudioPipeline`, copied into
`ClientStreamHealthState`, sent through `/quality/report`, stored by
`ClientQualityTracker`, and exposed in `/test/status` under client audio
pipeline diagnostics.

Audio invariants:

- microphone failure is best-effort and must not silently disappear
- video can work while audio reports a permission/capture reason
- `/test/audio-tone` must verify audio transport without microphone permission
- `/test/probe` must fail clearly if WAV header arrives but PCM does not
- native write errors must be visible in client metrics

## Native PCM Output

`PcmAudioOutput` uses method channel `mimicam/pcm_audio`.

Methods:

- `start`
- `write`
- `status`
- `playTestTone`
- `stop`

Android implementation:

- `AudioTrack`
- pending write guard
- write accepted/drop counters
- bytes written counter
- underrun count where API supports it
- play state/track state status

iOS implementation:

- `AVAudioEngine`
- `AVAudioPlayerNode`
- `AVAudioPCMBuffer`
- queued frame guard
- write accepted/drop counters
- bytes written counter
- playing status

Dart-side audio pipeline treats native write return value as authoritative for
per-write acceptance, while native `status()` supplies lower-level counters.

## Analysis Pipeline

`MediaAnalysisCoordinator` connects video/audio analyzers to alert generation.

Video analysis owns:

- `LumaDownsampler`
- `LumaFrame`
- `MotionAnalyzerV2`
- ROI support
- global light-change detection
- motion hysteresis
- frame-rate gate

Audio analysis owns:

- `Pcm16LeReader`
- `AudioRingBuffer`
- `GoertzelBandAnalyzer`
- `CryAudioAnalyzerV2`
- ambient calibration
- cry-like score
- hysteresis

Alert generation owns:

- `AlertConfig`
- `CooldownPolicy`
- `AlertEngine`
- `EpisodeBasedNotificationAggregator`
- localized parent messages
- JSON DTO conversion
- WebSocket fan-out

Audio analysis uses raw microphone PCM. Client playback uses leveled stream PCM.
That separation keeps cry scoring closer to the actual captured room signal
while still making live monitor audio easier to hear.

## Alert And Event Architecture

Server event path:

```text
AlertEngine emits AlertEvent
  -> MimiCamServer._handleAlertEvent
  -> AlertProtocolAdapter.toJsonText
  -> WebSocket clients
  -> legacy binary packet optional path
```

Client event path:

```text
ClientAlertListener
  -> WebSocket /ws/events
  -> AlertEventDto.fromJson
  -> ClientAlertHistory.add
  -> ClientNotificationService.showAlert
```

`AlertEventDto` fields:

- `schemaVersion`
- `id`
- `type`
- `severity`
- `messageKey`
- `message`
- `score`
- `timestampMs`
- `sourceDeviceId`
- optional `snapshotAvailable`
- optional `battery`
- optional `transport`
- optional `childId`
- `metadata`

Current limitation:

- There is no full ACK/retry protocol for critical events yet.
- Event ids exist as DTO ids, but monotonically ordered reliable delivery is
  not complete.
- Duplicate suppression on client is not a complete reliable-delivery system.

## Quality And Adaptation

Quality model types:

- `DeviceCapabilityTier`
- `NetworkQualityTier`
- `MediaQualityProfile`
- `ClientQualityReport`
- `ClientQualityTracker`
- `MediaQualitySelector`
- `UtilityBasedProfileSelector`

Device tiers:

- `legacy`
- `balanced`
- `modern`

Network tiers:

- `unknown`
- `excellent`
- `good`
- `weak`
- `critical`
- `offline`

Base profiles:

| Device tier | Profile id | Resolution | FPS | JPEG |
| --- | --- | --- | --- | --- |
| legacy | `legacy_480p` | 854x480 | 8 | 56 |
| balanced | `balanced_540p` | 960x540 | 10 | 60 |
| modern | `modern_720p` | 1280x720 | 12 | 66 |

Network adaptations:

| Tier | Result |
| --- | --- |
| excellent/good | base profile, `audioFirst=false` |
| weak | 640x360, 8fps, JPG 54, `audioFirst=true` |
| critical | 640x360, 5fps, JPG 48, `audioFirst=true` |
| offline | 426x240, 2fps, JPG 42, `audioFirst=true` |

Client-load adaptations:

- 2-3 active video clients cap profile near 480p/8fps.
- 4-5 active video clients cap profile near 360p/5fps.
- crowded sessions prefer audio-first.

Quality report flow:

```text
NetworkQualityMonitor
  -> GET /status for RTT/status
  -> ClientStreamHealthState.snapshot
  -> BatterySnapshotProvider.snapshot
  -> POST /quality/report
  -> ClientQualityReport.fromJson
  -> ActiveClientRegistry.updateQualityReport
  -> MediaQualitySelector.select
  -> optional server media profile change
```

Signals:

- RTT
- consecutive failures
- video frame gap
- audio gap
- skipped video frames
- skipped audio chunks
- WebSocket disconnects
- reconnect count
- stream timeout
- audio underrun
- recent reconnect
- active watch flag
- battery
- audio pipeline metrics
- server backpressure
- active client count

Upgrade/degrade behavior:

- degrade is fast when desired profile is lower quality
- upgrade is cooldown-gated
- recently reconnected clients block immediate upgrade
- one-step upgrade prevents jumping from survival to max too quickly

Important current limitation:

- There is no separate `MediaProfileController` class with Max/Ultra levels yet.
- Current selectors are `MediaQualitySelector` and `UtilityBasedProfileSelector`.
- Existing model is adaptive, but not the full Max/Ultra algorithm requested as
  future work.

## Backpressure

`StreamBackpressureGate<T>` is shared by video and audio stream services.

It tracks:

- skipped writes
- skipped video frames
- skipped audio chunks
- consecutive write failures
- last successful video write timestamp
- last successful audio write timestamp
- last write duration
- average write duration

`MjpegStreamService` uses it for frame write pressure.
`WavAudioStreamService` uses it for PCM write pressure.
`combineBackpressureMetrics` merges audio/video pressure into quality
selection.

Backpressure rules:

- if a client response is busy, the next payload for that response is skipped
- skip is metric, not queued work
- failed flush removes the client
- closing all clients has short timeouts to avoid hanging tests

## Battery And Transport Status

`BatterySnapshot` and `BatterySnapshotProvider` model:

- battery level
- charging state
- unknown fallback

Server status includes:

- server battery
- client battery if sent by quality report
- transport status
- stream health

Transport status currently reports:

- active transport: `wifi_lan`
- BLE discovery capability flag
- hotspot automation false
- media over BLE false

## Feature Control Services

`baby_monitor_feature_services.dart` contains three service families.

Comfort audio:

- `ComfortAudioTrack`
- `ComfortAudioService`
- built-in catalog metadata
- reducer actions: `play`, `pause`, `stop`, `setVolume`, `setPlaylist`

Night light:

- `NightLightController`
- reducer actions: `on`, `off`, `toggle`, `set`
- torch best-effort path
- `screenGlow` fallback state

Talk:

- `TalkSessionRegistry`
- short-lived talk token
- single active speaker
- busy response behavior
- audio byte ingest counter
- video byte ingest counter

Current limitation:

- comfort service does not yet play real audio through a server-side player
- talk audio bytes are counted but not rendered through native speaker output
- talk video bytes are counted but parent overlay is not complete

## UI Architecture

Shared UI:

- `MimiCamDesignTokens`
- `MimiCamRolePresentation`
- `MimiCamShells`
- localized measurement/media-profile helpers
- Material theme in `core/theme`
- text catalogs in `l10n`

Server UI:

```text
ServerAppShell
  -> ServerHomeScreen
  -> QR/IP tab
  -> stream/preview tab
  -> service status tab
  -> settings tab
```

Server UI surfaces:

- QR and manual IP pairing
- local preview
- full-screen preview
- video fit toggle
- broadcast access card
- runtime stats
- detection settings
- service status

Client UI:

```text
ClientAppShell
  -> ClientHomeScreen
  -> WatchScreen
  -> QR scanner
  -> manual pairing
  -> alert history
  -> settings
```

Client watch surfaces:

- live MJPEG video
- live PCM audio control
- full-screen watch
- video fit toggle
- night clock
- signal indicator
- battery/quality hints
- comfort/night-light/talk controls where wired
- broadcast access card

Responsive behavior is guarded by
`test/features/performance/screen_render_budget_test.dart`.

## Localization

`AppStrings` owns localization lookup.

Text source files:

- `lib/l10n/src/app_ui_text_catalog.dart`
- `lib/l10n/src/app_ui_text_catalog_extra.dart`

Supported locales are declared by `AppStrings.supportedLocales`. UI should use
localized keys instead of hard-coded user-visible strings except for protocol,
debug, or developer-only values.

## Status Surfaces

`/status/public`:

- only available in pairing mode
- returns pairing service descriptor
- includes nonce and capabilities
- does not return trusted token

`/status`:

- private Bearer route
- returns runtime state for paired clients
- includes media profile and health values

`/test/status`:

- private Bearer route except debug dashboard access rules for `/test`
- returns detailed diagnostics
- exposes audio/video/event/client/battery/transport/feature state
- intended for proof and support debugging

Audio fields in `/test/status` include both server-side capture and client-side
pipeline reports when quality report has supplied them.

## Test Dashboard And `/test/*`

Dashboard assets:

- `assets/test_dashboard/index.html`
- `assets/test_dashboard/dashboard.js`
- served by `TestDashboardAssets`

Diagnostic endpoints:

| Route | Purpose |
| --- | --- |
| `/test` | Browser dashboard |
| `/test/dashboard.js` | Browser test script |
| `/test/status` | Full diagnostics JSON |
| `/test/start` | Start media runtime |
| `/test/reset` | Reset streams, test counters and diagnostics |
| `/test/probe` | End-to-end media/event loopback |
| `/test/alert` | Synthetic WebSocket alert |
| `/test/audio-tone` | Deterministic WAV tone |

`/test/probe` behavior:

```text
read JSON body
  -> optionally start runtime
  -> optionally emit test alert
  -> wait for video/audio/event counters
  -> optionally create loopback session
  -> read /video first MJPEG payload
  -> read /audio WAV header + PCM payload
  -> return checks, video, audio, alerts, profile, diagnostics
```

Audio probe modes:

- `audioMode: "microphone"` or default: uses current runtime audio source
- `useAudioTone: true` or `audioMode: "tone"`: pushes deterministic PCM into
  the `/audio` stream path without microphone permission

`/test/audio-tone` behavior:

- produces deterministic sine PCM
- wraps it in a WAV header
- returns finite `audio/wav` response
- proves parser/header path independent of microphone capture

Proof criteria for audio:

- WAV header valid
- PCM bytes received after header
- client parser emits PCM chunk
- native PCM sink write is attempted
- native bytes written are visible in client metrics where a real client report
  is present

## End-To-End Media Seams

The strongest non-device media tests use:

- `DeterministicServerMediaSource`
- real `MimiCamServer`
- real `/session/start`
- real `/video`
- real `/audio`
- real `MjpegStreamParser`
- real `WavPcmStreamParser`
- first-payload force-close teardown

This proves runtime wiring without relying on camera/microphone hardware in CI.

## Platform Services

`services/platform/` contains:

- `BatterySnapshotProvider`
- `DeviceCapabilityProbe`
- `ForegroundServiceController`

Platform/native paths:

- Android foreground service bridge keeps server runtime visible.
- Android PCM playback uses `AudioTrack`.
- iOS PCM playback uses `AVAudioEngine` and `AVAudioPlayerNode`.
- iOS camera permission handling has a native camera permission channel.

iOS builds require macOS/Xcode. Linux can run Flutter analysis, Dart tests and
Android debug builds.

## Configuration

`ConfigurationService` reads and writes runtime thresholds in
`SharedPreferences`.

Important settings:

- motion threshold
- cry score threshold
- notification cooldown
- minimum motion duration
- minimum cry duration

Server settings screen updates `ConfigurationService`, then calls
`MimiCamServer.reloadAnalysisConfig` through `ServerRuntime`.

## Security Boundaries

Current protections:

- local network guard
- nonce-based pairing
- trusted token hashing
- secure client token storage
- short-lived media stream tokens
- stream tokens rejected by control endpoints
- test dashboard is debug-open but otherwise protected
- pair confirm rate limiting
- nonce pruning

Known security limits:

- HTTP/WS is plaintext on local network
- no HTTPS/WSS
- no certificate pinning
- no cloud identity/account system
- local network attackers are not fully mitigated

Those limits are product/security decisions, not accidental omissions.

## Error Handling And Cleanup

General rules:

- dispose runtimes on role switch
- cancel stream subscriptions
- force-close long-lived media test clients after first payload
- close HTTP responses on error paths
- reset diagnostics during `/test/reset`
- keep media start best-effort for audio
- stop runtime when no active demand remains

Important cleanup owners:

- `AppBootstrap`: role runtime disposal
- `ServerRuntime`: UI/runtime resource demand cleanup
- `MimiCamServer`: HTTP server, media runtime, stream clients
- `MjpegStreamService`: video responses
- `WavAudioStreamService`: audio responses
- `ClientRuntime`: network subscription and watch state
- `ClientMediaStreamSupervisor`: video client and audio pipeline
- `ClientAlertListener`: WebSocket and reconnect timer
- `BroadcastAccessService`: purchase stream subscription

## Testing Strategy

Core gate:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

High-value runtime suites:

```bash
flutter test test/features/server/media_stream_end_to_end_test.dart
flutter test test/features/server/test_endpoints_test.dart
flutter test test/features/client/client_live_audio_pipeline_test.dart
flutter test test/features/client/client_media_stream_supervisor_test.dart
flutter test test/features/client/network_quality_monitor_test.dart
flutter test test/features/client/client_runtime_lifecycle_test.dart
flutter test test/features/server/feature_control_endpoints_test.dart
flutter test test/features/performance/screen_render_budget_test.dart
```

Audio-specific proof:

```bash
flutter test test/features/server/test_endpoints_test.dart --plain-name "/test/audio-tone"
flutter test test/features/server/media_stream_end_to_end_test.dart --plain-name "/test/probe audio-tone"
flutter test test/features/server/media_stream_end_to_end_test.dart --plain-name "/test/probe loopback video ve audio"
flutter test test/features/server/test_endpoints_test.dart --plain-name "/test/status client audio pipeline"
```

What these tests prove:

- `/test/audio-tone` returns valid WAV + PCM
- `/test/probe` can verify audio without microphone via tone mode
- `/test/probe` can verify real `/audio` stream path with deterministic source
- `/test/status` can expose client audio pipeline metrics
- full media endpoint tests use real HTTP server and parsers

## Release And Store Notes

Before shipping paid unlock:

1. Configure non-consumable product `mimicam_lifetime_unlock_try_300`.
2. Set product price to 300 TL or matching local tier.
3. Test purchase and restore on sandbox accounts.
4. Confirm unavailable store state is user-visible.
5. Confirm unlock persists across app restarts.

Before shipping iOS:

1. Build on macOS or macOS CI.
2. Check camera, microphone, local network and notification permissions.
3. Check native PCM playback.
4. Check QR scan permission fallback.
5. Check purchase/restore on sandbox.

Before marketing Bluetooth:

1. Do not claim direct Bluetooth media.
2. Only claim local network/hotspot HTTP/WS media.
3. BLE discovery/control must be implemented and real-device verified first.

## Architecture Change Rules

When adding a new feature:

1. Decide which runtime owns it: Server, Client, shared protocol or platform.
2. Add typed model/DTO where data crosses a boundary.
3. Preserve existing endpoint behavior unless intentionally versioned.
4. Keep stream tokens limited to media endpoints.
5. Add runtime-visible diagnostics for media and alert behavior.
6. Add focused tests before broad tests.
7. Update this file when the shipped architecture changes.

When touching media:

1. Protect audio first.
2. Keep latest-frame/latest-chunk behavior bounded.
3. Do not introduce unbounded queues.
4. Verify `/audio` with WAV header + PCM bytes.
5. Verify `/video` with a real MJPEG payload.
6. Verify `/test/probe` after endpoint changes.
7. Run Android debug build if native PCM or plugin paths changed.

When touching docs:

1. Read `lib/` first.
2. Treat README as product/runtime summary.
3. Treat this file as implementation architecture.
4. Treat `docs/kotlin_to_flutter_porting_matrix.md` as migration ledger.
5. Do not resurrect old Kotlin/cloud/UDP/WebRTC assumptions unless code exists.

## Future Work Boundaries

Do not mark these as complete until they have runtime implementation, wire
contract, UI integration, diagnostics and tests:

- Max/Ultra `MediaProfileController`
- alert ACK/retry protocol
- duplicate event suppression and reliable critical delivery
- production BLE discovery/control
- native comfort audio playback
- real two-way talk playback
- parent video overlay on server
- cloud relay
- account system
- HTTPS/WSS
- WebRTC/H.264/Opus

The safe rule is simple: if `/test/status`, `/test/probe` or focused tests
cannot prove it, it should not be documented as shipped behavior.
