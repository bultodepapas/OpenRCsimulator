#!/usr/bin/env bash
# EX-02: render the Extra 300S .60 preview views (front/side/top/bottom/obliques, rest and full deflection).
# Usage: research/extra-300/ex02/capture.sh [--output-dir NEW_DIR]   (needs xvfb-run; never overwrites a directory)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="$("$ROOT/app/get-godot.sh")"
OUT="$ROOT/app/captures/extra-300s-ex02-$(date -u +%Y%m%dT%H%M%SZ)"
if [ "${1:-}" = "--output-dir" ]; then OUT="$2"; fi
python3 "$ROOT/assets/aircraft/extra-300s-60/compile_geometry.py" --check
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}" # same pinning as app/capture.sh: repeatable llvmpipe output
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 \
  --audio-driver Dummy --script res://aircraft/inspect_extra.gd -- --output-dir="$OUT" > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error during Extra capture"; exit 1; fi
echo "$OUT"
