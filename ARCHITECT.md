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
sinirsiz erisim, Apple Watch, HTTPS/WSS ve dogrudan Bluetooth video/ses tasima
bu mimarinin aktif parcasi degildir. Varsayilan media yolu MJPEG/WAV'dir;
WebRTC H.264 + Opus ise capability probe ile acilan, tek peer'li ve otomatik
MJPEG/WAV fallback'i olan opt-in bir pilot olarak bulunur.

## Architectural Truths

1. **Tek app, tek aktif rol.** `Server` ve `Client` runtime grafikleri ayni
   process icinde tanimli olsa da ayni anda sadece biri mount edilir.
2. **Local-first transport.** Kontrol ve signaling HTTP, alert/event WebSocket
   uzerinden akar. Media varsayilan olarak HTTP MJPEG/WAV, pilotta WebRTC'dir.
3. **Pairing once, private access sonra.** Pairing olmadan private route'lara
   erisilmez. Server trusted-client kayitlarini yalniz token hash'i ve metadata
   olarak kalici tutar; nonce ve stream token restart ile tasinmaz.
4. **Trusted token ve stream token farklidir.** Trusted Bearer token state
   degistiren endpointler icindir. Stream token legacy `/video` ve `/audio`
   attach icin zorunludur; WebRTC signaling'de ayni Bearer client'a ait peer'i
   baglamak icin Bearer ile birlikte kullanilir.
5. **Media backpressure bounded kalir.** Slow client icin eski frame/chunk
   biriktirilmez; skip ve failure metric yazilir.
6. **Ses ve kritik alert video kalitesinden onceliklidir.** Ag kotulesirse
   video profili dusurulur; audio ve alert delivery korunmaya calisilir.
7. **Runtime diagnostics urun davranisinin parcasidir.** `/test/status`,
   `/test/probe` ve `/test/audio-tone` gercek endpoint davranisini kanitlar;
   session telemetry p50/p95/p99 dagilimlari ve bounded counter'lar tasir.
8. **Ucretli erisim UI'dan ibaret degildir.** 2 saat ucretsiz yayin/izleme
   siniri hem Client runtime hem Server `/session/start` katmaninda uygulanir.
9. **Media hardware demand'e aittir.** Kamera ve mikrofon birbirinden bagimsiz,
   serialized demand transition'lariyla edinilir ve birakilir.
10. **Platform background sozlesmesi aciktir.** Android aktif process icinde
    foreground service mevcut engine'i sahiplenir; iOS background camera iddia
    etmez, media'yi kontrollu durdurup foreground'da talebi geri yukler.
11. **Docs shipped code'u anlatir.** Bitmemis ozellikler "destekleniyor" diye
   yazilmaz; partial veya out-of-scope olarak ayrilir.

## Current Transport Matrix

| Concern | Current runtime |
| --- | --- |
| Control transport | HTTP |
| Media transport | Default HTTP MJPEG/WAV; opt-in one-peer WebRTC pilot |
| Event transport | WebSocket |
| QR transport id | `http_ws` |
| Video codec | MJPEG fallback; H.264 pilot |
| Audio codec | PCM16LE/WAV fallback; Opus pilot |
| Signaling | Authenticated local HTTP `/webrtc/*` |
| Discovery | DNS-SD/NSD `_mimicam._tcp`, QR and manual IP fallbacks |
| Addressing | IPv6 dual-stack bind attempt, IPv4 fallback |
| Alert payload | JSON DTO |
| Private auth | Trusted Bearer token |
| Media auth | Short-lived stream token; Bearer alone cannot open media |
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
- direct Bluetooth media
- automatic hotspot creation
- WebRTC relay/TURN or internet NAT traversal
- parent talk video overlay

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
| `crypto` | Purchase evidence fingerprinting |
| `flutter_webrtc` | Opt-in H.264 + Opus local-LAN pilot |
| `nsd` | Bonjour/NSD advertise, browse and resolve |
| `just_audio` | Retained audio dependency; comfort currently uses generated PCM |
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
  -> SharedPreferencesTrustedClientRepository
  -> PairingTokenService
  -> BroadcastAccessService
  -> FlutterWebRtcServerGateway
  -> MimiCamServiceAdvertiser
  -> MimiCamServer
  -> ServerQrPayloadBuilder
  -> MediaRuntimeController
  -> PlatformMediaLifecycleCoordinator
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
  -> StreamSessionController + FlutterWebRtcClientConnector
  -> NetworkQualityMonitor
  -> ClientAlertHistory
  -> BroadcastAccessService
  -> ClientRoomControls
  -> MimiCamServiceBrowser
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
`MediaRuntimeController` then serializes independent video/audio acquisition and
release. A platform pause first reconciles demand to `none`; recovery replays
the retained requested demand, so lifecycle events cannot race a late hardware
start.

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
  -> ActiveStreamSession(streamToken, mediaTransport)
  -> WebRTC capability/negotiation if advertised
  -> RTCVideoView + native WebRTC audio on success
  -> otherwise a fresh MJPEG/WAV fallback session
  -> WatchScreen mounts ClientMediaStreamSupervisor for fallback
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
| `webRtcOffer` | `/webrtc/offer` |
| `webRtcIce` | `/webrtc/ice` |
| `webRtcClose` | `/webrtc/close` |
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
- WebRTC pilot signaling gateway
- media stream attach/detach
- quality report ingestion
- status and diagnostics JSON
- delegation of comfort/night-light/talk device work to
  `BabyMonitorFeatureController`
- DNS-SD advertiser lifecycle
- alert broadcast

The class is still the HTTP composition boundary, but device/business work no
longer all lives in one implementation body:

- diagnostics handlers are in the `MimiCamServerTestEndpoints` part extension
- comfort/night-light/talk delegate to `BabyMonitorFeatureController`
- native comfort/talk output delegates to `RoomAudioCoordinator`
- WebRTC peer/media ownership delegates to `WebRtcServerGateway`
- MJPEG/WAV response ownership remains in their stream services
- demand reconciliation remains in `ServerRuntime` + `MediaRuntimeController`
- thermal/power decisions delegate to `MediaResourceGovernor`

This is incremental decomposition, not a claim that the 2,000+ line route host
has been fully split into independent controllers.

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
| `none` | Router does not pre-authenticate; handler may validate nonce or a dedicated talk token |
| `bearer` | Requires trusted `Authorization: Bearer <token>` |
| `streamToken` | Requires a valid short-lived media stream token |
| `testAccess` | Debug mode open; otherwise trusted Bearer token required |

Stream tokens open legacy `/video` and `/audio`; pilot `/webrtc/*` routes also
require the same token in addition to trusted Bearer identity. Other
state-changing routes cannot be authorized by a stream token alone.

## Route Table

| Route | Method | Auth mode | Owner behavior |
| --- | --- | --- | --- |
| `/status/public` | GET | none | Pairing-only public descriptor |
| `/pair/confirm` | POST | none | Nonce validation and trusted token issue |
| `/auth/renew` | POST | handler validates Bearer | Trusted token renewal |
| `/session/start` | POST | bearer | Paywall, active slot, stream token |
| `/session/stop` | POST | bearer | Active session cleanup |
| `/quality/report` | POST | bearer | Client quality/battery/audio metrics |
| `/status` | GET | bearer | Private server runtime status |
| `/video` | GET | streamToken | MJPEG stream attach |
| `/audio` | GET | streamToken | WAV/PCM stream attach |
| `/webrtc/offer` | POST | bearer + streamToken | Pilot offer/answer and peer creation |
| `/webrtc/ice` | GET/POST | bearer + streamToken | Drain/send pilot ICE candidates |
| `/webrtc/close` | POST | bearer + streamToken | Idempotent peer cleanup |
| `/ws/events` | WebSocket GET | trusted token | JSON alert socket |
| `/comfort/state` | GET | bearer | Comfort state JSON |
| `/comfort/command` | POST | bearer | Comfort state plus generated native PCM playback |
| `/night-light/state` | GET | bearer | Night light state JSON |
| `/night-light/command` | POST | bearer | Night light reducer command |
| `/talk/start` | POST | bearer | Short talk token and busy check |
| `/talk/stop` | POST | bearer | Stop active talk session |
| `/talk/audio` | POST | talk token in query/header | PCM ingest and native room playback |
| `/talk/video` | POST | talk token in query/header | Compatibility ingest; video output unsupported |
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

DNS-SD/NSD discovery:

```text
MimiCamServer.startPairingMode
  -> IPv6 dual-stack bind attempt, IPv4 fallback
  -> MimiCamServiceAdvertiser registers _mimicam._tcp
  -> TXT: id, protocol version, WebRTC availability, http_ws transport

ClientCompositionRoot
  -> MimiCamServiceBrowser.start
  -> auto-resolve with IPv4/IPv6 lookup
  -> discovered room card
  -> existing /status/public + pairing flow
```

Discovery is an optional address acquisition path. Failure is caught and QR or
manual address pairing remains available. The advertiser is active only while
pairing mode is active.

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

Purchase verification flow:

```text
in_app_purchase PurchaseDetails
  -> exact product id check
  -> app_store/google_play source check
  -> purchased/restored state check
  -> non-empty local + server verification envelope check
  -> SHA-256 evidence fingerprint
  -> completePurchase
  -> persist verified source/fingerprint/time + entitlement
```

Verification fails closed: an unverified purchase/restore cannot unlock or
persist entitlement, and raw receipt/token data is not stored. This verifier
checks the store-originated envelope locally; it does not contact Apple or
Google to prove receipt authenticity. Production fraud resistance still needs
a replaceable server-side verifier. Play Console/App Store Connect must also
define the non-consumable product separately.

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

`MimiCamServer` exposes independent `startVideoRuntime` / `stopVideoRuntime` and
`startAudioRuntime` / `stopAudioRuntime` boundaries. `startMediaRuntime` remains
as a compatibility convenience that requests both. There are two source modes:

1. **Injected media source branch:** used by tests with `ServerMediaSource`.
2. **Hardware branch:** uses camera and microphone plugins.

Demand-owned hardware branch:

```text
ServerRuntime folds watch/preview/analyzer demand
  -> MediaRuntimeController.reconcile(video, audio)
  -> stop no-longer-demanded resource first
  -> start only newly-demanded resource
  -> publish exact camera/microphone demand to native platform contract

video demand
  -> camera permission + CameraController image stream

audio demand
  -> MicrophoneCaptureService + audio analysis/stream

any media demand
  -> wakelock + Android foreground-service update
```

The transition queue is serialized. A stop arriving during a plugin start waits
for that start and then deterministically releases it. Video-only and audio-only
sessions therefore avoid lighting the unrelated privacy indicator.

Stop branch:

```text
stopMediaRuntime
  -> stop injected media source if any
  -> stop camera and microphone independently
  -> cancel alert subscription
  -> dispose analysis coordinator
  -> close video clients
  -> close audio clients
  -> stop foreground service and wakelock when final demand ends
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

WebRTC pilot uses a separate hardware owner inside
`FlutterWebRtcServerGateway`: after an H.264/Opus capability probe it acquires
requested `getUserMedia` tracks for one peer. The matching `/session/start`
records logical video/audio demand as external capture ownership: legacy plugin
capture is suspended, combined demand remains visible to the Android service,
and platform pause closes pilot peer tracks. Peer/session close disposes tracks,
releases the suspension and restores retained legacy/analyzer demand. If the
pilot cannot start, the client stops that session before opening a new
MJPEG/WAV fallback session.

## Video Pipeline

Server path:

```text
CameraImage
  -> device-tier capture FPS ceiling / active-profile frame pacing
  -> MediaFramePolicy / FrameRateGate
  -> capacity-one encoder mailbox
  -> persistent CameraImageJpegEncoder worker isolate
  -> latest JPEG cache
  -> sequence/capture/send metadata
  -> per-client capacity-one MjpegStreamService mailbox
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
  -> sequence gap + relative queue delay + RFC jitter
  -> newest complete frame only
  -> onVideoFrame(Uint8List)
  -> WatchScreen / ClientVideoViewer
```

`MjpegStreamService` owns:

- connected `HttpResponse` set
- response-to-client id mapping
- first frame delivery
- busy-client latest-frame mailbox
- skip/failure metrics
- detach callback
- diagnostics snapshot
- close/reset behavior

Video invariants:

- no unbounded per-client frame queue
- slow client skips instead of blocking all clients
- encoder and client decoder prefer current frame age over complete history
- iOS NV12/BGRA row and pixel stride are decoded explicitly
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
  -> 20 ms PcmAudioFramePacketizer
  -> per-client bounded 160 ms queue / detach on overflow or flush timeout
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
  -> RFC 3550-style adaptive 60-220 ms playout target
  -> native 80-100 ms high-water occupancy pump
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
- server frame duration is 20 ms (640 bytes at 16 kHz mono PCM16)
- server queue is capped at 160 ms; overflow detaches the slow stream so it
  reconnects instead of hiding a gap inside raw WAV PCM
- client Dart buffer is capped at 320 ms

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
- `bufferedAudioMs`
- `jitterBufferedBytes`
- `droppedBufferBytes`
- `jitterDroppedBytes`
- `droppedBufferFrames`
- `estimatedJitterMs`
- `targetPlayoutDelayMs`
- `playoutStarts`
- `playoutUnderruns`
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
- `AudioFocusRequest` / legacy focus request as API requires
- pause on transient/permanent focus loss and `ACTION_AUDIO_BECOMING_NOISY`
- resume on focus gain
- audio-device add/remove observation
- pending write guard
- write accepted/drop counters
- bytes written counter
- underrun count where API supports it
- play state/track state status

iOS implementation:

- `AVAudioEngine`
- `AVAudioPlayerNode`
- `AVAudioPCMBuffer`
- `AVAudioSession` interruption and route-change observation
- media-services reset recovery
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

Device resource governor:

```text
mimicam/device_resources snapshot
  -> thermal state + low-power + charging + battery
  -> network tier + transport backpressure
  -> encode p95 + pre-encode drop ratio
  -> decoder coalescing + audio underruns + active clients
  -> normal / constrained / survival / audioOnly
  -> cap effective MediaQualityProfile
```

Critical pressure is audio-first when audio demand exists; legacy video keeps a
1 fps liveness frame rather than tearing the TCP stream down. Degrade is
immediate, while existing selector hysteresis controls upgrade.

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

## End-To-End Session Telemetry

`MediaSessionTelemetry` uses a process-monotonic clock for same-device spans and
a bounded 1,024-sample window per duration metric. Snapshot calculation exposes
count, sample count, min/max/average and p50/p95/p99 without sorting in the hot
path.

Instrumented signals include:

- video capture, capture-to-encode, encode, send, receive/decode/present spans
- audio capture, send, native output write and startup-to-playout spans
- captured/encoded/pre-encode-drop/transport-skip counters
- decoder coalescing, audio underrun and reconnect counters

MJPEG multipart metadata carries trace/sequence and capture/send timestamps for
cross-device receive estimates. `/test/status` publishes `sessionTelemetry`;
the sample bound prevents a long-running monitor from growing telemetry memory.

## Battery And Transport Status

`BatterySnapshot` and `BatterySnapshotProvider` model client/server battery
reporting. `DeviceResourceSnapshotProvider` separately models:

- thermal state
- low-power mode
- charging state and battery level
- 10-second cached/in-flight-coalesced platform snapshots

Server status includes:

- server battery
- client battery if sent by quality report
- transport status
- stream health
- device resources and resource-governor decision
- bounded session telemetry

Transport status currently reports:

- active transport: `wifi_lan`
- DNS-SD advertising state
- IPv6 capability/bind state
- BLE discovery false
- hotspot automation false
- media over BLE false

## Feature Control Services

`BabyMonitorFeatureController` is the facade between HTTP routing and room-side
feature devices. `baby_monitor_feature_services.dart` contains state/session
services; `RoomAudioCoordinator` owns serialized native audio output.

Comfort audio:

- `ComfortAudioTrack`
- `ComfortAudioService`
- built-in catalog metadata
- procedural 16 kHz PCM generation for white noise, pink noise, rain and soft
  lullaby
- reducer actions: `play`, `pause`, `stop`, `setVolume`, `setPlaylist`
- native `PcmAudioOutput` playback and output diagnostics

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
- parent microphone capture through `ClientRoomControls`
- long-lived PCM upload and native room-speaker playback
- talk preempts comfort output; comfort resumes after talk
- video byte ingest counter

Current limitation:

- built-in comfort sounds are procedural, not mastered audio assets
- talk is PCM audio only; talk-video ingest is compatibility state and parent
  overlay is not implemented
- physical-device echo/feedback and route behavior still require the release
  matrix

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
  -> DNS-SD discovered room list
  -> alert history
  -> settings
```

Client watch surfaces:

- live WebRTC or MJPEG video
- live WebRTC or PCM/WAV audio control
- full-screen watch
- video fit toggle
- night clock
- signal indicator
- battery/quality hints
- comfort track/volume controls and night-light controls
- press-and-hold parent-to-room PCM talk
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
- exposes `sessionTelemetry`, `deviceResources`, `resourceGovernor` and room
  audio output status
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
- `DeviceResourceSnapshotProvider`
- `ForegroundServiceController`
- `PlatformRuntimeContract`
- `PlatformMediaLifecycleCoordinator`
- `PcmAudioOutput`

Platform/native paths:

- Android caches the existing Flutter engine and lets
  `MimiCamForegroundService` claim it while media demand is active.
- Android service notification and Wi-Fi lock reflect exact camera/microphone
  demand. The service is `START_NOT_STICKY`; process death requires a visible
  user restart and does not fabricate recovered capture.
- iOS `SceneDelegate` publishes foreground/inactive/background transitions.
  Background emits `mediaPauseRequired`; foreground-active emits
  `mediaRecoveryRequested`. `ServerRuntime` serially suspends/replays demand.
- iOS explicitly reports `supportsCameraInBackground=false`.
- Android PCM uses `AudioTrack` with audio focus/noisy/device-route events.
- iOS PCM uses `AVAudioEngine`/`AVAudioPlayerNode` with interruption, route and
  media-services-reset handling.
- Both platforms expose thermal/low-power/charging/battery snapshots through
  `mimicam/device_resources`.
- iOS camera/local-network permission channels remain explicit.

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
- `webRtcPilotEnabled`, defaulting to
  `--dart-define=MIMICAM_WEBRTC_PILOT=true` only when no stored override exists

Server settings screen updates `ConfigurationService`, then calls
`MimiCamServer.reloadAnalysisConfig` through `ServerRuntime`.

The WebRTC pilot is off by default. A build can opt in with
`--dart-define=MIMICAM_WEBRTC_PILOT=true`; a persisted
`config.webrtc_pilot_enabled` value overrides the build default. Pairing mode
initializes the gateway and advertises WebRTC only when both H.264 and Opus
capability probes succeed.

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
- public pairing-nonce redesign is intentionally not part of this work
- JSON request bodies do not yet share one central byte limit
- socket lease/revoke and secure session-ticket designs are intentionally not
  implemented

The public nonce/body-limit/socket-lease/session-ticket bundle was explicitly
excluded for the local-LAN scope. This is a recorded scope decision, not a
claim that the risks do not exist.

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
- `BabyMonitorFeatureController`: comfort/night-light/talk facade
- `RoomAudioCoordinator`: exclusive comfort/talk native PCM output
- `FlutterWebRtcServerGateway`: pilot peer/tracks
- `MimiCamServiceAdvertiser` / `MimiCamServiceBrowser`: discovery lifecycle
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
flutter test test/features/server/media_runtime_controller_test.dart
flutter test test/services/platform/platform_runtime_contract_test.dart
flutter test test/services/server/media_resource_governor_test.dart
flutter test test/core/media/media_session_telemetry_test.dart
flutter test test/features/server/webrtc_signaling_endpoints_test.dart
flutter test test/features/client/stream_session_controller_test.dart
flutter test test/services/discovery/mimicam_service_discovery_test.dart
flutter test test/services/server/room_audio_coordinator_test.dart
flutter test test/features/client/client_room_controls_test.dart
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
- pilot tests prove signaling auth/session ownership and automatic fallback;
  they do not prove physical codec/ICE behavior
- platform contract tests prove serialized pause/recovery policy; simulators do
  not prove background camera/audio-focus behavior

Physical release evidence is defined in
`docs/physical_device_test_matrix.md`. `tool/benchmarks/device_soak_harness.dart`
records `/test/status` JSONL, but the matrix is not complete until the named
physical device/network lanes have produced archived results.

## Release And Store Notes

Before shipping paid unlock:

1. Configure non-consumable product `mimicam_lifetime_unlock_try_300`.
2. Set product price to 300 TL or matching local tier.
3. Test purchase and restore on sandbox accounts.
4. Confirm unavailable store state is user-visible.
5. Confirm unverified purchase/restore fails closed.
6. Replace or back `StorePayloadPurchaseVerifier` with Apple/Google server-side
   verification for fraud-resistant production entitlement.
7. Confirm unlock persists across app restarts.

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
5. Do not resurrect old Kotlin/cloud/UDP assumptions unless code exists; keep
   the WebRTC path described as an opt-in pilot until physical evidence exists.

## Future Work Boundaries

Do not mark these as complete until they have runtime implementation, wire
contract, UI integration, diagnostics and tests:

- Max/Ultra `MediaProfileController`
- alert ACK/retry protocol
- duplicate event suppression and reliable critical delivery
- production BLE discovery/control
- parent video overlay on server
- mastered comfort-audio assets and echo-controlled talk productization
- cloud relay
- account system
- HTTPS/WSS
- multi-peer WebRTC, TURN/relay and production NAT traversal
- release-grade Apple/Google server-side purchase verification
- completed physical-device matrix evidence

The safe rule is simple: if `/test/status`, `/test/probe` or focused tests
cannot prove it, it should not be documented as shipped behavior.
