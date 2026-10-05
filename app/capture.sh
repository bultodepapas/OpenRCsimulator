#!/usr/bin/env bash
# Capture mode: render t = 3.0 s at 1280x720 under Xvfb (software OpenGL), save PNGs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="$("$HERE/get-godot.sh")"
mkdir -p "$HERE/captures" # untracked in git: a fresh clone does not have it
# L0b: llvmpipe thread count pinned. 1 and 12 threads gave byte-identical captures on Mesa 25.2.8 (2026-10-05), so
# this is cheap insurance for machines with other core counts (CI runners); 1 thread costs ~5 s per run.
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"
COUNTERS="$HERE/captures/landscape-counters.txt"
: > "$COUNTERS"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
shot() { # shot <file suffix> <user args...>
  local name="capture$1" out="$HERE/captures/capture$1.png"; shift
  # timeout: a script error must fail the capture, never hang it.
  timeout 60 xvfb-run -a -s "-screen 0 1280x720x24" \
    "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy -- --capture "$@" --out="$out" > "$LOG" 2>&1 || true
  # Shaders only compile with a real renderer, so engine errors (e.g. a broken sky shader) surface here, not in test.sh.
  if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error during capture $name"; exit 1; fi
  sed -n "s|^saved .* (error 0) \(draw_calls=.*\)|$name \1|p" "$LOG" >> "$COUNTERS"
  [ -s "$out" ] || { cat "$LOG"; echo "capture $name failed"; exit 1; }
}
# Stage 0/1 views on the scripted circle (stable references).
shot "" --scripted
shot "-inspect" --scripted --inspect
shot "-inspect-deflected" --scripted --inspect --roll=1 --pitch=1 --yaw=1
# Physics (trimmed flight) at t = 1.5 s, pilot view (auto-zoom) and close-up.
shot "-physics" --t=1.5
shot "-physics-inspect" --t=1.5 --inspect
# D7: the same pilot view without auto-zoom (the readability problem auto-zoom addresses).
shot "-physics-nozoom" --t=1.5 --autozoom=0
# D7: a low pass at 0.8 m, close-up: the ground shadow under the airplane (from the pilot at 77 m the grazing
# angle makes it < 1 px thick: the shadow is a cue for close passes and landings).
shot "-physics-low-inspect" --t=1.5 --alt=0.8 --inspect
# L0 (LANDSCAPE-PLAN): landscape review set. Horizon from the pilot's eye at 4 azimuths, level and 10° up; the 30 m
# trimmed view and the 3 m low pass without auto-zoom; a view toward the sun (Spec.ATMOSPHERE: azimuth 225°, elevation 45°).
for az in 0 90 180 270; do
  for el in 0 10; do shot "-land-az${az}-el${el}" --t=1.5 --look_az=$az --look_el=$el; done
done
shot "-land-30m" --t=1.5 --autozoom=0
shot "-land-low3m" --t=1.5 --alt=3 --autozoom=0
shot "-land-sun" --t=1.5 --look_az=225 --look_el=25
# L0c: the airplane-in-view landscape shots again without the airplane: the background for the readability metric.
shot "-land-30m-noplane" --t=1.5 --autozoom=0 --hide_airplane
shot "-land-low3m-noplane" --t=1.5 --alt=3 --autozoom=0 --hide_airplane
# L0b: straight down from 30 m over the pilot station: ground tiling must be judged from above (investigation 06).
shot "-land-top" --t=1.5 --look_az=0 --look_el=-90 --look_alt=30
echo "render counters per view (draw calls and primitives): $COUNTERS"
cat "$COUNTERS"
python3 "$HERE/tests/check_landscape_captures.py" "$HERE/captures"
# L0c: airplane readability against its background (pinned, hashed Python environment in .tools/visual-venv).
# L1b thresholds (investigation 09): the low pass keeps the airplane readable against the sky.
"$("$HERE/tests/visual-env.sh")" "$HERE/tests/compare_captures.py" readability "$HERE/captures" \
  --require "capture-land-low3m.png:-0.40:0.15:30:25"
# C7: flight trace of the same throw, headless (no display needed).
timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy -- --trace="$HERE/captures/trace-physics.csv" --t=1.5
