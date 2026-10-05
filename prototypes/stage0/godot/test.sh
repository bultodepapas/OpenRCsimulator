#!/usr/bin/env bash
# Headless checks (no display needed). Fails if any script fails to parse or any test fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="$("$HERE/get-godot.sh")"
run() { timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }

echo "== parse check: every script"
(cd "$HERE" && find . -name '*.gd' -not -path './.godot/*' | sort) | while read -r f; do
  run --check-only --script "res://${f#./}" > /dev/null || { echo "parse error in $f"; exit 1; }
done

for t in "$HERE"/tests/test_*.gd; do
  echo "== $(basename "$t")"
  run --script "res://tests/$(basename "$t")"
done
