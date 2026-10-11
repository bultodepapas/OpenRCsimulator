#!/usr/bin/env bash
# Exact production Apply versus fresh Main parity, with equivalent startup allocation in independent processes.
# The retained render_probe.gd is the historical same-process diagnostic and exploratory cost probe.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-/tmp/openrc-tod09b-process-parity}"
exec python3 "$HERE/process_oracle.py" --out "$OUT" --mutation-control
