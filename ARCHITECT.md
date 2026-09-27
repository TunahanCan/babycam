# MiuCam Architecture

Bu dokuman MiuCam Flutter uygulamasinin mevcut mimari gercegini anlatir.
Kaynak kodun asil sahibi `lib/` agacidir; test davranisinin asil sahibi
`test/` agacidir. Bu dosya, eski Kotlin planlarini veya pazarlama hedeflerini
degil, bu repodaki calisan Flutter uygulamasini tarif eder.

MiuCam tek Flutter uygulamasi icinde iki rol tasir:

- **Server:** Bebek odasindaki cihazdir. Kamera, mikrofon, analiz, alert
  uretimi, HTTP media server, WebSocket event server ve runtime diagnostics
  burada calisir.
- **Client:** Ebeveyn cihazidir. Pairing yapar, video izler, PCM sesi native
  cikisa yazar, alert dinler, local notification uretir ve server'a kalite
  raporu gonderir.

Aktif medya runtime modeli local-first'tur. Bulut relay, hesap sistemi, internetten
sinirsiz erisim, Apple Watch, yerel medya icin HTTPS/WSS ve dogrudan Bluetooth video/ses tasima
bu mimarinin aktif parcasi degildir. Varsayilan media yolu MJPEG/WAV'dir;
WebRTC H.264 + Opus ise capability probe ile acilan, tek peer'li ve otomatik
MJPEG/WAV fallback'i olan opt-in bir pilot olarak bulunur.
Satin alma dogrulamasi ayri HTTPS backend'ine gider; medya bu backend'den gecmez.
Yeni ozelliklerin gercek kod sinirlari ve testleri icin
[mimari genisletme rehberine](docs/architecture_extension_guide.md) bakin.

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
7. **Dogrulama production yollarini kullanir.** Test-only HTTP rotasi yoktur;
   `/session/start`, `/video`, `/audio`, `/ws/events` ve authenticated `/status`
   senaryo testlerinde dogrudan calistirilir.
8. **Ucretli erisim UI'dan ibaret degildir.** 2 saatlik yayin hakkinin otoritesi
   oda sunucusudur. Server medya/alert girislerini ve sure bitimini uygular;
   Client runtime oda snapshot'ini kullanir, ayri ebeveyn denemesi saymaz.
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
| Discovery | DNS-SD/NSD `_miucam._tcp`, QR and manual IP fallbacks |
| Addressing | IPv6 dual-stack bind attempt, IPv4 fallback |
| Alert payload | JSON DTO |
| Private auth | Trusted Bearer token |
| Media auth | Short-lived stream token; Bearer alone cannot open media |
| Test surface | Runtime test-only HTTP route yok; production routes are exercised directly |
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

Pubspec'te Bluetooth paketi yoktur. Media local IP network veya
kullanicinin/OS'in olusturdugu hotspot network uzerinden HTTP/WS ile akar.

## Dependency Map

Runtime acisindan onemli dependency'ler:

| Package | Ownership |
| --- | --- |
| `camera`, `camera_platform_interface` | Plugin camera path, preview and injectable platform tests; Android default capture uses the native service bridge |
| `record` | Plugin microphone PCM16 path; Android default capture uses native AudioRecord |
| `image` | Camera image to JPEG encoding support |
| `flutter_local_notifications` | Client local notification |
| `shared_preferences` | Role, config, alert history, child metadata, paid usage |
| `flutter_secure_storage` | Trusted token storage |
| `qr_flutter` | Server QR rendering |
| `mobile_scanner` | Client QR scanning |
| `permission_handler` | Permission coordination |
| `wakelock_plus` | Server runtime keep-awake |
| `battery_plus` | Battery snapshots |
| `in_app_purchase` | One-time unlock purchase/restore |
| `in_app_purchase_android`, `in_app_purchase_platform_interface` | Silent owned-purchase queries and Android acknowledgement result handling |
| `in_app_purchase_storekit` | StoreKit 2 transaction recovery and explicit account sync; pinned to `0.4.10+1` |
| `crypto` | Purchase evidence fingerprinting |
| `cryptography` | Offline Ed25519 family-license verification |
| `flutter_webrtc` | Opt-in H.264 + Opus local-LAN pilot |
| `nsd` | Bonjour/NSD advertise, browse and resolve |

HTTP/WebSocket transport uses `dart:io`. Native PCM output uses the app's
`PcmAudioOutput` platform adapter. `web_socket_channel`, `just_audio` and
`bluetooth_low_energy` are not dependencies in the current `pubspec.yaml`.

Flutter assets:

- `assets/branding/miucam_launcher_icon.png`
- `assets/branding/miucam_bear_mascot.png`
- `assets/branding/miucam_wordmark.png`
- `assets/branding/miucam_wordmark_v2.png`
- `assets/branding/miucam_wordmark_v3.png`

## Source Tree Ownership

```text
lib/
├── main.dart
├── app/
│   ├── app_bootstrap.dart
│   ├── broadcast_purchase_composition_root.dart
│   ├── broadcast_purchase_coordinator.dart
│   ├── app_lifecycle_observer.dart
│   ├── app_role.dart
│   ├── miucam_app.dart
│   ├── role_permission_coordinator.dart
│   ├── role_repository.dart
│   └── role_resolver.dart
├── analysis/
│   ├── alert/
│   ├── audio/
│   └── video/
├── core/
│   ├── alerts/
│   ├── bytes/
│   ├── media/
│   ├── network/
│   ├── protocol/
│   ├── security/
│   ├── settings/
│   └── theme/
├── features/
│   ├── client/
│   ├── role_selection/
│   ├── server/
│   └── shared/
├── l10n/
└── services/
    ├── miucam_server.dart
    ├── discovery/
    ├── monetization/
    ├── platform/
    └── server/
```

Package ownership:

- `app/`: App bootstrap, role resolution, role switching, permission entry and
  application-lifetime purchase coordination.
- `analysis/`: Pure-ish motion/audio/alert scoring logic.
- `core/`: DTOs, protocol constants, security helpers, theme, transport values.
- `features/client/`: Client UI, Client runtime, pairing, media receive path,
  alert receive path.
- `features/server/`: Server UI, Server runtime facade, pairing QR builder,
  stream services near UI/runtime boundaries.
- `services/`: HTTP server, platform facades, monetization, media-quality
  selectors and backpressure utilities.
- `backend/miucam_billing/`: Store adapters, purchase reconciliation, signed
  licenses and durable SQLite records. It is separate from the LAN media server.

## Shared Policy And Value Ownership

Shared values live with the domain that gives them meaning. UI layout values,
algorithm tuning, transport formats and persistence keys have separate owners.

| Concern | Owner | Used by |
| --- | --- | --- |
| User detection defaults, bounds and presets | `core/settings/detection_settings.dart` | `ConfigurationService`, server settings UI, analysis composition |
| Alert type, category, severity and message identifiers | `core/alerts/` | Analysis, protocol adapter, DTO interpretation, client presentation and native notification policy |
| PCM byte layout and live audio defaults | `core/media/pcm_audio_format.dart` | WAV header/parser, microphone, packetizer, playback and talkback |
| Episode intensity and message classification | `analysis/alert/episode_notification_policy.dart` | Episode aggregator, notification composer, protocol adapter |

`DetectionPreset` contains values, while its UI extension owns translated labels
and icons. `ConfigurationService.setDetectionSettings` owns persistence; screens
do not duplicate the sequence of preference writes. Settings use milliseconds
throughout the model and storage, converting to seconds only for presentation.
Low-level `AudioAnalysisConfig` and `MotionAnalysisConfig` remain separate from
these user-facing product presets.

`PcmAudioFormat` describes sample rate, channels and bit depth and owns byte/time
conversion and sample-frame alignment. Live transport packet duration is not the
comfort-synthesis interval, jitter target or retry delay. Native Kotlin/Swift
defaults still belong to their platform contracts; changing the Dart default
alone does not migrate those contracts or add codec support.

Alert enums serialize through explicit `wireValue` identifiers. Renaming a Dart
enum member must not rename stored history or peer JSON. DTOs retain unknown raw
values for forward compatibility and apply typed interpretation for known values.
The old `analysis/alert/alert_type.dart` and `alert_severity.dart` paths re-export
the shared definitions so existing imports keep the same enum identity.

`BabyEventEpisode`/state, `EpisodeBasedNotificationAggregator`, and
`NotificationComposer` have separate source files for data, temporal aggregation,
and localized text. The former aggregator import path retains compatibility
exports. New code should import the owner it actually uses.

When adding a preset, update the domain enum and its exhaustive UI label/icon
mapping, then run the settings scenarios. When adding an alert, update the shared
wire identifiers and exhaustive message mapping, then run serialization,
localization and notification tests. Changes to PCM layout require parser,
packetizer, stream and native-output compatibility checks.

## App Bootstrap

Startup flow:

```text
main.dart
  -> runApp(MiuCamApp)
  -> MaterialApp
  -> AppBootstrap
  -> SharedPreferences.getInstance()
  -> SharedPreferencesRoleRepository
  -> RoleResolver
  -> ServerAppShell OR ClientAppShell OR RoleSelectionScreen
```

`MiuCamApp` owns:

- app title
- theme
- supported locales
- localization delegates
- `AppBootstrap` as home

`AppBootstrap` owns:

- loading `SharedPreferences`
- creating the application-lifetime billing graph through
  `BroadcastPurchaseCompositionRoot` when paid access is enabled
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
  -> disable parent room delivery and cancel its open LAN requests
  -> remove active runtime from widget tree
  -> seal and await ServerRuntime or ClientRuntime disposal
  -> await widget-owned media teardown and the transition frame
  -> confirm native capture/output/service ownership is idle
  -> clear PairingSessionStore
  -> save or clear AppRole
  -> mount the new composition root
```

Only after these barriers succeed can the next composition root run. A failed
or timed-out resource shutdown keeps both role surfaces inactive and retains the
closing owner for retry; it must not reconstruct the previous runtime over work
that may still be alive. Persistence failure after confirmed shutdown may restore
the previous role. Native confirmation runs only during handoff, not as a new
continuous background poll.

The purchase coordinator survives role changes and is disposed only with
`AppBootstrap`, so late store transactions retain their owner. Its room network
work is separately gated by `setClientActive`: server/selection/transition states
cannot issue parent room requests. A later client needs a fresh attached session.
See [role isolation verification](docs/reports/role_isolation_2026-09-27.md).

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
- Microphone failure must remain visible in runtime state/logs and must not take
  down the video path.

## Composition Roots

The app uses small composition roots instead of global singletons.

Application purchase creation:

```text
BroadcastPurchaseCompositionRoot.create
  -> SharedPreferencesPendingRoomActivationRepository
  -> RemoteBroadcastAccessClient implements RoomBroadcastAccessGateway
  -> BroadcastAccessService
  -> BroadcastPurchaseCoordinator
```

The coordinator depends on `PendingRoomActivationRepository` and
`RoomBroadcastAccessGateway`; preference writes and HTTP requests remain in
their adapters. The service owns local entitlement/trial persistence, while
the coordinator owns delivery to the originally selected room.

Server creation:

```text
ServerCompositionRoot.create
  -> SharedPreferencesTrustedClientRepository
  -> PairingTokenService
  -> borrowed app-owned BroadcastAccessService (standalone fallback owns its service)
  -> FlutterWebRtcServerGateway
  -> AndroidServiceMediaSource on Android (native CameraX/AudioRecord bridge)
  -> MiuCamServiceAdvertiser
  -> MiuCamServer
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
  -> RemoteBroadcastAccessClient
  -> ClientRoomControls
  -> MiuCamServiceBrowser
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
stream writes. Those live in `MiuCamServer` and service classes.

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
  -> StreamSessionController.start(session, audioEnabled)
  -> /session/start checks authoritative room access
  -> ActiveStreamSession(streamToken, mediaTransport, broadcastAccess)
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

`MiuCamProtocolV2` owns the current route names:

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
| `broadcastAccessActivate` | `/broadcast-access/activate` |
| `broadcastAccessLicense` | `/broadcast-access/license` |

`ServerEndpointBuilder` builds HTTP and WS URIs from `PairingSession` and keeps
path/query normalization centralized on the client.

## HTTP Server Ownership

`MiuCamServer` is the runtime owner for:

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

- comfort/night-light/talk delegate to `BabyMonitorFeatureController`
- native comfort/talk output delegates to `RoomAudioCoordinator`
- WebRTC peer/media ownership delegates to `WebRtcServerGateway`
- MJPEG/WAV response ownership remains in their stream services
- demand reconciliation remains in `ServerRuntime` + `MediaRuntimeController`
- thermal/power decisions delegate to `MediaResourceGovernor`

`miucam_server_routes.dart`, `miucam_server_http_controllers.dart`,
`miucam_server_session_http_controller.dart` and
`miucam_server_media_controllers.dart` are still `part`/extension files in the
same library. They share the host's private state; a file boundary does not
enforce an independent controller contract. Extracted objects such as
`MiuCamHttpDispatcher`, `MiuCamEventSocketController`, `ServerSessionRegistry`
and `ServerResourcePolicyCoordinator` have narrower explicit responsibilities.

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
| `/broadcast-access/activate` | POST | bearer | Verify and persist a signed family grant before replying |
| `/broadcast-access/license` | GET | bearer | Recover an active room grant for a trusted paired parent |
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

## Pairing Architecture

Server pairing flow:

```text
ServerHomeScreen QR/IP tab
  -> ServerRuntime.startPairingMode
  -> MiuCamServer.startPairingMode
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
MiuCamServer.startPairingMode
  -> IPv6 dual-stack bind attempt, IPv4 fallback
  -> MiuCamServiceAdvertiser registers _miucam._tcp
  -> TXT: id, protocol version, WebRTC availability, http_ws transport

ClientCompositionRoot
  -> MiuCamServiceBrowser.start
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

`MIUCAM_BROADCAST_PAYWALL_ENABLED` defaults to `true`.
`AppBootstrap`, through `BroadcastPurchaseCompositionRoot`, creates one `BroadcastPurchaseCoordinator` and
`BroadcastAccessService` for the application lifetime. The server runtime borrows
the service for its cumulative trial ledger and license enforcement; role changes
do not dispose billing. Standalone server composition can still own a service.
Diagnostic builds
can explicitly disable enforcement with
`--dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=false`.

Config:

```text
free limit: 2 hours
Turkey target price: 350 TL; checkout uses the store's localized price
product id: miucam_lifetime_unlock_try_300
storage: atomic entitlement JSON in SharedPreferences; independent trial ledger
store gateway: in_app_purchase
license: Ed25519 signed family grant, pinned public key
backend: Python/FastAPI, Apple official SDK + Google Android Publisher API, SQLite
```

Production client ownership:

```text
ClientCompositionRoot
  -> shared BroadcastPurchaseCoordinator for checkout/restore/license delivery
  -> no parent-local trial enforcement
  -> stream start response provides the room's broadcast-access snapshot
  -> RemoteBroadcastAccessClient reads authenticated GET /status
     and trusted POST /broadcast-access/activate, GET /broadcast-access/license
  -> room state is checked again before a client trial timer stops playback
```

The room enforces access when a parent starts media or alert monitoring. Its
trial ledger charges elapsed active time once, even with several viewers.
Disconnected time and local preview do not consume the trial. Expiry closes
paid monitoring paths but preserves pairing and the control channel.

```text
Room media / alert request
  -> authoritative room access check
  -> if locked: HTTP 402 + BROADCAST_ACCESS_LOCKED
  -> otherwise activate demand and account for active monitoring
```

Purchase verification and delivery (parent or room phone):

```text
in_app_purchase PurchaseDetails
  -> exact product id check
  -> app_store/google_play source check
  -> purchased/restored state check
  -> non-empty local + server verification envelope check
  -> trusted HTTPS verifier validates the store transaction
  -> backend durably stores entitlement and pending Google ack
  -> verifier returns fingerprint + entitlement id + signed licenseToken
  -> verify Ed25519 signature, product, source, fingerprint and revision
  -> persist verified entitlement atomically
  -> completePurchase (failed completion remains retryable)
  -> deliver signed grant to originally selected paired room
  -> room persists the grant before confirming activation
```

`MIUCAM_PURCHASE_VERIFIER_URL` and matching `MIUCAM_LICENSE_PUBLIC_KEY` must
configure the trusted verifier before checkout can open. Local store-envelope
validation alone never grants access. The repository includes both client and
backend source; deployment, store credentials and store-console configuration
remain operational release requirements. Raw receipt/token data is not persisted
by the Flutter client.

The family grant can activate multiple trusted paired rooms. QR pairing is the
family invitation; merely being on the same LAN is insufficient. An already
licensed room can give its certificate to a trusted paired parent for recovery,
including a different store account/platform. There is no cloud user account or
single-active-room transfer rule. The five-viewer limit remains per room.

Activation targets are persisted before checkout. Offline delivery uses bounded
foreground retries and survives process restart. Switching rooms clears the old
remote snapshot and cannot change an in-flight checkout's target. Explicit unpairing invalidates pending work for that room before the first
await, including old work completing after the same room is paired again. The
family purchase remains owned by the app. Failed cleanup after a successful
activation preserves the room result and retries persistence. The license
control routes remain usable after trial expiry. Public status never contains a
license certificate. Media requests do not query billing servers.

The coordinator's `PendingRoomActivationRepository` must reject unconfirmed
writes. Its SharedPreferences adapter reloads after a failed write and retains
its last confirmed snapshot if that reload also fails.
`RoomBroadcastAccessGateway` isolates room lookup/activation from the HTTP
adapter. `RetryPolicy` supplies foreground activation backoff without owning
timers. `InAppBroadcastPurchaseGateway` owns the store stream and serializes
verification, durable delivery and acknowledgement; `FlutterInAppPurchaseStore`
contains platform calls. The service's old import path re-exports the split
models and gateway for compatibility.

Foreground reconciliation queries owned transactions without interactive sync.
Android uses `queryPastPurchases`; StoreKit 2 uses unfinished/history queries,
with a current-entitlements receipt fallback tied to pinned plugin `0.4.10+1`.
Only an explicit iOS Restore action calls `AppStore.sync`. Queries coalesce and
normally throttle for one minute; a new checkout force-checks ownership.
Catalog prices expire after 15 minutes. Known store-pending approval remains
separate from an expired UI await.

The Python backend's `domain.py` defines `StoreAdapter`, `AcknowledgingStore`
and `SignedNotificationStore` protocols plus typed store source/status/failure
values. `BillingService` reconciles through these capabilities. Google and Apple
implementations live in `stores.py`; `LicenseRepository` and `LicenseSigner`
own persistence and signing in `licenses.py`.

Signed revocations are refreshed on foreground with a six-hour throttle; network
errors preserve a paid offline license. A confirmed revoke is delivered to rooms
and its increasing revision prevents replay of an older active grant. An entirely
offline device cannot receive an immediate refund update. Google ack recovery is
durable in the backend. See [backend operations](backend/README.md) and
[implementation evidence](docs/reports/purchase_implementation_2026-09-27.md).

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

`MiuCamServer` exposes independent `startVideoRuntime` / `stopVideoRuntime` and
`startAudioRuntime` / `stopAudioRuntime` boundaries. `startMediaRuntime` remains
as a compatibility convenience that requests both. There are two source modes:

1. **Media source branch:** `ServerMediaSource` is the adapter boundary for
   Android's production `AndroidServiceMediaSource` and deterministic test
   sources. Android hardware belongs to the native foreground-service engine.
2. **Plugin branch:** uses camera and microphone plugins, including the default
   iOS path and injected camera/recorder platform tests.

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

This seam is central to production-route end-to-end tests because it does not
require real hardware.

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

Plugin camera path:

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

Android's default path uses the service-owned CameraX encoder and feeds JPEG
and luma through `AndroidServiceMediaSource` into the same Dart fan-out and
analysis boundaries. `CameraJpegWorker` belongs to the plugin camera path.

Injected test path (`test/support/deterministic_server_media_source.dart`):

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

Plugin microphone path:

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

Android's native AudioRecord chunks arrive through `AndroidServiceMediaSource`.
The injected-source handler currently passes the same PCM to analysis and WAV;
the separate `AudioStreamLeveler` path above belongs to plugin capture.

Server injected source path:

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
`ClientQualityTracker`, and exposed in authenticated `/status` stream health.

Audio invariants:

- microphone failure is best-effort and must not silently disappear
- video can work while audio reports a permission/capture reason
- production `/audio` scenario tests must verify WAV header and emitted PCM
- notification tests must feed PCM through the real analyzer and `/ws/events`
- native write errors must be visible in client metrics

## Native PCM Output

`PcmAudioOutput` uses method channel `miucam/pcm_audio`.

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

Plugin audio analysis uses raw microphone PCM while client playback uses leveled
stream PCM. The Android source handler currently supplies the same native PCM
to both destinations. Room-generated comfort/talk audio suppresses analysis
without interrupting the parent stream.

The coordinator checks current audio/video analysis demand before feature work
and clears temporal evidence on discontinuity. `AudioRingBuffer` uses fixed
capacity and bulk copies; `CryAudioAnalyzerV2` lazily owns reusable PCM/normalized
window buffers. Analysis timing must contain at least one sample. These resource
rules preserve thresholds and do not establish accuracy on real baby recordings.

## Alert And Event Architecture

Server event path:

```text
AlertEngine emits AlertEvent
  -> MiuCamServer._handleAlertEvent
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

Current delivery behavior:

- `ClientAlertListener` negotiates `alertReplayV=1`, reconnects with
  `afterAlertId`, and ACKs an event only after its delivery callback succeeds.
- `MiuCamEventSocketController` keeps an ordered in-memory replay window:
  at most 128 alerts, two minutes of age and 64 client cursors by default.
- `ClientAlertDeliveryCoordinator` serializes history/notification delivery and
  deduplicates IDs. A transient delivery failure reconnects from the last
  contiguous ACK; permanently denied notifications can use durable history.
- Replay is bounded and is lost when the server process stops. It is not a
  durable push service or a guarantee of exactly-once delivery across devices.

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
miucam/device_resources snapshot
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

The implemented policies are `MediaQualitySelector`,
`UtilityBasedProfileSelector` and `MediaResourceGovernor`, with profile changes
serialized through `MediaProfileApplyQueue`. No Max/Ultra mode is exposed by
these contracts.

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

- busy video responses retain only the latest pending frame; replacement is
  counted as a skip
- audio responses retain a bounded PCM queue and detach on overflow
- failed flush removes the client
- `HttpMediaResponseLifecycle` shares flush timeout/connection checks and
  teardown deadlines between MJPEG and WAV; the deadline also ends stalled TCP
  output, rather than merely ending the Dart await

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
cross-device receive estimates. Authenticated `/status` publishes telemetry in
`streamHealth.sessionTelemetry`; the sample bound prevents a long-running
monitor from growing telemetry memory.

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

- `MiuCamDesignTokens`
- `MiuCamRolePresentation`
- `MiuCamShells`
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
- `lib/l10n/src/app_purchase_text_catalog.dart`

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
- includes media profile, stream health, resource governor and bounded session
  telemetry values

## Production-Route Scenario Verification

There is no browser dashboard, synthetic alert route or `/test/*` API in the
runtime. Automated tests exercise the same boundaries used by paired phones:

```text
deterministic PCM/JPEG source
  -> MiuCamServer analysis and stream services
  -> /audio, /video or /ws/events
  -> production client parser/listener
```

Notification scenarios additionally verify quiet-room calibration, configured
cry threshold/minimum duration, episode gap handling, comfort/talk self-audio
suppression, continuous parent audio, structured alert delivery, history
persistence and the platform-notification handoff. Physical runs capture
authenticated `/status`; they do not trigger synthetic media or notifications.

Proof criteria for audio and alerts:

- WAV header is valid and PCM arrives after it
- the client parser emits PCM chunks
- calibrated sustained cry-like PCM traverses the production alert pipeline
- room-generated comfort/talk audio never becomes a cry notification
- the client listener receives exactly one structured event for one episode

## End-To-End Media Seams

The strongest non-device media tests use:

- the `test/support/deterministic_server_media_source.dart` fixture
- real `MiuCamServer`
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
- `AndroidServiceMediaSource` and its platform bridge ports

Platform/native paths:

- Android caches the existing Flutter engine and lets
  `MiuCamForegroundService` claim it while media demand is active.
- Default Android capture is service-owned CameraX/AudioRecord;
  `AndroidServiceMediaSource` adapts it to the shared Dart media contracts.
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
  `miucam/device_resources`.
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
  `--dart-define=MIUCAM_WEBRTC_PILOT=true` only when no stored override exists
- build-only broadcast paywall flag:
  `--dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED`; default `true` in
  `core/feature_flags.dart`; diagnostic builds can set it to `false`

Server settings screen updates `ConfigurationService`, then calls
`MiuCamServer.reloadAnalysisConfig` through `ServerRuntime`.

The WebRTC pilot is off by default. A build can opt in with
`--dart-define=MIUCAM_WEBRTC_PILOT=true`; a persisted
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
- WebSocket authentication accepts only the Bearer header, never URL tokens
- pair confirm rate limiting
- nonce pruning
- bounded JSON control-body reader (64 KiB normally, 16 KiB for license activation)
- exact connection leases and operation-attempt ownership for media/talk cleanup

Known security limits:

- HTTP/WS is plaintext on local network
- no HTTPS/WSS
- no certificate pinning
- no cloud identity/account system
- local network attackers are not fully mitigated
- public pairing-nonce redesign is intentionally not part of this work
- no encrypted session-ticket protocol

The shared body reader and in-memory socket leases are implemented. They do
not encrypt local transport or replace the current pairing nonce design.

## Error Handling And Cleanup

General rules:

- dispose runtimes on role switch
- cancel stream subscriptions
- force-close long-lived media test clients after first payload
- close HTTP responses on error paths
- keep media start best-effort for audio
- stop runtime when no active demand remains

Important cleanup owners:

- `AppBootstrap`: role runtime disposal
- `ServerRuntime`: UI/runtime resource demand cleanup
- `MiuCamServer`: HTTP server, media runtime, stream clients
- `BabyMonitorFeatureController`: comfort/night-light/talk facade
- `RoomAudioCoordinator`: exclusive comfort/talk native PCM output
- `FlutterWebRtcServerGateway`: pilot peer/tracks
- `MiuCamServiceAdvertiser` / `MiuCamServiceBrowser`: discovery lifecycle
- `MjpegStreamService`: video responses
- `WavAudioStreamService`: audio responses
- `ClientRuntime`: network subscription and watch state
- `ClientMediaStreamSupervisor`: video client and audio pipeline
- `ClientAlertListener`: WebSocket and reconnect timer
- `BroadcastPurchaseCoordinator`: application-lifetime purchase graph,
  foreground room-delivery retries and access subscription
- `BroadcastAccessService`: entitlement/trial persistence and gateway ownership
- `InAppBroadcastPurchaseGateway`: native purchase subscription and queued delivery

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
flutter test test/services/discovery/miucam_service_discovery_test.dart
flutter test test/services/server/room_audio_coordinator_test.dart
flutter test test/features/client/client_room_controls_test.dart
```

Audio-specific proof:

```bash
flutter test test/features/server/media_stream_end_to_end_test.dart
flutter test test/features/server/server_alert_delivery_scenario_test.dart
flutter test test/analysis/audio/cry_audio_analyzer_v2_test.dart
flutter test test/analysis/alert/episode_notification_aggregator_test.dart
```

What these tests prove:

- `/session/start`, `/video` and `/audio` use the real HTTP server and parsers
- WAV framing yields live PCM without a synthetic tone endpoint
- calibrated cry-like PCM reaches `/ws/events` through the real analyzer
- comfort and talk output are suppressed from cry classification
- notification profiles and packet gaps affect the episode decision correctly
- pilot tests prove signaling auth/session ownership and automatic fallback;
  they do not prove physical codec/ICE behavior
- platform contract tests prove serialized pause/recovery policy; simulators do
  not prove background camera/audio-focus behavior

Physical release evidence is defined in
`docs/physical_device_test_matrix.md`. `tool/benchmarks/device_soak_harness.dart`
records authenticated `/status` JSONL, but the matrix is not complete until the named
physical device/network lanes have produced archived results.

## Release And Store Notes

Before shipping paid unlock:

1. Configure non-consumable product `miucam_lifetime_unlock_try_300`.
2. Set the Turkey target price to 350 TL and configure other store regions.
3. Test purchase and restore on sandbox accounts.
4. Confirm unavailable store state is user-visible.
5. Confirm unverified purchase/restore fails closed.
6. Deploy `backend/` with real store credentials; configure
   `MIUCAM_PURCHASE_VERIFIER_URL` and matching `MIUCAM_LICENSE_PUBLIC_KEY`.
7. Confirm unlock persists across app restarts.
8. Complete the two-device real-store acceptance matrix, including pending
   approval while terminated, parent-to-room delivery, restore, refund webhooks,
   acknowledgement recovery, and cross-platform family recovery.

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
6. Run the production media and alert scenario tests after endpoint changes.
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

- durable alert replay across server process loss and guaranteed remote delivery
- production BLE discovery/control
- parent video overlay on server
- mastered comfort-audio assets and echo-controlled talk productization
- cloud relay
- account system
- HTTPS/WSS
- multi-peer WebRTC, TURN/relay and production NAT traversal
- live deployment and real-store acceptance of the included purchase backend
- completed physical-device matrix evidence

The safe rule is simple: if production-route scenario tests or physical-device
evidence cannot prove it, it should not be documented as shipped behavior.
