#!/usr/bin/env bash
# Run the TOD-09b in-place/fresh-build image and cost probe with Compatibility under Xvfb.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${1:-/tmp/openrc-tod09b}"
GODOT_BIN="$("$ROOT/app/get-godot.sh")"
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"
revision="$(git -C "$ROOT" describe --always --dirty)"
export OPENRC_CODE_REVISION="${OPENRC_CODE_REVISION:-$revision}"
mkdir -p "$OUT"
for mode in off on; do
	probe_out="$OUT/render-$mode"
	mkdir -p "$probe_out"
	echo "== TOD-09b Compatibility probe, scenery=$mode, output=$probe_out"
	timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" \
		"$GODOT_BIN" --path "$ROOT/app" --rendering-driver opengl3 --audio-driver Dummy \
		--script "$HERE/render_probe.gd" -- --scenery="$mode" --probe-out="$probe_out"
done
