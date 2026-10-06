#!/usr/bin/env bash
# Release builds (PT1): Windows, Linux and macOS exports into <repo>/dist, each checked, zipped, with SHA256SUMS.
#   - the exported Linux binary flies the app-level trimmed-flight check headless (proves the data is in the pack);
#   - the macOS zip is a universal, ad-hoc signed app bundle (tests/check_macos_export.py);
#   - UI-04a: one build identity (git describe, commit, dirty, commit date), computed here once, names the ZIPs, is
#     written into every pack as res://build_info.json (addons/build_info) and is checked in the exported binary's
#     trace header; the .exe and Info.plist carry project.godot's numeric config/version (tests/check_build_versions.py).
# Needs: app/get-godot.sh, app/get-templates.sh (downloads 1.28 GB once), zip, python3, git. No display or GPU.
# Usage: app/export.sh   (the version is always git describe: the app and the ZIP names cannot disagree)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
GODOT="$("$HERE/get-godot.sh")"
"$HERE/get-templates.sh" > /dev/null
[ $# -eq 0 ] || { echo "export.sh takes no version argument any more: the build identity is git describe (UI-04a)"; exit 1; }
VERSION="$(git -C "$ROOT" describe --tags --always --dirty)"
NUMERIC="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$HERE/project.godot")"
[[ "$NUMERIC" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "project.godot config/version must be x.y.z (found '$NUMERIC')"; exit 1; }
if [[ "$VERSION" =~ ^v([0-9]+\.[0-9]+\.[0-9]+) ]] && [ "${BASH_REMATCH[1]}" != "$NUMERIC" ]; then
  echo "tag ${BASH_REMATCH[1]} (git describe: $VERSION) does not match project.godot config/version $NUMERIC"; exit 1
fi
export OPENRC_BUILD_DESCRIBE="$VERSION"
export OPENRC_BUILD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
export OPENRC_BUILD_DIRTY="$([[ "$VERSION" == *-dirty ]] && echo 1 || echo 0)"
export OPENRC_BUILD_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
echo "== build identity: $VERSION (commit $OPENRC_BUILD_COMMIT, $OPENRC_BUILD_DATE), numeric $NUMERIC"
DIST="$ROOT/dist"
rm -rf "$DIST" && mkdir -p "$DIST/linux" "$DIST/windows" "$DIST/macos"
run() { timeout 600 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT

echo "== import (a fresh clone has no .godot cache)"
run --import > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
for preset in Linux Windows macOS; do
  case "$preset" in
    Linux) out="$DIST/linux/openrc-simulator.x86_64" ;;
    Windows) out="$DIST/windows/OpenRC Simulator.exe" ;;
    macOS) out="$DIST/macos/OpenRC Simulator.zip" ;;
  esac
  echo "== export $preset"
  run --export-release "$preset" "$out" > "$LOG" 2>&1 || { cat "$LOG"; echo "export $preset failed"; exit 1; }
  if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error while exporting $preset"; exit 1; fi
  [ -s "$out" ] || { echo "export $preset produced no file"; exit 1; }
done

echo "== smoke test: the exported Linux binary flies trimmed level flight"
TRACE="$(mktemp --suffix=.csv)"
timeout 120 "$DIST/linux/openrc-simulator.x86_64" --headless --audio-driver Dummy -- --trace="$TRACE" --t=3 > "$LOG" 2>&1 \
  || { cat "$LOG"; echo "exported binary failed"; exit 1; }
if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error in the exported binary"; exit 1; fi
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE"
grep -qxF "# app_build: $VERSION" "$TRACE" || { grep "^# app_" "$TRACE"; echo "the exported binary does not report build $VERSION"; exit 1; }
echo "exported binary reports build $VERSION"; rm -f "$TRACE"

echo "== macOS bundle: universal and ad-hoc signed"
python3 "$HERE/tests/check_macos_export.py" "$DIST/macos/OpenRC Simulator.zip"

echo "== version fields: .exe VERSIONINFO and Info.plist carry config/version $NUMERIC"
python3 "$HERE/tests/check_build_versions.py" "$DIST/windows/OpenRC Simulator.exe" "$DIST/macos/OpenRC Simulator.zip" "$NUMERIC"

echo "== packages"
(cd "$DIST/linux" && zip -q -9 "$DIST/openrc-simulator-$VERSION-linux-x86_64.zip" openrc-simulator.x86_64)
(cd "$DIST/windows" && zip -q -9 "$DIST/openrc-simulator-$VERSION-windows-x86_64.zip" "OpenRC Simulator.exe")
cp "$DIST/macos/OpenRC Simulator.zip" "$DIST/openrc-simulator-$VERSION-macos-universal.zip"
(cd "$DIST" && sha256sum openrc-simulator-*.zip > SHA256SUMS && cat SHA256SUMS && ls -la openrc-simulator-*.zip)
