#!/usr/bin/env bash
# PT1h: bounded offline tool regressions; synthetic fixtures never close flight-validation gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
for test in \
  native-kernel/test_verification.py \
  native-kernel/test_verification_families.py \
  native-kernel/test_fleet_campaign.py \
  native-kernel/test_package.py \
  native-kernel/test_devtools.py \
  performance/test_session_baseline.py \
  performance/test_native_summary.py \
  performance/test_frame_diagnose.py \
  performance/test_texture_inventory.py \
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
  propulsion/el2a-p1/test_compare.py \
  propulsion/el2a-p2/test_compare_events.py \
  propulsion/el2a-e1/test_trace_checks.py \
  propulsion/el2a-p3/test_compare_envelope.py \
  propulsion/el2a-p3/test_verify_motor.py \
  validation/metamorphic/test_runner.py; do
  echo "== $test"
  timeout 120 python3 "$ROOT/research/$test"
done
echo "== FL-04: flight log analysis and CLI contracts"
timeout 120 python3 -m unittest discover -s "$ROOT/tools/flight_log" -p 'test_*.py'
echo "== PT1h-R1: checked Godot runner failure diagnostics"
timeout 120 python3 -m unittest discover -s "$ROOT/tools/godot" -p 'test_*.py'
echo "== PT1h-R7: agent debug bridge client"
timeout 60 python3 -m unittest discover -s "$ROOT/tools/debug" -p 'test_*.py'
echo "== DT-LNX-02c/03a: release integrity and Linux ABI inventory"
timeout 120 python3 -m unittest discover -s "$ROOT/tools/release" -p 'test_*.py'

echo "Offline tool regressions passed; physical validation remains open."
