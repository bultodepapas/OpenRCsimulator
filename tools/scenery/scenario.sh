#!/usr/bin/env bash
# The runway scenario (app/scenery/runway_scenario.gd): the Ugly Stik at the runway threshold, engine idling, then a
# scripted takeoff, captured from five cameras at fixed times with a per-frame manifest. Writes <root>/latest, keeps
# the previous run as <root>/previous, and builds <root>/latest/report.html: filmstrips, automatic sync checks and a
# frame-by-frame comparison with the previous run. Runs inside app/capture.sh (CI uploads it with the captures).
#   tools/scenery/scenario.sh [root] [-- extra scenario args, e.g. --aircraft=gp-extra-300s-60 --scenery=off]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(realpath -m "${1:-$ROOT/app/captures/scenario}")
shift || true
[ "${1:-}" = "--" ] && shift
GODOT=$("$ROOT/app/get-godot.sh")
VPY=$("$ROOT/app/tests/visual-env.sh")
mkdir -p "$OUT"
if [ -d "$OUT/latest" ]; then
  rm -rf "$OUT/previous"
  mv "$OUT/latest" "$OUT/previous"
fi
LOG="$OUT/latest.log"
LP_NUM_THREADS=1 timeout 900 xvfb-run -a -s '-screen 0 1920x1080x24' "$GODOT" --path "$ROOT/app" --rendering-driver opengl3 \
  --audio-driver Dummy --resolution 1280x720 --script res://scenery/runway_scenario.gd -- --out="$OUT/latest" "$@" >"$LOG" 2>&1 || true
grep -q "RUNWAY SCENARIO DONE" "$LOG" || { echo "runway scenario failed:"; tail -30 "$LOG"; exit 1; }
if grep -E "^(SCRIPT )?ERROR:" "$LOG"; then echo "engine errors during the runway scenario (see $LOG)"; exit 1; fi
mv "$LOG" "$OUT/latest/run.log"
PREV=()
STATUS=0
[ -f "$OUT/previous/scenario.json" ] && PREV=("$OUT/previous")
"$VPY" -I "$ROOT/tools/scenery/scenario_report.py" "$OUT/latest" "${PREV[@]}" || STATUS=$?
STATUS=${STATUS:-0}
# Light history for reviewing changes over many runs: manifest, checks, comparison and filmstrips (full frames only in
# latest/previous: ~50 MB a run). Newest 30 kept; history/index.html shows them as a timeline.
REV=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo norev)
[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] && REV="$REV-dirty"
STAMP="$(date -u +%Y%m%d-%H%M%S)-$REV"
mkdir -p "$OUT/history/$STAMP"
cp "$OUT/latest"/scenario.json "$OUT/latest"/sync.json "$OUT/latest"/filmstrip-*.png "$OUT/history/$STAMP/"
[ -f "$OUT/latest/compare.json" ] && cp "$OUT/latest/compare.json" "$OUT/history/$STAMP/"
ls -1d "$OUT"/history/*/ | sort | head -n -30 | xargs -r rm -rf
"$VPY" -I "$ROOT/tools/scenery/scenario_report.py" --history "$OUT/history"
exit "$STATUS" # a failed sync check still fails the run, after the history is saved
