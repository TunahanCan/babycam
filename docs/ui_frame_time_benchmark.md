# UI frame-time benchmark

The device benchmark measures Flutter engine `FrameTiming` samples while the
real server settings screen is being used. It covers two high-frequency paths:

- continuous advanced-setting slider drags;
- repeated forward and backward settings-list scrolls.

The benchmark must run in profile mode. Debug-mode timings are intentionally
rejected. It reports build, raster and total frame-time p50/p95 values, the
maximum frame time, and the ratios over 16.67 ms and 32 ms.

Build the benchmark in profile mode before connecting the driver. The driver
only attaches to an existing app; it never installs or removes a package.
`--keep-app-running` alone does not prevent Flutter's default installation
fallback from uninstalling an existing app and losing its data. Use a test
device and the update-only installation below; stop if installation fails.

```bash
flutter build apk --profile \
  --target=integration_test/ui_frame_time_benchmark_test.dart \
  --dart-define=MIUCAM_FRAME_P95_BUDGET_MS=35
adb -s DEVICE_ID install -r -t build/app/outputs/flutter-apk/app-profile.apk
```

Start the installed benchmark paused so the driver can attach:

```bash
adb -s DEVICE_ID shell am start -n com.miucam.app/.MainActivity \
  --ez start-paused true --ez enable-dart-profiling true
```

Find this process's Dart VM service URI in the device log. Forward its device
port with `adb -s DEVICE_ID forward tcp:0 tcp:DEVICE_VM_PORT`; use the returned
host port while preserving the URI's session path. Then attach:

```bash
tool/benchmarks/run_ui_frame_benchmark.sh DEVICE_ID \
  http://127.0.0.1:HOST_PORT/VM_SESSION_PATH/
```

Both arguments are required. A missing URI exits before invoking Flutter.
The runner uses `--use-existing-app --keep-app-running`; it does not build,
install, uninstall or clear app data. See the
[device setup guide](../integration_test/role_isolation_device.md) for the
existing-app workflow. After testing, restore the normal `lib/main.dart` APK
with `adb install -r` and remove the temporary adb port forward. Do not use
uninstall or data clearing to recover from a failed update installation.

The default regression gate is total frame-time p95 <= 35 ms for both slider
and scroll scenarios, with at least 30 measured frames per scenario. This gate
was calibrated on the legacy LG H870 / Android 9 lane: the optimized slider
measured 32.181-33.830 ms while the pre-optimization path measured 43.753 ms.
Override the gate for a faster device class **at build time**, then update-install
and attach to that new build using the steps above:

```bash
flutter build apk --profile \
  --target=integration_test/ui_frame_time_benchmark_test.dart \
  --dart-define=MIUCAM_FRAME_P95_BUDGET_MS=24
```

The default remains 35 ms when the define is omitted. An environment variable
on the attach command cannot change a budget compiled into the running app.

The host-side driver writes the machine-readable result to:

```text
build/performance/ui_frame_time_p95.json
```

For release comparisons, run the same APK/device/thermal state three times and
archive all JSON results. Do not compare debug runs or mix emulator and
physical-device baselines.
