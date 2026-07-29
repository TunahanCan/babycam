#!/usr/bin/env bash
set -euo pipefail

device_id="${1:-}"
budget_ms="${MIUCAM_FRAME_P95_BUDGET_MS:-35}"

if [[ -z "$device_id" ]]; then
  echo "Usage: $0 DEVICE_ID"
  echo "Set MIUCAM_FRAME_P95_BUDGET_MS to override the default 35 ms p95 gate."
  flutter devices
  exit 64
fi

flutter drive \
  --profile \
  --no-pub \
  --device-id "$device_id" \
  --driver test_driver/ui_frame_time_benchmark_driver.dart \
  --target integration_test/ui_frame_time_benchmark_test.dart \
  --dart-define "MIUCAM_FRAME_P95_BUDGET_MS=$budget_ms"
