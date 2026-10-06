#!/usr/bin/env bash
# EX-02 visual review of the Extra 300S .60 preview: render the capture suites, then analyse them.
# Usage: research/extra-300/ex02/capture.sh [--output-dir NEW_DIR] [--suite inspection|orbit|detail|distance|scale|all]
# Default: --suite all into a new app/captures/extra-300s-review-<UTC> directory (untracked). With "all", the
# orthographic scale views are also rendered at 3840x2160 into scale_hr/ and review.py writes review/ (metrics,
# contact sheets, and plan overlays when the local plan raster cache exists). Needs xvfb-run; never overwrites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="$("$ROOT/app/get-godot.sh")"
OUT="$ROOT/app/captures/extra-300s-review-$(date -u +%Y%m%dT%H%M%SZ)"
SUITE=all
while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir) OUT="$2"; shift 2 ;;
    --suite) SUITE="$2"; shift 2 ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
done
python3 "$ROOT/assets/aircraft/extra-300s-60/compile_geometry.py" --check
python3 "$ROOT/assets/aircraft/extra-300s-60/compile_appearance.py" --check
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}" # same pinning as app/capture.sh: repeatable llvmpipe output
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
render() { # render <output dir> <suite> <WxH>
  timeout 600 xvfb-run -a -s "-screen 0 ${3}x24" "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 \
    --audio-driver Dummy --script res://aircraft/inspect_extra.gd -- --output-dir="$1" --suite="$2" --size="$3" \
    > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
  if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error during Extra capture"; exit 1; fi
}
render "$OUT" "$SUITE" 1280x720
if [ "$SUITE" = all ]; then
  render "$OUT/scale_hr" scale 3840x2160
  python3 "$ROOT/research/extra-300/ex02/review.py" "$OUT"
fi
echo "$OUT"
