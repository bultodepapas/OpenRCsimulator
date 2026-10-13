#!/usr/bin/env bash
# Usage: research/ugly-stik/finish-v6/capture.sh <new output dir> [--app <app dir>] [--view <name>]
# Renders the US-V09a bench views with the pinned Godot under Xvfb. --app selects another checkout's app/ (A/B).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${1:?output directory}"; shift
APP="$ROOT/app"; VIEW=""
while (($#)); do
	case "$1" in
		--app) APP="$2"; shift ;;
		--view) VIEW="$2"; shift ;;
		*) echo "unknown argument $1" >&2; exit 2 ;;
	esac
	shift
done
[[ -e "$OUT" ]] && { echo "$OUT exists; choose a new directory" >&2; exit 2; }
mkdir -p "$OUT"
LP_NUM_THREADS="${LP_NUM_THREADS:-1}" xvfb-run -a -s "-screen 0 1280x720x24" "$("$ROOT/app/get-godot.sh")" \
	--path "$APP" --rendering-driver opengl3 --audio-driver Dummy \
	--script "$ROOT/research/ugly-stik/finish-v6/finish_bench.gd" -- --out="$(cd "$OUT" && pwd)" ${VIEW:+--view=$VIEW}
(cd "$OUT" && sha256sum ./*.png > SHA256SUMS)
