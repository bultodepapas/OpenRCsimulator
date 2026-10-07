#!/usr/bin/env bash
# SC-01(d): scenery technique probe and style bake-off (docs/SCENERY-PLAN.md).
# Runs probe.gd inside a scratch copy of app/ made from `git archive HEAD`, so app/ and other tracks' uncommitted
# work are never touched. Needs xvfb-run and the downloaded candidate archives (README.md lists them and their SHA-256).
#   SC01_ASSETS=<folder with the downloads> research/scenery/sc01/run.sh <out-dir> [case ...]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
SRC=${SC01_ASSETS:?set SC01_ASSETS to the folder holding the downloaded archives}
OUT=$(realpath -m "${1:?usage: run.sh <out-dir> [case ...]}")
shift
CASES=("${@:-merge depth ground groundbug style}")
read -r -a CASES <<<"${CASES[*]}"
GODOT=$("$ROOT/app/get-godot.sh")
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sc01.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Candidate assets: unpacked into a fresh folder, read only by Godot's runtime glTF/FBX importers.
A="$WORK/assets"
mkdir -p "$A/kenney-car" "$A/quaternius-cars" "$A/polypizza"
cp -r "$SRC/kenney-car/x/Models/GLB format/." "$A/kenney-car/"
unzip -q -j "$SRC/qi-lowpoly-cars/1148381.zip" "Realistic Car Pack - Nov 2018/FBX/*" -d "$A/quaternius-cars"
cp "$SRC"/pp/glb/*.glb "$A/polypizza/"

git -C "$ROOT" archive HEAD app | tar -x -C "$WORK"
mkdir -p "$WORK/app/sc01"
cp "$HERE/probe.gd" "$WORK/app/sc01/"
LP_NUM_THREADS=1 timeout 600 "$GODOT" --headless --path "$WORK/app" --import >"$WORK/import.log" 2>&1 || {
  tail -20 "$WORK/import.log"; exit 1; }

mkdir -p "$OUT"
for c in "${CASES[@]}"; do
  rm -rf "${OUT:?}/$c"
  LP_NUM_THREADS=1 timeout 1200 xvfb-run -a -s '-screen 0 1920x1080x24' "$GODOT" --path "$WORK/app" \
    --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --script res://sc01/probe.gd \
    -- --case="$c" --out="$OUT/$c" --assets="$A" --repo="$ROOT" >"$OUT/$c.log" 2>&1 || true
  if ! grep -q "SC01 DONE $c" "$OUT/$c.log"; then echo "case $c failed:"; tail -30 "$OUT/$c.log"; exit 1; fi
  if grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/$c.log" | grep -v "VSync" >/dev/null; then
    echo "case $c logged engine/script errors:"; grep -E "SCRIPT ERROR|Parse Error|ERROR:" "$OUT/$c.log" | head; exit 1
  fi
  echo "case $c ok"
done
