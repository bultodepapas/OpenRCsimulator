#!/usr/bin/env bash
# Explicit complete-field launcher; also overrides an inherited scenery-off environment.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if python3 "$HERE/../tools/testqueue/entry.py" landscape -- "$@"; then
  exit 0
else
  queue_status=$?
  [[ "$queue_status" == 100 ]] || exit "$queue_status"
fi
if [[ -n "${OPENRC_TESTQUEUE_CONTEXT:-}" ]]; then
  trap 'queue_status=$?; python3 "$HERE/../tools/testqueue/entry.py" receipt landscape "$queue_status"' EXIT
fi
OPENRC_SCENERY=on "$("$HERE/get-godot.sh")" --path "$HERE" "$@"
