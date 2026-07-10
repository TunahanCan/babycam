# MimiCam physical-device release matrix

This matrix validates the media pipeline on real hardware. Emulator/simulator
results do not qualify a release because camera, microphone, thermal throttling,
audio focus and background execution differ materially from a physical device.

**Execution status:** this file is the required test specification and release
gate, not a completed result report. No lane passes until a dated result JSON,
device/network metadata and the case's required evidence (including JSONL for
sampled/soak lanes) have been archived.

The executable case catalog is
[`tool/device_matrix_plan.json`](../tool/device_matrix_plan.json), the runner is
[`tool/device_matrix_runner.dart`](../tool/device_matrix_runner.dart), and every
result must conform to
[`device_matrix_result.schema.json`](device_matrix_result.schema.json).

## Safe runner workflow

Run these commands from the repository root. The dry-run and self-test neither
contact a device nor mutate application/network state:

```sh
dart run tool/device_matrix_runner.dart --self-test
dart run tool/device_matrix_runner.dart \
  --dry-run \
  --output /tmp/mimicam-device-matrix.json
```

If Flutter is not on `PATH`, set `FLUTTER_BIN` to the SDK's `bin/flutter` or
pass `--flutter /absolute/path/to/flutter`; the recorded command remains
argument-separated and shell-free.

Inventory two attached physical devices and run the deterministic preflight
tests. Device IDs come from `flutter devices --machine`; simulator/emulator IDs
are rejected for launch and completed-result evaluation.

```sh
dart run tool/device_matrix_runner.dart \
  --server-device IOS_OR_ANDROID_SERVER_ID \
  --client-device DIFFERENT_PHYSICAL_CLIENT_ID \
  --run-tests \
  --network lab-baseline \
  --output artifacts/device-matrix/preflight.json
```

Launching is a separate explicit opt-in. The runner uses `Process.start`
without a shell, passes device IDs as individual arguments, never automates
Wi-Fi/call/thermal changes, and never accepts a trusted token in command-line
history.

```sh
dart run tool/device_matrix_runner.dart \
  --case WEBRTC-Codec-01 \
  --server-device IOS_SERVER_ID \
  --client-device ANDROID_CLIENT_ID \
  --media-lane webrtc \
  --build-mode profile \
  --launch \
  --output artifacts/device-matrix/webrtc-codec.json
```

`--launch` runs `flutter run --no-resident` first for the server and then the
client. Select/reset the intended room/client role on each device before the
case. For legacy, use `--media-lane legacy`; for the pilot the runner adds
`--dart-define=MIMICAM_WEBRTC_PILOT=true`.

After pairing, an authenticated diagnostic probe can capture `/test/status`
and `/test/probe`. Put the token only in the environment and clear it after the
command. `--probe-audio-tone` validates WAV transport without microphone
input; omit it for a real microphone path.

```sh
export MIMICAM_MATRIX_TOKEN='trusted-token-from-this-test-pair'
dart run tool/device_matrix_runner.dart \
  --case NET-IPv4-01 \
  --server-device SERVER_ID \
  --client-device CLIENT_ID \
  --base-url http://192.168.1.42:8080 \
  --probe \
  --output artifacts/device-matrix/ipv4-probe.json
unset MIMICAM_MATRIX_TOKEN
```

Record operator checks, numeric gates and evidence without hand-editing JSON:

```sh
dart run tool/device_matrix_runner.dart \
  --record artifacts/device-matrix/ipv4-probe.json \
  --case NET-IPv4-01 \
  --status pass \
  --all-checks-pass \
  --measure legacyVideoLatencyP95Ms=420 \
  --measure audioStartupP95Ms=310 \
  --artifact artifacts/device-matrix/ipv4-status.jsonl \
  --artifact artifacts/device-matrix/ipv4-latency.csv \
  --note 'iOS server to Android client, 2.4 GHz'

dart run tool/device_matrix_runner.dart \
  --evaluate artifacts/device-matrix/ipv4-probe.json
```

Evaluation exits `0` only when physical-device inventory, the focused Flutter
preflight, completed operator checks, required artifacts and numeric gates all
pass. It exits `1` for a failed check/gate and `2` for incomplete or blocked
evidence. A generated template remains `planned`; generation alone is never a
test pass.

## Required devices

| Slot | Minimum hardware | OS lane | Purpose |
| --- | --- | --- | --- |
| iOS-old | Oldest supported iPhone with 3 GB RAM | minimum supported iOS | memory, thermal and camera interruption floor |
| iOS-current | Recent non-Pro iPhone | latest stable iOS | current AVFoundation/audio behavior |
| Android-low | 3–4 GB RAM, entry/mid SoC | oldest supported Android | encoder, GC and foreground-service floor |
| Android-current | Recent Pixel/Samsung class device | latest stable Android | current FGS, Doze and audio-focus behavior |

Each slot must run once as the room/server device and once as the watching
client. At least one cross-platform pair is required in both directions.

Archive `flutter devices --machine`, device model, OS version, app build/commit,
power/charger state, SSID/AP topology and role direction with every result.
Device names and IDs are evidence; simulator and emulator runs may be attached
as development notes but do not satisfy a physical slot.

Run two media lanes:

| Media lane | Configuration | Scope |
| --- | --- | --- |
| legacy | default build | MJPEG video + PCM16LE/WAV audio |
| WebRTC pilot | `MIMICAM_WEBRTC_PILOT=true` | one peer, H.264 + Opus with fallback verification |

## Network scenarios

Run every smoke case on 2.4 GHz Wi-Fi and the 30-minute soak on both 2.4 and
5 GHz. Use a controllable access point/netem bridge for impaired lanes.

| Lane | Loss | RTT | Available bandwidth | Pass intent |
| --- | ---: | ---: | ---: | --- |
| baseline | 0% | <20 ms | >20 Mbit/s | quality ceiling |
| mild | 1% | 50 ms | 8 Mbit/s | no audio interruption |
| weak | 3% | 150 ms | 3 Mbit/s | constrained profile |
| critical | 5% | 400 ms | 1 Mbit/s | survival/audio-first mode |
| recovery | critical → baseline | variable | stepped | recover without restart |

## Scenario checklist

- Video-only watch: camera active, microphone privacy indicator absent.
- Audio-only watch: microphone active, camera privacy indicator absent.
- Video+audio watch; run two simultaneous clients on legacy. Confirm the
  one-peer pilot returns/falls back cleanly for additional demand.
- Client screen lock/unlock and app background/foreground.
- Server background/foreground contract: iOS pauses camera and recovers the
  retained demand; Android foreground service retains the existing engine while
  the process lives. After process death, verify that capture stays stopped
  until a visible user restart (`START_NOT_STICKY`).
- Repeat background/foreground separately for the WebRTC pilot because its
  gateway owns `getUserMedia` tracks outside the legacy demand controller.
- Incoming phone call, Siri/Assistant, alarm and audio-focus loss/recovery.
- Wired/Bluetooth route connect, disconnect and `becoming noisy` behavior.
- Wi-Fi roam, DHCP address change, router restart and IPv4/IPv6-only LAN.
- Server/client process kill and supported recovery path.
- Low-power mode, charging transition, thermal serious and thermal critical.
- 30-minute quick soak for every PR candidate; 2-hour soak for release builds.

The machine-readable cases and their primary purpose are:

| Case ID | Gate being proven |
| --- | --- |
| `DEMAND-01` | independent camera/microphone/native-output ownership |
| `NET-IPv4-01` | IPv4 DNS-SD and MJPEG/WAV baseline |
| `NET-IPv6-01` | IPv6-only DNS-SD, bracketed authorities and host ICE |
| `NET-LinkLocal-01` | client-side scoped link-local parsing/reachability |
| `DISC-ReAdvertise-01` | stable TXT ID plus port/metadata refresh |
| `NET-Handoff-01` | DHCP/Wi-Fi endpoint rebind without re-pairing |
| `LIFE-iOS-01` | foreground-only iOS pause and retained-demand recovery |
| `LIFE-Android-01` | visible FGS start and no hidden process-death recovery |
| `AUDIO-iOS-01` | AVAudioSession interruption/route/media-reset recovery |
| `AUDIO-Android-01` | focus loss/gain, duck and becoming-noisy behavior |
| `THERMAL-01` | serious/critical governor reaction and stable recovery |
| `WEBRTC-Codec-01` | H.264, Opus, host ICE and single-peer cleanup |
| `WEBRTC-Fallback-01` | pilot failure/capacity cleanup then MJPEG/WAV |
| `SOAK-Legacy-01` | 30-minute legacy memory/backpressure/recovery trend |
| `SOAK-WebRTC-01` | 30-minute pilot stats, memory and track release trend |

## Network fixtures

- **IPv4-only:** use an isolated test SSID/VLAN with IPv6 router
  advertisements disabled. Do not change a shared office/home router for this
  test. Record the server IPv4, DNS-SD TXT and client-resolved address.
- **IPv6-only:** use an isolated SSID with multicast DNS and ULA or global IPv6
  working between clients. Confirm the result did not silently use IPv4 or a
  cellular path. NAT64 is optional but is not evidence for local IPv6
  reachability.
- **Scoped link-local:** use the zone identifier reported on the *client* that
  opens the socket. A server-side `en0`/`wlan0` name is not portable to another
  device. Record both interface names and the percent-escaped bracketed URI.
- **Handoff/rebind:** use two controlled APs in the same trusted lab LAN, or a
  DHCP lease change. Start the recovery clock only once the new endpoint is
  reachable/published; record old/new endpoint, stable TXT ID and the first
  healthy frame/audio timestamp.
- **Impairment:** apply shaping at a dedicated AP/bridge, not on either phone.
  Save the shaping configuration and recovery timestamp next to the result.

## Measurement method

- **Video latency:** place a millisecond timer or LED transition in the camera
  scene and record source plus client display with a third high-frame-rate
  camera. Use at least 30 transitions per lane; store raw samples and p50/p95.
- **Audio startup/recovery:** record the watch/focus transition and first
  audible tone on one external audio/video timeline. Use at least 20 trials for
  a p95; do not infer this from two unsynchronised phone wall clocks.
- **Reconnect:** record connectivity-restored/DNS-SD update and first healthy
  media event on one monotonic host or external recording timeline.
- **Memory slope:** discard the first five minutes. Use Android `dumpsys
  meminfo` or a profiler and iOS Instruments/Organizer memory data; keep raw
  samples. Compare trends within a platform, not absolute iOS versus Android
  RSS.
- **WebRTC codecs:** save `getStats` codec and selected candidate-pair records.
  Server `/test/status` should also show matching client transport telemetry.
- **Thermal:** poll `deviceResources`, `resourceGovernor` and media profile at
  five-second intervals. Never bypass OS thermal protection; stop on an OS
  warning, shutdown risk or unsafe touch temperature.
- **Native lifecycle/audio:** retain `flutter logs -d DEVICE_ID` (and platform
  diagnostics when available) around background, focus, interruption and route
  transitions. Check event sequence/counters as well as audible behavior.

## Release gates

| Metric | Gate |
| --- | ---: |
| video capture-to-receive p95 | <700 ms (legacy), <400 ms WebRTC pilot |
| audio startup-to-playout p95 | <500 ms |
| video reconnect p95 | <2 s |
| audio underruns | <1 per 10 minutes on baseline |
| crash / OOM | 0 |
| post-warm-up memory slope | <1 MiB per 10 minutes |
| critical thermal response | audio-first profile within 15 s |
| recovery after pressure clears | stable upgrade without oscillation |

Record the `/test/status` snapshots with
`tool/benchmarks/device_soak_harness.dart`. Archive JSONL output with device
model, OS/build, app commit, charger state and network lane in the filename.
Also record selected media transport, fallback reason, DNS-SD-resolved address
family, thermal state, resource-governor state and native audio interruption
counters in the run notes.

Example:

```sh
dart run tool/benchmarks/device_soak_harness.dart \
  --base-url http://192.168.1.42:8080 \
  --token TRUSTED_CLIENT_TOKEN \
  --duration-min 30 \
  --output artifacts/soak/android-low_2.4ghz_baseline.jsonl
```

Run the same harness alongside WebRTC `getStats` capture for the pilot soak.
The harness records server/client-reported bounded telemetry, but an external
profiler remains required for process memory and an external timeline remains
required for true glass-to-glass latency.

## Stop conditions and honest blocking

- Stop immediately on battery swelling, OS thermal warning/shutdown risk,
  repeated camera-service failure, unexpected cellular use or device damage.
- Mark a case `blocked`, not `pass`, when the lab cannot provide IPv6-only,
  controllable handoff, call interruption, required OS version or a second
  physical device.
- A WebRTC fallback is a pass only in `WEBRTC-Fallback-01`. It is a failure in
  the codec or WebRTC soak lane.
- Android background success must match the capability snapshot. Retaining an
  engine while camera remains Activity-owned is not evidence of service-owned
  camera hardware.
- iOS background camera pause is the intended contract; hidden continued
  capture is a failure, not an enhancement.
