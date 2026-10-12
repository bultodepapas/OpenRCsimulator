#!/usr/bin/env bash
# FIELD-WORLD-PLAN FW-01: parity manifest for the unification steps. Renders a fixed set of views through every world
# assembly site (flight, the L1–L4 atmosphere fixture, Home, scenery views, the runway scenario) plus a headless trace,
# and writes one SHA-256 per output. FW-A steps must leave the manifest unchanged on the same machine and renderer.
#   tools/world/parity.sh <out-dir>                  write <out-dir>/manifest.txt
#   tools/world/parity.sh <out-dir> --compare <old>  also diff against an earlier manifest (exit 1 on any change)
# Display: xvfb-run when installed (CI-like), otherwise the current $DISPLAY (e.g. WSLg). Software GL (llvmpipe) with
# one thread is forced either way, so a run proves repeatability on this machine, never GPU performance.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(realpath -m "${1:?usage: parity.sh <out-dir> [--compare <manifest>]}")
COMPARE=""
[ "${2:-}" = "--compare" ] && COMPARE=$(realpath -m "${3:?--compare needs a manifest}")
GODOT=$("$ROOT/app/get-godot.sh")
rm -rf "$OUT"
mkdir -p "$OUT"
export LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1
# SC-02a: pin the original bare-field baseline; scenery views and the scenario opt in explicitly.
export OPENRC_SCENERY=off
export OPENRC_SCENERY_BIRDS=off OPENRC_ENGINE_SHADOWS=off
if command -v xvfb-run > /dev/null; then
  DISPLAY_RUN=(xvfb-run -a -s "-screen 0 1920x1080x24")
elif [ -n "${DISPLAY:-}" ]; then
  DISPLAY_RUN=()
else
  echo "parity.sh needs xvfb-run or a DISPLAY" >&2; exit 1
fi
timeout 300 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy --import > "$OUT/import.log" 2>&1 \
  || { tail -20 "$OUT/import.log"; exit 1; }

godot_view() { # godot_view <log> <godot args...>
  local log="$1"; shift
  timeout 300 "${DISPLAY_RUN[@]}" "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 --audio-driver Dummy \
    --resolution 1280x720 "$@" > "$log" 2>&1 || true
  if grep -E "^(SCRIPT |SHADER )?ERROR:" "$log"; then echo "engine error, see $log" >&2; exit 1; fi
}
flight() { # flight <name> <user args...>: main.gd capture mode (production field)
  local name="$1"; shift
  godot_view "$OUT/$name.log" -- --capture "$@" --out="$OUT/$name.png"
  [ -s "$OUT/$name.png" ] || { echo "capture $name failed"; tail -20 "$OUT/$name.log"; exit 1; }
}

for az in 0 90 180 270; do
  for el in 0 10; do flight "field-az$az-el$el" --t=1.5 --look_az=$az --look_el=$el --hide_airplane; done
done
flight field-top --t=1.5 --look_az=0 --look_el=-90 --look_alt=30 --hide_airplane
flight land-30m --t=1.5 --autozoom=0 --shadow=off
flight land-low3m --t=1.5 --alt=3 --autozoom=0
flight land-sun --t=1.5 --look_az=225 --look_el=25
flight land-az0-el0-100m --t=1.5 --look_az=0 --look_el=0 --look_alt=100
flight land-inspect --scripted --inspect
flight scenery-az180-el10 --t=1.5 --look_az=180 --look_el=10 --scenery=on --scenery_audio=off
flight scenery-az0-el0 --t=1.5 --look_az=0 --look_el=0 --scenery=on --scenery_audio=off

# The frozen L1–L4 reference fixture (overrides main.gd's field seam).
godot_view "$OUT/atmosphere.log" res://tests/fixtures/atmosphere_field.tscn -- --capture --scripted --out="$OUT/atmosphere.png"
[ -s "$OUT/atmosphere.png" ] || { echo "atmosphere capture failed"; exit 1; }

# Home (ui/home_scene.gd) through the real app route.
godot_view "$OUT/home.log" --script res://tests/capture_ui.gd -- --out="$OUT/home.png" --lang=en --screen=home
[ -s "$OUT/home.png" ] || { echo "home capture failed"; tail -20 "$OUT/home.log"; exit 1; }

# Scenery evidence views (scenery/capture_views.gd builds its own world).
godot_view "$OUT/views.log" --script res://scenery/capture_views.gd -- --scenery=on --scenery_audio=off --out="$OUT/views"
grep -q "SCENERY VIEWS DONE" "$OUT/views.log" || { echo "scenery views failed"; tail -20 "$OUT/views.log"; exit 1; }

# Runway scenario (scenery/runway_scenario.gd builds its own world); frames and manifest.
godot_view "$OUT/scenario.log" --script res://scenery/runway_scenario.gd -- --out="$OUT/scenario"
grep -q "RUNWAY SCENARIO DONE" "$OUT/scenario.log" || { echo "runway scenario failed"; tail -20 "$OUT/scenario.log"; exit 1; }

# Simulation identity: the trimmed-flight trace.
timeout 120 "$GODOT" --headless --path "$ROOT/app" --audio-driver Dummy -- --trace="$OUT/trace.csv" --t=3 > "$OUT/trace.log" 2>&1
[ -s "$OUT/trace.csv" ] || { echo "trace failed"; tail -20 "$OUT/trace.log"; exit 1; }
# The header's wall-clock creation time is the only line that changes run to run; hash everything else.
grep -v '^# created_utc:' "$OUT/trace.csv" > "$OUT/trace-content.csv"
rm "$OUT/trace.csv"

# Images and the trace by content. JSON sidecars carry timings and revisions, so they are not hashed.
(cd "$OUT" && find . -type f \( -name '*.png' -o -name '*.csv' \) | LC_ALL=C sort | xargs sha256sum) > "$OUT/manifest.txt.tmp"
mv "$OUT/manifest.txt.tmp" "$OUT/manifest.txt"
echo "parity: $(wc -l < "$OUT/manifest.txt") outputs hashed in $OUT/manifest.txt"
if [ -n "$COMPARE" ]; then
  if diff <(awk '{print $2, $1}' "$COMPARE") <(awk '{print $2, $1}' "$OUT/manifest.txt"); then
    echo "parity: identical to $COMPARE"
  else
    echo "parity: CHANGED against $COMPARE (lines above: < old, > new)"; exit 1
  fi
fi
