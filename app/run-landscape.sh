#!/usr/bin/env bash
# Explicit preview of the complete field; scenery remains opt-in in the normal app.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPENRC_SCENERY=on exec "$("$HERE/get-godot.sh")" --path "$HERE" "$@"
