#!/usr/bin/env bash
# Capture mode: render t = 3.0 s at 1280x720 under Xvfb (software OpenGL), save PNGs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="$("$HERE/get-godot.sh")"
shot() { # shot <file suffix> <user args...>
  local out="$HERE/captures/capture$1.png"; shift
  # timeout: a script error must fail the capture, never hang it.
  timeout 60 xvfb-run -a -s "-screen 0 1280x720x24" \
    "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy -- --capture "$@" --out="$out"
}
# Stage 0/1 views on the scripted circle (stable references).
shot "" --scripted
shot "-inspect" --scripted --inspect
shot "-inspect-deflected" --scripted --inspect --roll=1 --pitch=1 --yaw=1
# C6: physics (gravity only) at t = 1.5 s, pilot view and close-up.
shot "-physics" --t=1.5
shot "-physics-inspect" --t=1.5 --inspect
# C7: flight trace of the same throw, headless (no display needed).
timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy -- --trace="$HERE/captures/trace-physics.csv" --t=1.5
