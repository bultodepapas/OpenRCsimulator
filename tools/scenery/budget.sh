#!/usr/bin/env bash
# LU-34 scene budget: per-subsystem drawn cost of the production world in every postcard view at the
# historical 1280x720 measurement viewport, checked against tools/scenery/scene_budget.json (view-class totals,
# subsystem allocations, shadow casters, full-detail meshes, texture memory). Needs xvfb-run; llvmpipe
# counts are renderer submissions after culling and LOD, not GPU timings or 1080p/hardware qualification.
# About 40 minutes on llvmpipe. The pinned engine must match the historical budget before gating.
#   tools/scenery/budget.sh [out-dir] [--report-only]  (default: app/captures/scene-budget, gitignored)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT_ARG=""
REPORT_ONLY=false
for argument in "$@"; do
  case "$argument" in
    --report-only) REPORT_ONLY=true ;;
    -*) echo "unknown argument: $argument" >&2; exit 1 ;;
    *) if [ -n "$OUT_ARG" ]; then echo "only one output directory is allowed" >&2; exit 1; fi; OUT_ARG="$argument" ;;
  esac
done
OUT=$(realpath -m "${OUT_ARG:-$ROOT/app/captures/scene-budget}")
GODOT=$("$ROOT/app/get-godot.sh")
if [ "$REPORT_ONLY" = false ]; then
  EXPECTED_GODOT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["measurement"]["godot_cli"])' "$ROOT/tools/scenery/scene_budget.json")
  ACTUAL_GODOT=$("$GODOT" --version | tr -d '\r')
  if [ "$ACTUAL_GODOT" != "$EXPECTED_GODOT" ]; then
    echo "scene budget not qualified: pinned Godot $ACTUAL_GODOT differs from historical budget $EXPECTED_GODOT; re-baseline before applying it" >&2
    exit 1
  fi
else
  echo "report only: recording an attribution without applying the historical budget"
fi
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo "$OUT must be new or empty"; exit 1; fi
mkdir -p "$OUT"
timeout 300 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy --import >"$OUT/import.log" 2>&1 || { tail -20 "$OUT/import.log"; exit 1; }
LP_NUM_THREADS="${LP_NUM_THREADS:-4}" timeout 5400 xvfb-run -a -s '-screen 0 1920x1080x24' "$GODOT" --path "$ROOT/app" \
  --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 \
  --script "$ROOT/tools/scenery/attribute_views.gd" -- --out="$OUT/views" >"$OUT/attribution.log" 2>&1 || true
grep -q "ATTRIBUTION DONE" "$OUT/attribution.log" || { echo "attribution failed"; tail -30 "$OUT/attribution.log"; exit 1; }
if grep -E "^(SCRIPT )?ERROR:" "$OUT/attribution.log"; then echo "engine errors during attribution"; exit 1; fi
REPORT_ARGS=("$OUT/views" --json "$OUT/summary.json" --markdown "$OUT/summary.md")
if [ "$REPORT_ONLY" = false ]; then REPORT_ARGS+=(--budget "$ROOT/tools/scenery/scene_budget.json"); fi
python3 "$ROOT/tools/scenery/attribution_report.py" "${REPORT_ARGS[@]}"
