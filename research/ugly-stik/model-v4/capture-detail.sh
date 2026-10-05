#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SEARCH_DIR="$SCRIPT_DIR"
ROOT=""
while [[ "$SEARCH_DIR" != "/" ]]; do
	if [[ -f "$SEARCH_DIR/app/get-godot.sh" && -f "$SEARCH_DIR/app/project.godot" ]]; then
		ROOT="$SEARCH_DIR"
		break
	fi
	SEARCH_DIR="$(dirname -- "$SEARCH_DIR")"
done
if [[ -z "$ROOT" ]]; then
	echo "Could not find repository root containing app/get-godot.sh" >&2
	exit 2
fi

OUTPUT_ARG=""
OUTPUT_SET=0
HELP=0
SUITE="showcase"
while (($#)); do
	case "$1" in
		--output-dir)
			if ((OUTPUT_SET)); then
				echo "--output-dir may be provided only once" >&2
				exit 2
			fi
			if (($# < 2)) || [[ "$2" == --* ]]; then
				echo "--output-dir requires a path" >&2
				exit 2
			fi
			OUTPUT_ARG="$2"
			OUTPUT_SET=1
			shift
			;;
		--output-dir=*)
			if ((OUTPUT_SET)); then
				echo "--output-dir may be provided only once" >&2
				exit 2
			fi
			OUTPUT_ARG="${1#*=}"
			if [[ -z "$OUTPUT_ARG" ]]; then
				echo "--output-dir requires a path" >&2
				exit 2
			fi
			OUTPUT_SET=1
			;;
		--engine) SUITE="engine" ;;
		-h|--help) HELP=1 ;;
		*)
			echo "Unknown argument: $1" >&2
			exit 2
			;;
	esac
	shift
done

if ((HELP)); then
	cat <<'EOF'
Usage: research/ugly-stik/model-v4/capture-detail.sh [--engine] [--output-dir PATH]

Capture the model-v4 showcase suite at 2560x1440 and build an offline review
gallery. Add --engine for only the eleven engine/exhaust closeups.
With no arguments, creates a unique directory under app/captures/.
The optional output directory must not already exist. model-v1 through
model-v4 are protected historical research destinations.
EOF
	exit 0
fi

CAPTURES_DIR="$ROOT/app/captures"
if ((OUTPUT_SET)); then
	if [[ "$OUTPUT_ARG" == /* ]]; then
		OUTPUT_RAW="$OUTPUT_ARG"
	else
		OUTPUT_RAW="$ROOT/$OUTPUT_ARG"
	fi
	while [[ "$OUTPUT_RAW" != "/" && "$OUTPUT_RAW" == */ ]]; do
		OUTPUT_RAW="${OUTPUT_RAW%/}"
	done
	OUTPUT_DIR="$(realpath -m -- "$OUTPUT_RAW")"
	if [[ -e "$OUTPUT_RAW" || -L "$OUTPUT_RAW" || -e "$OUTPUT_DIR" || -L "$OUTPUT_DIR" ]]; then
		echo "Output already exists; refusing to overwrite $OUTPUT_RAW" >&2
		exit 2
	fi
	for protected_name in model-v1 model-v2 model-v3 model-v4; do
		PROTECTED="$(realpath -m -- "$ROOT/research/ugly-stik/$protected_name")"
		if [[ "$OUTPUT_DIR" == "$PROTECTED" || "$OUTPUT_DIR" == "$PROTECTED/"* ]]; then
			echo "Refusing historical evidence destination: $OUTPUT_DIR" >&2
			exit 2
		fi
	done
fi

for command_name in timeout xvfb-run python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Required command not found: $command_name" >&2
		exit 2
	fi
done
GODOT="$("$ROOT/app/get-godot.sh")"

if ((OUTPUT_SET)); then
	mkdir -p -- "$(dirname -- "$OUTPUT_DIR")"
	if ! mkdir -- "$OUTPUT_DIR"; then
		echo "Could not create output directory (it may already exist): $OUTPUT_DIR" >&2
		exit 2
	fi
else
	mkdir -p -- "$CAPTURES_DIR"
	STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
	OUTPUT_DIR="$(mktemp -d -- "$CAPTURES_DIR/ugly-stik-detail-$STAMP-XXXX")"
fi

LOG_FILE="$OUTPUT_DIR/capture.log"
: > "$LOG_FILE"
echo "Capturing $SUITE into $OUTPUT_DIR"
set +e
timeout 180 xvfb-run -a -s "-screen 0 2560x1440x24" \
	env OPENRC_CAPTURE_RENDER_DRIVER=opengl3 \
	"$GODOT" --path "$ROOT/app" --script res://aircraft/inspect_model.gd \
	--rendering-driver opengl3 --audio-driver Dummy -- \
	"--output-dir=$OUTPUT_DIR" "--suite=$SUITE" 2>&1 | tee -a "$LOG_FILE"
CAPTURE_STATUS=${PIPESTATUS[0]}
set -e
if ((CAPTURE_STATUS != 0)); then
	echo "Godot $SUITE capture exited with status $CAPTURE_STATUS; log: $LOG_FILE" >&2
	exit "$CAPTURE_STATUS"
fi
if grep -Eq '^(SCRIPT )?ERROR:' "$LOG_FILE"; then
	echo "Godot logged an error during the $SUITE capture; log: $LOG_FILE" >&2
	exit 1
fi

python3 "$SCRIPT_DIR/make_detail_gallery.py" "$OUTPUT_DIR/manifest.json" \
	--output "$OUTPUT_DIR/review.html"
echo "Offline gallery: $OUTPUT_DIR/review.html"
