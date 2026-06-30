# Kotlin to Flutter Porting Matrix

This document maps the old Android/Kotlin responsibilities to the current Flutter/Dart implementation. It is not an architecture source by itself; it is a migration ledger. The current runtime truth lives in `lib/`, `android/`, `ios/`, and the tests.

## Porting Status

| Legacy Kotlin responsibility | Current status | Current implementation |
| --- | --- | --- |
| App entry and role UI | Rebuilt | `lib/app/app_bootstrap.dart`, `lib/features/role_selection/` |
| Server/client mixed navigation | Replaced | Separate `ServerAppShell` and `ClientAppShell` |
| Role persistence | Rebuilt | `SharedPreferencesRoleRepository`, `RoleResolver` |
| Permission request policy | Rebuilt | `lib/app/role_permission_coordinator.dart` |
| Protocol constants | Rebuilt | `lib/core/mimicam_protocol.dart`, `lib/core/protocol/mimicam_protocol.dart` |
| Local address selection | Rebuilt | `lib/services/network_address_provider.dart` |
| Local network guard | New | `lib/core/network/local_network_guard.dart` |
| Configuration thresholds | Rebuilt | `lib/services/configuration_service.dart` |
| Camera image analysis | Rebuilt | `lib/analysis/video/`, `lib/services/server/media_analysis_coordinator.dart` |
| Motion scoring | Rebuilt | `lib/analysis/video/motion_analyzer_v2.dart` |
| Luma downsampling | Rebuilt | `lib/analysis/video/luma_downsampler.dart` |
| CameraImage to JPEG | Rebuilt | `CameraImageJpegEncoder` in `lib/services/motion_analyzer.dart` |
| Audio PCM reading | Rebuilt | `lib/analysis/audio/pcm16le_reader.dart` |
| Audio ring buffer | Rebuilt | `lib/analysis/audio/audio_ring_buffer.dart` |
| Audio band analysis | Rebuilt | `lib/analysis/audio/goertzel_band_analyzer.dart` |
| Cry analysis | Rebuilt | `lib/analysis/audio/cry_audio_analyzer_v2.dart` |
| Alert cooldown | Rebuilt | `lib/analysis/alert/cooldown_policy.dart` |
| Alert engine | Rebuilt | `lib/analysis/alert/alert_engine.dart` |
| Episode-style parent messages | New | `lib/analysis/alert/episode_notification_aggregator.dart` |
| Local HTTP server | Rebuilt | `lib/services/mimicam_server.dart` |
| Pairing nonce and token service | New | `lib/features/server/pairing/pairing_token_service.dart` |
| QR payload build | Rebuilt | `lib/features/server/pairing/server_qr_payload_builder.dart` |
| QR rendering | Rebuilt | `qr_flutter` in Server UI |
| QR scan | Rebuilt | `mobile_scanner` in Client UI |
| Manual IP fallback | Rebuilt | Client pairing flow using `/status/public` |
| Trusted token storage | Hardened | `PairingSessionStore` plus `flutter_secure_storage` |
| Token renewal | New | `TrustedTokenRenewalClient`, `ClientRuntime.renewTokenIfNeeded` |
| Watch session lifecycle | Rebuilt | `StreamSessionController`, `ActiveClientRegistry` |
| MJPEG video stream | Rebuilt | `MjpegStreamService`, `ClientVideoViewer` |
| WAV/PCM audio stream | Rebuilt | `WavAudioStreamService`, `ClientLiveAudioPipeline` |
| Native Android audio output | Rebuilt | `android/app/src/main/kotlin/.../MainActivity.kt` with `AudioTrack` |
| Native iOS audio output | Rebuilt | `ios/Runner/AppDelegate.swift` with `AVAudioEngine` |
| WebSocket event stream | Rebuilt | `/ws/events`, `ClientAlertListener` |
| Local notifications | Rebuilt | `flutter_local_notifications`, `ClientNotificationService` |
| In-app alert history | New | `ClientAlertHistory` |
| Adaptive media quality | New | `MediaQualitySelector`, `UtilityBasedProfileSelector` |
| Stream backpressure | New | `StreamBackpressureGate`, `MjpegStreamService`, `WavAudioStreamService` |
| Runtime diagnostics | New | `/test`, `/test/status`, `/test/probe`, `/test/alert`, `/test/audio-tone` |
| Localization | Expanded | `lib/l10n/app_strings.dart`, `lib/l10n/src/` |
| UI theme tokens | Rebuilt | `lib/core/theme/`, `lib/features/shared/presentation/` |

## Removed or Deliberately Out of Scope

| Legacy or planned area | Current decision |
| --- | --- |
| UDP discovery / broadcast | Removed. Pairing is QR or manual IP. |
| Telegram automation | Removed from MVP. |
| Cloud relay | Out of scope. |
| Account system and OAuth | Out of scope. |
| Push backend | Out of scope. |
| HTTPS/WSS and certificate pinning | Out of scope for current MVP. |
| WebRTC/H.264 | Out of scope until implemented end to end. |
| Opus audio | Out of scope until implemented end to end. |
| Client-per-video-encode pipeline | Removed. Server uses latest-frame broadcast. |
| Server-side QR scanner | Removed. Server produces QR, Client scans QR. |
| Mixed Server/Client UI in one shell | Removed. Runtime graphs are role-isolated. |

## New Flutter Architecture Pieces

| Area | Why it exists |
| --- | --- |
| `ClientRuntime` | Keeps Client session, alert, watch, token-renewal, and quality state in one lifecycle model. |
| `ServerRuntime` | Connects Server UI state to `MimiCamServer` without mixing UI and protocol internals. |
| `ActiveClientRegistry` | Prevents trusted clients, watch sessions, stream connections, and quality reports from drifting apart. |
| `PairingSessionStore` | Separates secure token storage from non-secret pairing metadata. |
| `ClientStreamHealthState` | Builds quality reports from live video/audio/event callbacks without opening extra media streams. |
| `NetworkQualityMonitor` | Combines RTT/status probes with stream health and posts `/quality/report`. |
| `MjpegStreamService` | Owns MJPEG response lifecycle, keepalive, backpressure, and diagnostics. |
| `WavAudioStreamService` | Owns WAV response lifecycle, PCM chunk writes, backpressure, and diagnostics. |
| `ClientLiveAudioPipeline` | Parses WAV, buffers aligned PCM, writes to native sink, and reports underruns. |
| `ClientAlertHistory` | Keeps alert screen independent from OS notification permission. |

## Platform Mapping

| Platform concern | Android | iOS |
| --- | --- | --- |
| Camera | Flutter `camera` plugin | Flutter `camera` plugin |
| Microphone capture | `record` plugin | `record` plugin |
| PCM playback | Native `AudioTrack` | Native `AVAudioEngine` + `AVAudioPlayerNode` |
| QR scan | `mobile_scanner` | `mobile_scanner` with explicit permission gating |
| Local notifications | `flutter_local_notifications` | `flutter_local_notifications` |
| Foreground/server presence | Native foreground service bridge | iOS stays within app lifecycle constraints |
| Local network permission | Android network stack | `NSLocalNetworkUsageDescription` and Bonjour entries |

## Tests That Protect the Port

| Concern | Tests |
| --- | --- |
| Role separation | `test/app/role_isolation_test.dart`, `test/features/hard_split_navigation_test.dart` |
| Permissions | `test/app/role_permission_coordinator_test.dart` |
| Pairing payload | `test/core/pairing_payload_test.dart`, `test/features/client/qr_pairing_client_test.dart` |
| Session storage | `test/features/client/pairing_session_store_test.dart` |
| Token auth | `test/features/server/token_auth_test.dart`, `test/features/server/endpoint_worst_case_test.dart` |
| Active client lifecycle | `test/services/server/active_client_registry_test.dart`, `test/features/server/active_client_limit_test.dart` |
| MJPEG stream | `test/features/server/mjpeg_stream_service_test.dart`, `test/features/client/mjpeg_stream_parser_test.dart`, `test/features/client/client_video_viewer_test.dart` |
| WAV/audio stream | `test/features/client/client_live_audio_pipeline_test.dart`, `test/features/client/wav_pcm_stream_parser_test.dart`, `test/services/server/wav_pcm16_test.dart` |
| Alerts | `test/analysis/alert/alert_engine_test.dart`, `test/features/client/client_alert_listener_test.dart`, `test/features/client/client_alert_history_test.dart` |
| Adaptive media | `test/services/server/media_quality_selector_test.dart`, `test/services/server/utility_based_profile_selector_test.dart`, `test/core/media/client_quality_tracker_test.dart` |
| Diagnostics | `test/features/server/test_endpoints_test.dart` |
| Localization | `test/l10n/app_strings_test.dart` |
| UI budget | `test/features/performance/screen_render_budget_test.dart` |

## Migration Rule for Future Work

When adding back a legacy idea, do not document it as supported until it has:

1. Runtime implementation.
2. Wire contract.
3. Client and Server integration.
4. Tests.
5. README and architecture updates.

This rule especially applies to HTTPS/WSS, WebRTC, H.264, Opus, cloud relay, and automatic discovery.
