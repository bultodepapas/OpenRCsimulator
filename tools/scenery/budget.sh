#!/usr/bin/env bash
# LU-34 scene budget: per-subsystem drawn cost of the production world in every postcard view at the
# 1280x720 qualification viewport, checked against tools/scenery/scene_budget.json (view-class totals,
# subsystem allocations, shadow casters, full-detail meshes, texture memory). Needs xvfb-run; llvmpipe
# counts are renderer submissions after culling and LOD, not GPU timings. About 40 minutes on llvmpipe.
#   tools/scenery/budget.sh [out-dir]      (default: app/captures/scene-budget, gitignored)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(realpath -m "${1:-$ROOT/app/captures/scene-budget}")
GODOT=$("$ROOT/app/get-godot.sh")
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo "$OUT must be new or empty"; exit 1; fi
mkdir -p "$OUT"
timeout 300 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy --import >"$OUT/import.log" 2>&1 || { tail -20 "$OUT/import.log"; exit 1; }
LP_NUM_THREADS="${LP_NUM_THREADS:-4}" timeout 5400 xvfb-run -a -s '-screen 0 1920x1080x24' "$GODOT" --path "$ROOT/app" \
  --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 \
  --script "$ROOT/tools/scenery/attribute_views.gd" -- --out="$OUT/views" >"$OUT/attribution.log" 2>&1 || true
grep -q "ATTRIBUTION DONE" "$OUT/attribution.log" || { echo "attribution failed"; tail -30 "$OUT/attribution.log"; exit 1; }
if grep -E "^(SCRIPT )?ERROR:" "$OUT/attribution.log"; then echo "engine errors during attribution"; exit 1; fi
python3 "$ROOT/tools/scenery/attribution_report.py" "$OUT/views" --json "$OUT/summary.json" --markdown "$OUT/summary.md" \
  --budget "$ROOT/tools/scenery/scene_budget.json"
