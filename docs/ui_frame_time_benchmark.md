# UI frame-time benchmark

The device benchmark measures Flutter engine `FrameTiming` samples while the
real server settings screen is being used. It covers two high-frequency paths:

- continuous advanced-setting slider drags;
- repeated forward and backward settings-list scrolls.

The benchmark must run in profile mode. Debug-mode timings are intentionally
rejected. It reports build, raster and total frame-time p50/p95 values, the
maximum frame time, and the ratios over 16.67 ms and 32 ms.

Run it on a connected physical device:

```bash
tool/benchmarks/run_ui_frame_benchmark.sh LGH8708da5c4b
```

The default regression gate is total frame-time p95 <= 35 ms for both slider
and scroll scenarios, with at least 30 measured frames per scenario. This gate
was calibrated on the legacy LG H870 / Android 9 lane: the optimized slider
measured 32.181-33.830 ms while the pre-optimization path measured 43.753 ms.
Override the gate for a faster device class when needed:

```bash
MIUCAM_FRAME_P95_BUDGET_MS=24 \
  tool/benchmarks/run_ui_frame_benchmark.sh DEVICE_ID
```

The host-side driver writes the machine-readable result to:

```text
build/performance/ui_frame_time_p95.json
```

For release comparisons, run the same APK/device/thermal state three times and
archive all JSON results. Do not compare debug runs or mix emulator and
physical-device baselines.
