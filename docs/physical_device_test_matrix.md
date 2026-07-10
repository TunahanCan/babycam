# MimiCam physical-device release matrix

This matrix validates the media pipeline on real hardware. Emulator/simulator
results do not qualify a release because camera, microphone, thermal throttling,
audio focus and background execution differ materially from a physical device.

**Execution status:** this file is the required test specification and release
gate, not a completed result report. No lane passes until a dated JSONL log and
device/network metadata have been archived for it.

## Required devices

| Slot | Minimum hardware | OS lane | Purpose |
| --- | --- | --- | --- |
| iOS-old | Oldest supported iPhone with 3 GB RAM | minimum supported iOS | memory, thermal and camera interruption floor |
| iOS-current | Recent non-Pro iPhone | latest stable iOS | current AVFoundation/audio behavior |
| Android-low | 3–4 GB RAM, entry/mid SoC | oldest supported Android | encoder, GC and foreground-service floor |
| Android-current | Recent Pixel/Samsung class device | latest stable Android | current FGS, Doze and audio-focus behavior |

Each slot must run once as the room/server device and once as the watching
client. At least one cross-platform pair is required in both directions.

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
