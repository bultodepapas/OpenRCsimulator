#!/usr/bin/env bash
# Reproducible US-01/US-06 capture. Writes only inside this model-v3 directory.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
MODEL_V3_ROOT="$(realpath -m "$ROOT/research/ugly-stik/model-v3")"
DEFAULT_OUT="$MODEL_V3_ROOT/captures"
V1_DIR="$(realpath -m "$ROOT/research/ugly-stik/model-v1")"
V2_DIR="$(realpath -m "$ROOT/research/ugly-stik/model-v2")"
OUT="$DEFAULT_OUT"
ALLOW_REPLACE=0

while (($#)); do
	case "$1" in
		--output-dir=*) OUT="${1#*=}" ;;
		--output-dir)
			shift
			if (($# == 0)); then echo "--output-dir requires a path" >&2; exit 2; fi
			OUT="$1"
			;;
		--overwrite) ALLOW_REPLACE=1 ;;
		-h|--help)
			cat <<'EOF'
Usage: research/ugly-stik/model-v3/capture.sh [--output-dir PATH] [--overwrite]

Captures a 36-image orientation set twice, compares PNG SHA-256 hashes, then
writes the first run, manifest.json, and review.html to model-v3 captures.
The output path must be inside research/ugly-stik/model-v3. Existing output is
refused; --overwrite moves it to a timestamped sibling before writing.
EOF
			exit 0
			;;
		*) echo "Unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

if [[ "$OUT" != /* ]]; then OUT="$ROOT/$OUT"; fi
OUT="$(realpath -m "$OUT")"
if [[ "$OUT" == "$MODEL_V3_ROOT" || "$OUT" != "$MODEL_V3_ROOT/"* ]]; then
	echo "Refusing output outside model-v3: $OUT" >&2
	exit 2
fi
for protected in "$V1_DIR" "$V2_DIR"; do
	if [[ "$OUT" == "$protected" || "$OUT" == "$protected/"* ]]; then
		echo "Refusing to write into historical model evidence: $OUT" >&2
		exit 2
	fi
done
if [[ -e "$OUT" && "$ALLOW_REPLACE" != 1 ]]; then
	echo "Output exists; choose a fresh model-v3 directory or pass --overwrite: $OUT" >&2
	exit 2
fi
mkdir -p "$(dirname "$OUT")"

GODOT="$("$ROOT/app/get-godot.sh")"
WORK_ROOT="$(mktemp -d "$MODEL_V3_ROOT/.capture-work.XXXXXX")"
PRIMARY="$WORK_ROOT/primary"
REPEAT="$WORK_ROOT/repeat"
mkdir -p "$PRIMARY" "$REPEAT"
trap 'rm -rf "$WORK_ROOT"' EXIT

run_capture() {
	local output_dir="$1"
	local log_file="$2"
	set +e
	timeout 90 xvfb-run -a -s "-screen 0 1280x720x24" \
		env OPENRC_CAPTURE_RENDER_DRIVER=opengl3 \
		"$GODOT" --path "$ROOT/app" --script res://aircraft/inspect_model.gd \
		--rendering-driver opengl3 --audio-driver Dummy -- \
		"--output-dir=$output_dir" --suite=readability36 2>&1 | tee "$log_file"
	local run_status=${PIPESTATUS[0]}
	set -e
	if [[ "$run_status" != 0 ]]; then
		echo "Godot capture exited with status $run_status" >&2
		return "$run_status"
	fi
	if rg -q '^(SCRIPT )?ERROR:' "$log_file"; then
		echo "Godot logged a script error; see $log_file" >&2
		return 1
	fi
}

echo "Capturing primary orientation series…"
run_capture "$PRIMARY" "$WORK_ROOT/primary.log"
echo "Capturing independent repeat for PNG hash comparison…"
run_capture "$REPEAT" "$WORK_ROOT/repeat.log"
python3 "$ROOT/research/ugly-stik/model-v3/make_review_kit.py" \
	--captures "$PRIMARY" --repeat-captures "$REPEAT"

BACKUP=""
if [[ -e "$OUT" ]]; then
	BACKUP="${OUT}.replaced.$(date -u +%Y%m%dT%H%M%SZ).$$"
	if [[ -e "$BACKUP" ]]; then echo "Backup target already exists: $BACKUP" >&2; exit 2; fi
	mv "$OUT" "$BACKUP"
fi
if ! mv "$PRIMARY" "$OUT"; then
	if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then mv "$BACKUP" "$OUT"; fi
	echo "Could not install capture directory at $OUT" >&2
	exit 1
fi

echo "Capture set: $OUT"
echo "Review kit: $OUT/review.html"
if [[ -n "$BACKUP" ]]; then echo "Previous output preserved at: $BACKUP"; fi
