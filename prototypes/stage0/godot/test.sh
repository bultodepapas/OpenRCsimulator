#!/usr/bin/env bash
# Headless known-answer tests (no display needed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="$("$HERE/get-godot.sh")"
"$GODOT" --headless --path "$HERE" --audio-driver Dummy --script res://tests/test_frames.gd
