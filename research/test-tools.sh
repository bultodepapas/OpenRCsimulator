#!/usr/bin/env bash
# PT1h: bounded offline tool regressions; synthetic fixtures never close flight-validation gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
for test in \
  validation/weighing/test_reduce.py \
  validation/inertia/test_reduce.py \
  validation/static-prop/test_reduce.py \
  validation/rpm-step/test_reduce.py \
  validation/rpm-step/test_uncertainty.py \
  validation/ground-video/test_reduce.py \
  validation/roll-video/test_reduce.py \
  propwash/e0b7/test_reduce.py \
  radio-latency/test_reduce.py \
  propulsion/uiuc-import/test_import.py \
  propulsion/range-audit/test_audit.py \
  validation/metamorphic/test_runner.py; do
  echo "== $test"
  timeout 120 python3 "$ROOT/research/$test"
done
echo "Offline tool regressions passed; physical validation remains open."
