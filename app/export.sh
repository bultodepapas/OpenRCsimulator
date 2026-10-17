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
[ $# -eq 0 ] || { echo "export.sh takes no version argument any more: the build identity is git describe (UI-04a)"; exit 1; }
VERSION="$(git -C "$ROOT" describe --tags --always --dirty)"
# git describe prefers annotated tags when several tags name HEAD. A release
# must carry its triggering tag even when another tag exists on that commit.
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  RELEASE_TAG="${GITHUB_REF#refs/tags/}"
  [[ "$RELEASE_TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]] \
    || { echo "release tag must be vX.Y.Z or vX.Y.Z-prerelease: $RELEASE_TAG"; exit 1; }
  [ "$(git -C "$ROOT" rev-parse "$GITHUB_REF^{commit}")" = "$(git -C "$ROOT" rev-parse HEAD)" ] \
    || { echo "release tag $RELEASE_TAG does not identify HEAD"; exit 1; }
  [[ "$VERSION" != *-dirty ]] || { echo "tagged release requires a clean working tree"; exit 1; }
  VERSION="$RELEASE_TAG"
fi
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
GODOT="$("$HERE/get-godot.sh")"
"$HERE/get-templates.sh" > /dev/null
DIST="$ROOT/dist"
rm -rf "$DIST" && mkdir -p "$DIST/linux" "$DIST/windows" "$DIST/macos"
run() { timeout 600 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }
LOG="$(mktemp)"
PACK_PROBE="$(mktemp -d)"
HOST_PROBE="$(mktemp -d)"
trap 'rm -f "$LOG"; rm -rf "$PACK_PROBE" "$HOST_PROBE"' EXIT

echo "== import (a fresh clone has no .godot cache)"
run --import > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error while importing"; exit 1; fi
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

echo "== native package artifacts: verify both platform rows against exported binaries"
python3 - "$HERE/native/ground_vehicle/build-receipt.json" \
  "$DIST/linux/libopenrc_ground_vehicle.so" "$DIST/windows/openrc_ground_vehicle.dll" <<'PYRECEIPT'
import hashlib
import json
import pathlib
import re
import sys

receipt_path, linux_path, windows_path = map(pathlib.Path, sys.argv[1:])
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
if not isinstance(receipt, dict) or receipt.get("format") != "openrc-ground-vehicle-native-receipt":
    raise SystemExit("native build receipt is missing or has the wrong format")
if receipt.get("backend") != "native" or type(receipt.get("abi_version")) is not int or receipt["abi_version"] != 1:
    raise SystemExit("native receipt does not identify the supported native ABI")
backend_version = receipt.get("backend_version")
solver_version = receipt.get("solver_version")
if not isinstance(backend_version, str) or not backend_version or not isinstance(solver_version, str) or not solver_version:
    raise SystemExit("native receipt has no backend/solver identity")
platforms = receipt.get("platforms")
if not isinstance(platforms, dict):
    raise SystemExit("native receipt has no platform map")
common = ("backend", "backend_version", "abi_version", "solver_version")
hex64 = re.compile(r"[0-9a-f]{64}\Z")
expected_paths = {"linux": linux_path, "windows": windows_path}
declared_source = receipt.get("source_sha256")
if "source_sha256" in receipt and (not isinstance(declared_source, str) or not hex64.fullmatch(declared_source)):
    raise SystemExit("native receipt has an invalid envelope source_sha256")
source_hash = declared_source if "source_sha256" in receipt else None
verified = {}
for platform, binary_path in expected_paths.items():
    row = platforms.get(platform)
    if not isinstance(row, dict):
        raise SystemExit(f"native receipt lacks the {platform} platform row")
    if row.get("platform") != platform or row.get("architecture") != "x86_64":
        raise SystemExit(f"native {platform} receipt row has the wrong platform/architecture")
    if type(row.get("abi_version")) is not int or row["abi_version"] != 1:
        raise SystemExit(f"native {platform} receipt row has a non-integer or unsupported ABI version")
    for key in common:
        if row.get(key) != receipt.get(key):
            raise SystemExit(f"native {platform} receipt row disagrees with envelope field {key}")
    for key in ("source_sha256", "toolchain_sha256", "binary_sha256"):
        value = row.get(key)
        if not isinstance(value, str) or not hex64.fullmatch(value):
            raise SystemExit(f"native {platform} receipt has an invalid {key}")
    if source_hash is None:
        source_hash = row["source_sha256"]
    elif row["source_sha256"] != source_hash:
        raise SystemExit(f"native {platform} receipt row disagrees with the shared source identity")
    if not isinstance(row.get("toolchain"), dict):
        raise SystemExit(f"native {platform} receipt has no toolchain details")
    if not binary_path.is_file():
        raise SystemExit(f"export omitted required native artifact: {binary_path}")
    actual_hash = hashlib.sha256(binary_path.read_bytes()).hexdigest()
    if actual_hash != row["binary_sha256"]:
        raise SystemExit(f"exported {platform} native artifact differs from its receipt: {binary_path}")
    verified[platform] = {
        "binary": str(binary_path),
        "binary_sha256": actual_hash,
        "toolchain_sha256": row["toolchain_sha256"],
    }
print(json.dumps({
    "format": "openrc-native-export-artifacts-v1",
    "backend": receipt["backend"],
    "backend_version": backend_version,
    "abi_version": receipt["abi_version"],
    "solver_version": solver_version,
    "source_sha256": source_hash,
    "platforms": verified,
}, sort_keys=True))
PYRECEIPT

echo "== prepare empty-project host probe with the exact Linux editor sidecar"
[[ "$(uname -s)" == "Linux" ]] || { echo "native package smoke requires a Linux host editor"; exit 1; }
HOST_GODOT="$HOST_PROBE/$(basename "$GODOT")"
HOST_SIDECAR="$HOST_PROBE/libopenrc_ground_vehicle.so"
cp "$GODOT" "$HOST_GODOT"
chmod 755 "$HOST_GODOT"
cp "$DIST/linux/libopenrc_ground_vehicle.so" "$HOST_SIDECAR"
cmp -s "$GODOT" "$HOST_GODOT" || { echo "host editor staging changed the pinned binary"; exit 1; }
cmp -s "$DIST/linux/libopenrc_ground_vehicle.so" "$HOST_SIDECAR" || { echo "host native sidecar staging changed the exported binary"; exit 1; }
echo "host editor $(sha256sum "$HOST_GODOT" | cut -d ' ' -f1); Linux sidecar $(sha256sum "$HOST_SIDECAR" | cut -d ' ' -f1)"

echo "== smoke test: the exported Linux binary flies trimmed level flight"
TRACE="$(mktemp --suffix=.csv)"
timeout 120 "$DIST/linux/openrc-simulator.x86_64" --headless --audio-driver Dummy -- --trace="$TRACE" --t=3 > "$LOG" 2>&1 \
  || { cat "$LOG"; echo "exported binary failed"; exit 1; }
if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error in the exported binary"; exit 1; fi
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3
grep -qxF "# app_build: $VERSION" "$TRACE" || { grep "^# app_" "$TRACE"; echo "the exported binary does not report build $VERSION"; exit 1; }
echo "exported binary reports build $VERSION"; rm -f "$TRACE"

echo "== macOS bundle: universal and ad-hoc signed"
python3 "$HERE/tests/check_macos_export.py" "$DIST/macos/OpenRC Simulator.zip"

echo "== version fields: .exe VERSIONINFO and Info.plist carry config/version $NUMERIC"
python3 "$HERE/tests/check_build_versions.py" "$DIST/windows/OpenRC Simulator.exe" "$DIST/macos/OpenRC Simulator.zip" "$NUMERIC"

echo "== default field and compiled loader are present in all three packs (empty-project smoke)"
# Do not use --path app: that would mask a missing JSON with the loose source file.
FIELD_SHA="$(sha256sum "$HERE/data/fields/default.json" | cut -d ' ' -f1)"
python3 - "$DIST/macos/OpenRC Simulator.zip" "$PACK_PROBE/macos.pck" <<'PYPACK'
import pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    packs = [name for name in archive.namelist() if name.endswith(".pck")]
    assert len(packs) == 1, packs
    pathlib.Path(sys.argv[2]).write_bytes(archive.read(packs[0]))
PYPACK
for pack in "$DIST/linux/openrc-simulator.x86_64" "$DIST/windows/OpenRC Simulator.exe" "$PACK_PROBE/macos.pck"; do
  timeout 60 "$GODOT" --headless --path "$PACK_PROBE" --audio-driver Dummy \
    --script "$HERE/tests/check_field_pack.gd" -- "$pack" "$FIELD_SHA" > "$LOG" 2>&1 \
    || { cat "$LOG"; echo "field pack check failed: $pack"; exit 1; }
  if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then cat "$LOG"; exit 1; fi
  cat "$LOG"
  echo "host-side resource check on Linux editor; this does not execute the target OS binary: $pack"
  timeout 60 "$HOST_GODOT" --headless --path "$PACK_PROBE" --audio-driver Dummy \
    --main-pack "$pack" --script "$ROOT/research/aircraft-standardization/rotorcraft_package_smoke.gd" > "$LOG" 2>&1 \
    || { cat "$LOG"; echo "rotorcraft pack check failed: $pack"; exit 1; }
  if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; exit 1; fi
  cat "$LOG"
done

echo "== exported Linux pack selects its exact host-native implementation from an empty project"
timeout 60 "$HOST_GODOT" --headless --path "$PACK_PROBE" --audio-driver Dummy \
  --main-pack "$DIST/linux/openrc-simulator.x86_64" \
  --script "$HERE/tests/check_native_pack.gd" > "$LOG" 2>&1 \
  || { cat "$LOG"; echo "native package identity check failed"; exit 1; }
if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; exit 1; fi
cat "$LOG"

echo "== packages"
# Include exporter-managed GDExtension libraries beside the executable, preserving their relative paths.
(cd "$DIST/linux" && zip -q -9 -r "$DIST/openrc-simulator-$VERSION-linux-x86_64.zip" .)
(cd "$DIST/windows" && zip -q -9 -r "$DIST/openrc-simulator-$VERSION-windows-x86_64.zip" .)
cp "$DIST/macos/OpenRC Simulator.zip" "$DIST/openrc-simulator-$VERSION-macos-universal.zip"
(cd "$DIST" && sha256sum openrc-simulator-*.zip > SHA256SUMS && cat SHA256SUMS && ls -la openrc-simulator-*.zip)
