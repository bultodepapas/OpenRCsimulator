#!/usr/bin/env bash
# AUD-06: render one bench scenario with Godot Movie Maker and keep only <name>.wav and <name>.json.
# Usage: tools/audio/bench.sh <out-dir> <name> <scenario> [flight args...]
#   e.g. tools/audio/bench.sh /tmp/bench stik-sweep sweep --audio-seed=4102026
#   --engine-only mutes the environment bus for loudness calibration.
# Needs Xvfb on a display-less host. Analyze with tools/audio/bench_analyze.py.
# OPENRC_APP=<dir> renders another copy of app/ (e.g. a disposable baseline before a change).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"; name="$2"; scenario="$3"; shift 3
godot="$("$repo/app/get-godot.sh")"
frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT
runner=()
if [ -z "${DISPLAY:-}" ]; then runner=(xvfb-run -a); fi
"${runner[@]}" "$godot" --path "${OPENRC_APP:-$repo/app}" --rendering-driver opengl3 --resolution 480x270 \
	--write-movie "$frames/$name.png" --fixed-fps 60 \
	--script "$repo/tools/audio/bench.gd" -- --scenario="$scenario" --out="$out/$name" "$@"
mv "$frames/$name.wav" "$out/$name.wav"
echo "$out/$name.wav $out/$name.json"
