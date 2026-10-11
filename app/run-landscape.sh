#!/usr/bin/env bash
# Explicit complete-field launcher; also overrides an inherited scenery-off environment.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OPENRC_SCENERY=on exec "$("$HERE/get-godot.sh")" --path "$HERE" "$@"
