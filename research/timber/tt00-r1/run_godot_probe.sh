#!/usr/bin/env bash
set -euo pipefail
exec python3 "$(dirname -- "${BASH_SOURCE[0]}")/run_godot_probe.py" "$@"
