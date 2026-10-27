#!/bin/bash
# Export session_probe.gd inside an official release template (VQ-01c / NK-0). Templates ignore
# --path and --script, so a hard-linked snapshot of app/ gets the probe plus a wrapper main scene and
# is exported with the Linux preset. The shared app/ is never written: only project.godot and the
# Godot-written cache files are real copies in the snapshot.
# Usage: build.sh <output binary path>   (needs the matching export template installed, see README)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=$(realpath -m "$1")
SNAP=$REPO/tmp/release-probe-snap-$$
mkdir -p "$SNAP"
trap 'case "$SNAP" in "$REPO"/tmp/release-probe-snap-*) find "$SNAP" -delete;; esac' EXIT
cp -al "$REPO/app" "$SNAP/app"
find "$SNAP/app/captures" -delete 2>/dev/null || true
for f in .godot/editor .godot/uid_cache.bin .godot/global_script_class_cache.cfg project.godot; do
	rm -rf "${SNAP:?}/app/$f"; cp -a "$REPO/app/$f" "$SNAP/app/$f"
done
for s in "$REPO"/*/; do n=$(basename "$s"); case $n in app|tmp) ;; *) ln -s "$s" "$SNAP/$n";; esac; done
mkdir -p "$SNAP/app/perf_probe"
cp "$REPO/research/performance/session_probe.gd" "$SNAP/app/perf_probe/session_probe.gd"
cp "$REPO/research/performance/release_session_probe/release_wrapper.gd" "$REPO/research/performance/release_session_probe/release_wrapper.tscn" "$SNAP/app/perf_probe/"
sed -i 's|^run/main_scene=.*|run/main_scene="res://perf_probe/release_wrapper.tscn"|' "$SNAP/app/project.godot"
mkdir -p "$(dirname "$OUT")"
"$("$REPO/app/get-godot.sh")" --headless --path "$SNAP/app" --export-release "Linux" "$OUT"
echo "release session probe: $OUT"
