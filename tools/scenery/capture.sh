#!/usr/bin/env bash
# SCENERY-PLAN SC-03: scenery evidence captures and budget check. Renders every view of app/scenery/postcards.gd with the
# production field, sky and haze: once with scenery off (the baseline) and twice with it on (byte-repeat). Then
# tools/scenery/check_views.py checks the scenery's own cost per view (on − off) against the plan's budgets.
# Needs xvfb-run; llvmpipe numbers prove counts and repeatability, not GPU performance.
#   tools/scenery/capture.sh [out-dir]      (default: app/captures/scenery, gitignored)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(realpath -m "${1:-$ROOT/app/captures/scenery}")
GODOT=$("$ROOT/app/get-godot.sh")
rm -rf "$OUT"
mkdir -p "$OUT"
timeout 300 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy --import >"$OUT/import.log" 2>&1 || { tail -20 "$OUT/import.log"; exit 1; }
run() { # $1 = label, $2 = on|off
  LP_NUM_THREADS=1 timeout 900 xvfb-run -a -s '-screen 0 1920x1080x24' "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 \
    --audio-driver Dummy --resolution 1280x720 --script res://scenery/capture_views.gd -- \
    --scenery="$2" --scenery_audio=off --out="$OUT/$1" >"$OUT/$1.log" 2>&1 || true
  grep -q "SCENERY VIEWS DONE" "$OUT/$1.log" || { echo "capture $1 failed"; tail -30 "$OUT/$1.log"; exit 1; }
  if grep -E "^(SCRIPT )?ERROR:" "$OUT/$1.log"; then echo "engine errors during capture $1"; exit 1; fi
}
run off off
run on on
run on-repeat on
python3 "$ROOT/tools/scenery/check_views.py" "$OUT"
