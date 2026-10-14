#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: tools/ci/check-local.sh {quick|full|release}" >&2
}

# Reject malformed invocations before platform checks or any command that can create outputs.
if [[ "$#" -ne 1 ]]; then
	usage
	exit 2
fi
MODE="$1"
case "$MODE" in
	quick|full|release) ;;
	*)
		usage
		echo "Unknown check mode: $MODE" >&2
		exit 2
		;;
esac

if [[ "$(uname -s)" != "Linux" ]]; then
	echo "check-local.sh requires Linux or WSL2 Ubuntu." >&2
	exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

echo "== CI scope regressions =="
python3 tools/ci/test_scope.py

echo "== Source, schema, and generator checks =="
tools/ci/check-sources.sh

echo "== Offline tool regressions =="
research/test-tools.sh

if [[ "$MODE" == "full" || "$MODE" == "release" ]]; then
	echo "== Native Linux ground-vehicle build and parity =="
	python3 research/rc-monster-truck/native/build.py --jobs 2 --godot "$(app/get-godot.sh)"

	echo "== Production app tests =="
	app/test.sh

	echo "== Production app capture checks =="
	app/capture.sh
fi

if [[ "$MODE" == "release" ]]; then
	echo "== Release exports =="
	app/export.sh
fi
