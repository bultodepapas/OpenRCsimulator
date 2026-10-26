#!/usr/bin/env bash
set -euo pipefail
HERE="$PWD/app"
GODOT="$("$HERE/get-godot.sh")"
count=0
while read -r f; do
  count=$((count+1))
  python3 "$HERE/../tools/godot/run_checked.py" --timeout 60 --out-dir "$OPENRC_CHECK_OUT" -- "$GODOT" --headless --path "$HERE" --audio-driver Dummy --check-only --script "res://${f#./}" > /dev/null || { echo "parse error in $f"; exit 1; }
  if (( count % 100 == 0 )); then echo "parsed $count scripts: $f"; fi
done < <(cd "$HERE" && find . -name '*.gd' -not -path './.godot/*' -not -path './captures/*' | sort)
echo "all-script parse: $count scripts passed"
