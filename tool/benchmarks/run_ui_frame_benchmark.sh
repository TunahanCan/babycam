#!/usr/bin/env bash
set -euo pipefail

device_id="${1:-}"
vm_service_uri="${2:-}"

if [[ $# -ne 2 || -z "$device_id" || -z "$vm_service_uri" ]]; then
  echo "Usage: $0 DEVICE_ID VM_SERVICE_URI" >&2
  echo "Attach to an already installed and running profile benchmark." >&2
  echo "Build-time budget and update-only setup: docs/ui_frame_time_benchmark.md" >&2
  exit 64
fi

if [[ ! "$vm_service_uri" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "VM_SERVICE_URI must be the running app's HTTP Dart VM service URI." >&2
  exit 64
fi

flutter drive \
  --profile \
  --use-existing-app "$vm_service_uri" \
  --keep-app-running \
  --no-pub \
  --device-id "$device_id" \
  --driver test_driver/ui_frame_time_benchmark_driver.dart
