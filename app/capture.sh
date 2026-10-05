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
shot ""
shot "-inspect" --inspect
shot "-inspect-deflected" --inspect --roll=1 --pitch=1 --yaw=1
