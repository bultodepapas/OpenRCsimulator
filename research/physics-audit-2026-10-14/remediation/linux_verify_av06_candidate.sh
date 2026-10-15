#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 SNAPSHOT_ROOT OUTPUT_LOG" >&2
  exit 2
fi

snapshot_root="$1"
output_log="$2"
mkdir -p "$(dirname "$output_log")"
cd "$snapshot_root"

{
  echo "Python: $(python3 --version)"
  echo "Snapshot: $snapshot_root"
  echo "== AV-06 generated aircraft --check"
  python3 research/avanti-s/av06/derive_physics.py --check
  echo "== AV-15 generated artifacts test"
  python3 research/avanti-s/av14/test_geometry_inventory.py
  echo "== AV-17-R2 polar builder tests"
  python3 research/avanti-s/av17-r2/test_build_polar.py
  echo "== generated Workshop descriptors --check"
  python3 research/aircraft-editor/build_descriptors.py --check
  echo "== Workshop exact-byte checkout tests"
  python3 research/aircraft-editor/test_descriptor_checkout.py
} 2>&1 | tee "$output_log"
