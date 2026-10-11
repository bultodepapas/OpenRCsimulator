#!/usr/bin/env bash
# FIELD-WORLD-PLAN FW-22/23 evidence: the production field at every time-of-day preset, from the pilot's eye.
# Five views per preset: the 30 m pilot view with the airplane, the horizon toward summer sunset (az 300°), toward
# the east (az 110°), the southern sky 30° up (moon and stars), and the close-up camera (the night kit). Writes <out>/<preset>-<view>.png and a contact sheet index.html.
#   tools/world/capture_times.sh [out-dir] [preset ...]     (default: app/captures/times, all presets)
# Display: xvfb-run when installed, otherwise $DISPLAY (e.g. WSLg). Software GL, one thread: repeatable, not a
# performance measurement.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(realpath -m "${1:-$ROOT/app/captures/times}")
shift || true
PRESETS=("$@")
[ ${#PRESETS[@]} -gt 0 ] || PRESETS=(dawn sunrise morning noon afternoon golden_hour sunset blue_hour night night_dark)
GODOT=$("$ROOT/app/get-godot.sh")
mkdir -p "$OUT"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1
if command -v xvfb-run > /dev/null; then DISPLAY_RUN=(xvfb-run -a -s "-screen 0 1920x1080x24"); else DISPLAY_RUN=(); fi
timeout 300 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy --import > "$OUT/import.log" 2>&1 \
  || { tail -20 "$OUT/import.log"; exit 1; }
shot() { # shot <name> <user args...>
  local name="$1"; shift
  timeout 300 "${DISPLAY_RUN[@]}" "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1280x720 -- --capture "$@" --out="$OUT/$name.png" > "$OUT/$name.log" 2>&1 || true
  if grep -E "^(SCRIPT |SHADER )?ERROR:" "$OUT/$name.log"; then echo "engine error in $name"; exit 1; fi
  [ -s "$OUT/$name.png" ] || { echo "capture $name failed"; tail -20 "$OUT/$name.log"; exit 1; }
}
{
  echo "<!doctype html><meta charset=utf-8><title>Time of day</title><style>body{background:#111;color:#ddd;font:14px sans-serif}"
  echo "img{width:19%;margin:2px}</style><h1>Time of day (FW-22/23)</h1>"
} > "$OUT/index.html"
for p in "${PRESETS[@]}"; do
  shot "$p-pilot" --time_of_day="$p" --t=1.5 --autozoom=0
  shot "$p-west" --time_of_day="$p" --t=1.5 --look_az=300 --look_el=4 --hide_airplane
  shot "$p-east" --time_of_day="$p" --t=1.5 --look_az=110 --look_el=8 --hide_airplane
  shot "$p-south" --time_of_day="$p" --t=1.5 --look_az=180 --look_el=30 --hide_airplane
  shot "$p-close" --time_of_day="$p" --t=1.5 --inspect
  echo "<h2>$p</h2><img src=$p-pilot.png><img src=$p-west.png><img src=$p-east.png><img src=$p-south.png><img src=$p-close.png>" >> "$OUT/index.html"
  echo "captured $p"
done
echo "contact sheet: $OUT/index.html"
