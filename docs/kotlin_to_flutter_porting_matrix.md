# Kotlin to Flutter Porting Matrix

This file is a migration ledger from the old Android/Kotlin direction to the
current Flutter implementation. It is not the architecture source of truth. For
runtime details, read `README.md`, `ARCHITECT.md`, `lib/`, and `test/`.

## Porting Status

| Legacy or planned responsibility | Status | Current implementation |
| --- | --- | --- |
| App entry | Rebuilt | `lib/main.dart`, `lib/app/app_bootstrap.dart` |
| Role selection | Rebuilt | `lib/features/role_selection/` |
| Role persistence | Rebuilt | `SharedPreferencesRoleRepository`, `RoleResolver` |
| Server/client mixed navigation | Replaced | Separate `ServerAppShell` and `ClientAppShell` |
| Runtime graph isolation | Rebuilt | `ServerCompositionRoot`, `ClientCompositionRoot` |
| Permission policy | Rebuilt | `RolePermissionCoordinator` |
| Configuration thresholds | Rebuilt | `ConfigurationService` |
| Protocol constants | Rebuilt | `MimiCamProtocolV2` |
| Local address selection | Rebuilt | `NetworkAddressProvider`, IPv4/IPv6 URI-safe selection |
| DNS-SD/NSD discovery | New | `_mimicam._tcp`, `MimiCamServiceAdvertiser`, `MimiCamServiceBrowser` |
| Dual-stack server bind | New | IPv6 `v6Only:false` attempt with IPv4 fallback |
| Local network guard | New | `LocalNetworkGuard` |
| Local HTTP server | Rebuilt | `MimiCamServer` |
| Route auth guard | New | `RequestAuthGuard` |
| Pairing nonce service | New | `PairingTokenService` |
| QR payload build | Rebuilt | `ServerQrPayloadBuilder` |
| QR rendering | Rebuilt | `qr_flutter` |
| QR scan | Rebuilt | `mobile_scanner` |
| Manual IP fallback | Rebuilt | Client fetches `/status/public` |
| Trusted token storage | Hardened | `PairingSessionStore`, `flutter_secure_storage` |
| Persistent client identity | New | `ClientIdentityStore` |
| Token renewal | New | `TrustedTokenRenewalClient` |
| Multi-child profile storage | New | `ChildProfile`, `PairingSessionStore` |
| Active watch session lifecycle | Rebuilt | `StreamSessionController`, `ActiveClientRegistry` |
| Demand-owned camera/microphone | New | `MediaRuntimeController`, `MediaResourceDemand`, `ServerRuntime` |
| MJPEG server stream | Rebuilt | `MjpegStreamService` |
| MJPEG client parsing | Rebuilt | `MjpegStreamParser`, `ClientVideoViewer` |
| WAV/PCM server stream | Rebuilt | `WavAudioStreamService` |
| WAV/PCM client parsing | Rebuilt | `WavPcmStreamParser`, `ClientLiveAudioPipeline` |
| Native Android audio output | Rebuilt | `AudioTrack` in `android/app/src/main/.../MainActivity.kt` |
| Native iOS audio output | Rebuilt | `AVAudioEngine` in `ios/Runner/AppDelegate.swift` |
| Native audio interruptions | New | Android audio focus/noisy/device callbacks; iOS interruption/route/reset observers |
| Android background ownership | Rebuilt | Cached Flutter engine owned by non-sticky `MimiCamForegroundService` while demand exists |
| iOS background contract | New | Controlled media pause on background and retained-demand recovery on foreground |
| Camera image analysis | Rebuilt | `analysis/video/`, `MediaAnalysisCoordinator` |
| Motion scoring | Rebuilt | `MotionAnalyzerV2` |
| Luma downsampling | Rebuilt | `LumaDownsampler` |
| Camera image to JPEG | Rebuilt | `CameraImageJpegEncoder` |
| PCM sample reading | Rebuilt | `Pcm16LeReader` |
| Audio ring buffer | Rebuilt | `AudioRingBuffer` |
| Audio band analysis | Rebuilt | `GoertzelBandAnalyzer` |
| Cry-like scoring | Rebuilt | `CryAudioAnalyzerV2` |
| Alert cooldown | Rebuilt | `CooldownPolicy` |
| Alert engine | Rebuilt | `AlertEngine` |
| Episode parent messages | New | `EpisodeBasedNotificationAggregator` |
| WebSocket events | Rebuilt | `/ws/events`, `ClientAlertListener` |
| Local notifications | Rebuilt | `ClientNotificationService` |
| In-app alert history | New | `ClientAlertHistory` |
| Adaptive media quality | New | `MediaQualitySelector`, `UtilityBasedProfileSelector` |
| Thermal/power governor | New | `DeviceResourceSnapshotProvider`, `MediaResourceGovernor` |
| Bounded E2E media telemetry | New | `MediaSessionTelemetry`, p50/p95/p99 and counters in `/test/status` |
| Stream backpressure | New | `StreamBackpressureGate` |
| Runtime diagnostics | New | `/test`, `/test/status`, `/test/probe`, `/test/alert`, `/test/audio-tone` |
| Battery reporting | New | `BatterySnapshot`, `BatterySnapshotProvider`, `battery_plus` |
| WebRTC H.264 + Opus | Pilot | Opt-in one-peer `flutter_webrtc` path with authenticated HTTP signaling and MJPEG/WAV fallback |
| Comfort audio controls | Rebuilt | Procedural PCM catalog, native room playback and client controls |
| Night light controls | Partial | State/command model and torch/screen-glow path exist |
| Two-way talk audio | Rebuilt | Parent microphone PCM upload, exclusive native room playback and comfort resume |
| Two-way talk video | Partial | Compatibility ingest exists; parent overlay is intentionally unsupported |
| Full screen watch UI | Rebuilt | `WatchScreen` |
| Server full screen preview | New | `ServerHomeScreen` preview controls |
| Paid unlock | Hardened | Fail-closed local store-envelope verification, SHA-256 evidence fingerprint, `in_app_purchase` |
| Localization | Expanded | `AppStrings`, `app_ui_text_catalog.dart`, extras |
| UI theme tokens | Rebuilt | `MimiCamDesignTokens`, shells, role presentation |

## Removed or Out of Scope

| Area | Decision |
| --- | --- |
| UDP discovery | Replaced by DNS-SD/NSD |
| Telegram automation | Removed |
| Cloud relay | Out of scope |
| Account system | Out of scope |
| OAuth/login | Out of scope |
| Push backend | Out of scope |
| Apple Watch | Out of scope |
| HTTPS/WSS | Out of scope for current runtime |
| Certificate pinning | Out of scope until HTTPS/WSS exists |
| Multi-peer WebRTC | Out of scope; pilot is one peer |
| TURN/relay/internet NAT traversal | Out of scope; pilot is LAN host ICE only |
| Direct Bluetooth media | Out of scope |
| Client-per-video-encode pipeline | Removed; server broadcasts latest frame |
| Mixed Server/Client shell | Removed; role graphs are isolated |
| Public nonce/body limits/socket lease/session ticket bundle | Intentionally excluded from this local-LAN implementation pass |

## Flutter Architecture Pieces Added During Port

| Piece | Reason |
| --- | --- |
| `ClientRuntime` | Owns client session, watch, alerts, token renewal, quality, and paid access state |
| `ServerRuntime` | Owns server UI state without mixing widget code into protocol internals |
| `MimiCamServer` | HTTP composition boundary; diagnostics and room/WebRTC/resource work delegate to focused services |
| `MediaRuntimeController` | Serializes independent camera/microphone demand and platform pause/recovery |
| `PlatformRuntimeContract` | Publishes native lifecycle/audio/engine ownership events and snapshots |
| `MediaResourceGovernor` | Combines thermal, power, codec and transport pressure |
| `MediaSessionTelemetry` | Keeps bounded session latency distributions and reliability counters |
| `BabyMonitorFeatureController` | Facade for comfort, night-light and talk routes |
| `RoomAudioCoordinator` | Gives talk priority over comfort on one native PCM sink |
| `FlutterWebRtcServerGateway` | Owns pilot peer, local tracks and H.264/Opus preferences |
| `MimiCamServiceAdvertiser` / `MimiCamServiceBrowser` | Own DNS-SD advertise/browse lifecycle |
| `ActiveClientRegistry` | Keeps trusted clients, watch sessions, stream sockets, and quality reports aligned |
| `PairingSessionStore` | Separates secure tokens from non-secret metadata |
| `ClientStreamHealthState` | Builds health reports from real streams |
| `NetworkQualityMonitor` | Combines status RTT, stream health, and battery reports |
| `MjpegStreamService` | Owns MJPEG response lifecycle and diagnostics |
| `WavAudioStreamService` | Owns WAV response lifecycle and backpressure |
| `ClientMediaStreamSupervisor` | Coordinates video/audio stream start, failure classification, and reconnect behavior |
| `ClientLiveAudioPipeline` | Parses WAV and writes PCM to native output |
| `BroadcastAccessService` | Enforces free time and persists only verified unlock results |
| `ClientAlertHistory` | Keeps alert history independent of OS notification permission |

## Platform Mapping

| Concern | Android | iOS |
| --- | --- | --- |
| Camera | Flutter `camera` plugin | Flutter `camera` plugin |
| Microphone capture | `record` plugin | `record` plugin |
| PCM playback | `AudioTrack` | `AVAudioEngine` and `AVAudioPlayerNode` |
| Audio lifecycle | Audio focus, becoming-noisy and output-device callbacks | AVAudioSession interruption, route and media-services reset |
| QR scan | `mobile_scanner` | `mobile_scanner` with explicit permission gating |
| Notifications | `flutter_local_notifications` | `flutter_local_notifications` |
| Battery | `battery_plus` | `battery_plus` |
| Paid unlock | Google Play envelope validation before local entitlement | App Store envelope validation before local entitlement |
| Foreground/server presence | Existing Flutter engine owned by non-sticky foreground service | Camera pauses in background and retained demand recovers in foreground |
| Local network permission | Android network stack | `NSLocalNetworkUsageDescription` and Bonjour config |
| Discovery | Android NSD through `nsd` | Bonjour through `nsd`, `_mimicam._tcp` declared |
| Thermal/power snapshot | `PowerManager` + battery state | `ProcessInfo` + `UIDevice` battery state |

## Tests That Protect the Port

| Concern | Tests |
| --- | --- |
| Role separation | `test/app/role_isolation_test.dart`, `test/features/hard_split_navigation_test.dart` |
| Permissions | `test/app/role_permission_coordinator_test.dart` |
| Pairing payload | `test/core/pairing_payload_test.dart`, `test/features/client/qr_pairing_client_test.dart` |
| Pairing storage | `test/features/client/pairing_session_store_test.dart` |
| Client identity | `test/features/client/client_identity_store_test.dart` |
| Token auth | `test/features/server/token_auth_test.dart`, `test/features/server/endpoint_worst_case_test.dart` |
| Active client lifecycle | `test/services/server/active_client_registry_test.dart`, `test/features/server/active_client_limit_test.dart` |
| MJPEG stream | `test/features/server/mjpeg_stream_service_test.dart`, `test/features/client/mjpeg_stream_parser_test.dart` |
| Real media endpoints | `test/features/server/media_stream_end_to_end_test.dart` |
| WAV/audio stream | `test/features/client/client_live_audio_pipeline_test.dart`, `test/features/client/wav_pcm_stream_parser_test.dart` |
| Alerts | `test/analysis/alert/alert_engine_test.dart`, `test/features/client/client_alert_listener_test.dart` |
| Adaptive quality | `test/services/server/media_quality_selector_test.dart`, `test/services/server/utility_based_profile_selector_test.dart` |
| Demand ownership | `test/features/server/media_runtime_controller_test.dart` |
| Platform lifecycle | `test/services/platform/platform_runtime_contract_test.dart` |
| Resource governor | `test/services/server/media_resource_governor_test.dart` |
| Session telemetry | `test/core/media/media_session_telemetry_test.dart` |
| WebRTC pilot/fallback | `test/features/server/webrtc_signaling_endpoints_test.dart`, `test/features/client/stream_session_controller_test.dart` |
| DNS-SD/IPv6 discovery model | `test/services/discovery/mimicam_service_discovery_test.dart` |
| Feature controls | `test/features/server/feature_control_endpoints_test.dart` |
| Comfort/talk native ownership | `test/services/server/room_audio_coordinator_test.dart`, `test/features/client/client_room_controls_test.dart` |
| Paid access | `test/services/monetization/broadcast_access_service_test.dart`, `test/features/client/client_runtime_lifecycle_test.dart` |
| Diagnostics | `test/features/server/test_endpoints_test.dart` |
| Localization | `test/l10n/app_strings_test.dart` |
| UI budget | `test/features/performance/screen_render_budget_test.dart` |

## Migration Rule

When reviving an old Kotlin feature or adding a planned product feature, do not
mark it as supported until it has:

1. Runtime implementation.
2. Protocol or local API contract.
3. Client integration.
4. Server integration where relevant.
5. Tests.
6. README and architecture updates.

This rule is especially important for cloud relay, Bluetooth, HTTPS/WSS,
multi-peer/relayed WebRTC, talk video and purchase server verification. The
current WebRTC implementation must remain labelled a pilot until the physical
device matrix has codec, interruption, network-impairment and soak evidence.

Purchase-verification caveat: current code verifies store source/product/state
and non-empty verification envelopes locally, then stores only a fingerprint.
It does not yet perform Apple/Google server-side receipt authenticity checks.
