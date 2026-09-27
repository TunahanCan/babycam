#!/usr/bin/env bash
set -euo pipefail

# Select an installed iPhone simulator without pinning CI to a device model.
# Flutter simulator artifacts must already exist (flutter build ios --debug --simulator).
miucam_simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
for runtime, devices in runtimes.items():
    if ".iOS-" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator is installed.")
')"

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$miucam_simulator_id" \
  -destination-timeout 120 \
  -only-testing:RunnerTests \
  -resultBundlePath build/ios/native-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO
