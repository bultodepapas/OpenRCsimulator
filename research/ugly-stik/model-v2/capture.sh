#!/usr/bin/env bash
# Model v2 evidence, separate from v1 and the simulator's official captures.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
GODOT="$("$ROOT/app/get-godot.sh")"
OUT="$ROOT/research/ugly-stik/model-v2/captures"
mkdir -p "$OUT"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
timeout 60 xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$ROOT/app" --script res://aircraft/inspect_model.gd \
  --rendering-driver opengl3 --audio-driver Dummy -- --output-dir="$OUT" 2>&1 | tee "$LOG"
if grep -qE '^(SCRIPT )?ERROR:' "$LOG"; then
  exit 1
fi
