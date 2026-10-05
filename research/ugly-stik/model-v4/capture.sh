#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEARCH_DIR="$SCRIPT_DIR"
ROOT=""
while [[ "$SEARCH_DIR" != "/" ]]; do
	if [[ -f "$SEARCH_DIR/app/get-godot.sh" && -f "$SEARCH_DIR/app/project.godot" ]]; then
		ROOT="$SEARCH_DIR"
		break
	fi
	SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done
if [[ -z "$ROOT" ]]; then
	echo "Could not find repository root containing app/get-godot.sh" >&2
	exit 2
fi

OUT="$SCRIPT_DIR"
while (($#)); do
	case "$1" in
		--output-dir=*) OUT="${1#*=}" ;;
		--output-dir)
			shift
			if (($# == 0)); then echo "--output-dir requires a path" >&2; exit 2; fi
			OUT="$1"
			;;
		-h|--help)
			cat <<'EOF'
Usage: research/ugly-stik/model-v4/capture.sh [--output-dir PATH]

Captures the v4 inspection, readability36, details, motion, and beauty suites,
then repeats readability36 to compare all 36 PNG hashes. Builds review.html,
comparison.json, and diagnostic differences with the pinned Pillow version.
Existing suite outputs are never overwritten. model-v1, model-v2, and model-v3
are protected destinations.
EOF
			exit 0
			;;
		*) echo "Unknown argument: $1" >&2; exit 2 ;;
	esac
	shift
done

if [[ "$OUT" != /* ]]; then OUT="$ROOT/$OUT"; fi
OUT="$(realpath -m "$OUT")"
for protected_name in model-v1 model-v2 model-v3; do
	PROTECTED="$(realpath -m "$ROOT/research/ugly-stik/$protected_name")"
	if [[ "$OUT" == "$PROTECTED" || "$OUT" == "$PROTECTED/"* ]]; then
		echo "Refusing historical evidence destination: $OUT" >&2
		exit 2
	fi
done

mkdir -p "$OUT"
for artifact in inspection readability36 details motion beauty review.html comparison.json differences logs; do
	if [[ -e "$OUT/$artifact" ]]; then
		echo "Output already exists; refusing to overwrite $OUT/$artifact" >&2
		exit 2
	fi
done

PILLOW_VERSION="$(python3 -c 'import PIL; print(PIL.__version__)')"
if [[ "$PILLOW_VERSION" != "11.3.0" ]]; then
	echo "Pillow==11.3.0 is required; found $PILLOW_VERSION" >&2
	exit 2
fi

GODOT="$("$ROOT/app/get-godot.sh")"
WORK_ROOT="$(mktemp -d "$OUT/.capture-work.XXXXXX")"
PRIMARY="$WORK_ROOT/primary"
REPEAT="$WORK_ROOT/readability36-repeat"
LOGS="$WORK_ROOT/logs"
mkdir -p "$PRIMARY" "$REPEAT" "$LOGS"
trap 'rm -rf "$WORK_ROOT"' EXIT
{
	printf 'Pillow==11.3.0 exact version check: PASS\n'
	printf 'Installed Pillow: %s\n' "$PILLOW_VERSION"
	python3 --version
} > "$LOGS/pillow-version.txt"

run_capture() {
	local suite="$1"
	local output_dir="$2"
	local log_file="$3"
	local capture_status
	mkdir -p "$output_dir"
	set +e
	timeout 90 xvfb-run -a -s "-screen 0 1280x720x24" \
		env OPENRC_CAPTURE_RENDER_DRIVER=opengl3 \
		"$GODOT" --path "$ROOT/app" --script res://aircraft/inspect_model.gd \
		--rendering-driver opengl3 --audio-driver Dummy -- \
		"--output-dir=$output_dir" "--suite=$suite" 2>&1 | tee "$log_file"
	capture_status=${PIPESTATUS[0]}
	set -e
	if [[ "$capture_status" != 0 ]]; then
		echo "Godot $suite capture exited with status $capture_status; log: $log_file" >&2
		return "$capture_status"
	fi
	if rg -n '^(SCRIPT )?ERROR:' "$log_file"; then
		echo "Godot logged a script error for suite $suite; log: $log_file" >&2
		return 1
	fi
}

for suite in inspection readability36 details motion beauty; do
	echo "Capturing v4 suite: $suite"
	run_capture "$suite" "$PRIMARY/$suite" "$LOGS/$suite.log"
done

echo "Repeating readability36 in temporary storage for exact PNG hash comparison"
run_capture readability36 "$REPEAT" "$LOGS/readability36-repeat.log"
python3 "$SCRIPT_DIR/make_gallery.py" --root "$PRIMARY" \
	--baseline "$ROOT/research/ugly-stik/model-v3" --repeat-dir "$REPEAT"

for suite in inspection readability36 details motion beauty; do
	mv "$PRIMARY/$suite" "$OUT/$suite"
done
mv "$PRIMARY/review.html" "$OUT/review.html"
mv "$PRIMARY/comparison.json" "$OUT/comparison.json"
if [[ -d "$PRIMARY/differences" ]]; then mv "$PRIMARY/differences" "$OUT/differences"; fi
mv "$LOGS" "$OUT/logs"

echo "Evidence installed at: $OUT"
echo "Offline gallery: $OUT/review.html"
echo "Diagnostic comparison: $OUT/comparison.json"
