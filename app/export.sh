#!/usr/bin/env bash
# Release builds (PT1/DT-LNX-02a): Windows, Linux and macOS exports into one new output directory per run.
#   - the exported Linux binary qualifies NK-3 and flies the app-level trimmed-flight check headless;
#   - the macOS zip is a universal, ad-hoc signed app bundle (tests/check_macos_export.py);
#   - UI-04a: one build identity (git describe, commit, dirty, commit date), computed here once, names the ZIPs, is
#     written into every pack as res://build_info.json (addons/build_info) and is checked in the exported binary's
#     trace header; the .exe and Info.plist carry project.godot's numeric config/version (tests/check_build_versions.py).
# Needs: app/get-godot.sh, app/get-templates.sh (downloads 1.36 GB once), zip, binutils, python3, git. No display or GPU.
# Usage: app/export.sh [--output-dir NEW_DIRECTORY] (default: <repo>/dist/export-XXXXXXXX).
# The version is always git describe. Existing outputs are never replaced, including after a failed run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$(cd "$HERE/.." && pwd -P)"
OUTPUT_ARG=""
case "$#:${1:-}" in
  0:) ;;
  2:--output-dir) OUTPUT_ARG="$2"; [ -n "$OUTPUT_ARG" ] || { echo "--output-dir must name a new directory" >&2; exit 1; } ;;
  1:--help) echo "Usage: app/export.sh [--output-dir NEW_DIRECTORY] (default: dist/export-XXXXXXXX; Linux host required)"; exit 0 ;;
  *) echo "export.sh takes no version argument: use [--output-dir NEW_DIRECTORY]; build identity is git describe (UI-04a)" >&2; exit 1 ;;
esac
VERSION="$(git -C "$ROOT" describe --tags --always --dirty)"
# Godot discovers untracked project resources too; git describe only sees
# tracked changes. Ignored generated native artifacts have their own receipt
# validation below and do not change the source identity.
UNTRACKED_APP="$(git -C "$ROOT" ls-files --others --exclude-standard -- app/)"
if [[ -n "$UNTRACKED_APP" && "$VERSION" != *-dirty ]]; then
  VERSION="${VERSION}-dirty"
fi
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
NUMERIC="$(sed -n 's/\r$//; s/^config\/version="\(.*\)"$/\1/p' "$HERE/project.godot")"
[[ "$NUMERIC" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "project.godot config/version must be x.y.z (found '$NUMERIC')"; exit 1; }
if [[ "$VERSION" =~ ^v([0-9]+\.[0-9]+\.[0-9]+) ]] && [ "${BASH_REMATCH[1]}" != "$NUMERIC" ]; then
  echo "tag ${BASH_REMATCH[1]} (git describe: $VERSION) does not match project.godot config/version $NUMERIC"; exit 1
fi
export OPENRC_BUILD_DESCRIBE="$VERSION"
export OPENRC_BUILD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
export OPENRC_BUILD_DIRTY="$([[ "$VERSION" == *-dirty ]] && echo 1 || echo 0)"
export OPENRC_BUILD_DATE="$(git -C "$ROOT" show -s --format=%cI HEAD)"
echo "== build identity: $VERSION (commit $OPENRC_BUILD_COMMIT, $OPENRC_BUILD_DATE), numeric $NUMERIC"
[[ "$(uname -s)" == Linux ]] || { echo "export and native package smoke require a Linux host" >&2; exit 1; }
# Imports and NK-3 prepare mutate this checkout. Keep independent checkouts parallel,
# but refuse a second exporter here before it can touch shared source-side caches.
GIT_DIR="$(realpath -- "$(git -C "$ROOT" rev-parse --absolute-git-dir)")"
GIT_COMMON_DIR="$(git -C "$ROOT" rev-parse --git-common-dir)"
[[ "$GIT_COMMON_DIR" == /* ]] || GIT_COMMON_DIR="$ROOT/$GIT_COMMON_DIR"
GIT_COMMON_DIR="$(realpath -- "$GIT_COMMON_DIR")"
EXPORT_LOCK="$GIT_DIR/openrc-export.lock"
if [[ -L "$EXPORT_LOCK" || ( -e "$EXPORT_LOCK" && ! -f "$EXPORT_LOCK" ) ]]; then
  echo "export lock must be a regular file: $EXPORT_LOCK" >&2; exit 1
fi
exec 9>>"$EXPORT_LOCK"
flock -n 9 || { echo "another export is using this checkout; use a separate checkout or wait" >&2; exit 1; }
validate_output_path() {
  case "$1/" in
    "$HERE/"*|"$GIT_DIR/"*|"$GIT_COMMON_DIR/"*) echo "export output must be outside app/ and Git metadata: $1" >&2; exit 1 ;;
  esac
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]] || { echo "export output path must not contain newlines" >&2; exit 1; }
}
if [[ -n "$OUTPUT_ARG" ]]; then
  # Check the requested path before realpath, which otherwise follows dangling symlinks.
  [[ ! -e "$OUTPUT_ARG" && ! -L "$OUTPUT_ARG" ]] || { echo "export output already exists; choose a new directory: $OUTPUT_ARG" >&2; exit 1; }
  DIST="$(realpath -m -- "$OUTPUT_ARG")"
  validate_output_path "$DIST"
  mkdir -p -- "$(dirname "$DIST")"
  mkdir -- "$DIST" # Atomic reservation; never reuse or delete a competing run's directory.
else
  DIST_PARENT="$(realpath -m -- "$ROOT/dist")"
  validate_output_path "$DIST_PARENT"
  mkdir -p -- "$DIST_PARENT"
  DIST="$(mktemp -d "$DIST_PARENT/export-XXXXXXXX")"
fi
echo "== export output: $DIST"
mkdir -- "$DIST/linux" "$DIST/windows" "$DIST/macos"
LOG=""
PACK_PROBE=""
HOST_PROBE=""
cleanup() {
  local export_status=$?
  [[ -z "$LOG" ]] || rm -f -- "$LOG"
  [[ -z "$PACK_PROBE" ]] || rm -rf -- "$PACK_PROBE"
  [[ -z "$HOST_PROBE" ]] || rm -rf -- "$HOST_PROBE"
  if [[ "$export_status" -ne 0 ]]; then
    echo "export failed; partial output retained: $DIST" >&2
  fi
}
trap cleanup EXIT
GODOT="$("$HERE/get-godot.sh")"
TEMPLATE_DIR="$("$HERE/get-templates.sh")"
run() { timeout 600 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }
LOG="$(mktemp)"
PACK_PROBE="$(mktemp -d)"
HOST_PROBE="$(mktemp -d)"

echo "== import (a fresh clone has no .godot cache)"
run --import > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
if grep -qE "^(SCRIPT |SHADER )?ERROR:" "$LOG"; then cat "$LOG"; echo "engine error while importing"; exit 1; fi
echo "== capture source, tool and native receipt identities before export"
python3 "$ROOT/tools/release/manifest.py" capture --root "$ROOT" --editor "$GODOT" \
  --templates "$TEMPLATE_DIR" --output "$DIST/.release-inputs.json"

echo "== prepare verified NK-3 export identity"
python3 "$ROOT/research/native-kernel/package.py" prepare
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
  if [[ "$preset" == Linux ]]; then
    echo "== stage verified NK-3 sidecars for the exact exported executable"
    python3 "$ROOT/research/native-kernel/package.py" finalize \
      --executable "$out" --template "$TEMPLATE_DIR/linux_release.x86_64"
  fi
done

echo "== native package artifacts: verify both platform rows against exported binaries"
python3 - "$HERE/native/ground_vehicle/build-receipt.json" \
  "$DIST/linux/libopenrc_ground_vehicle.so" "$DIST/windows/openrc_ground_vehicle.dll" \
  "$ROOT/research/rc-monster-truck/native/build.py" <<'PYRECEIPT'
import hashlib
import importlib.util
import json
import pathlib
import re
import sys

receipt_path, linux_path, windows_path, builder_path = map(pathlib.Path, sys.argv[1:])
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("openrc_native_receipt_builder", builder_path)
if spec is None or spec.loader is None:
    raise SystemExit(f"could not load native receipt validator: {builder_path}")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
lock = builder.locked.load_lock()
expected_source_hash = builder.source_digest()
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
    builder.validate_platform_receipt(platform, row, lock, expected_source_hash)
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

mkdir -p "$ROOT/tmp"
NK3_EVIDENCE="$(mktemp -d "$ROOT/tmp/nk3-export-XXXXXXXX")"
mkdir -p "$NK3_EVIDENCE/user-data"
LINUX_EXE="$DIST/linux/openrc-simulator.x86_64"
echo "== NK-3: qualify the exact exported Linux executable"
for mode in stage lifecycle replay helicopter helicopter-radio; do
  required_markers=(--require-text "NATIVE_QUALIFICATION preloaded=false"
                    --require-text "NATIVE_QUALIFICATION mode=$mode verdict=pass")
  case "$mode" in
    helicopter) required_markers+=(--require-text "NK3_NATIVE_HELICOPTER_NATIVE verdict=pass") ;;
    helicopter-radio) required_markers+=(--require-text "NK3_NATIVE_HELICOPTER_RADIO_NATIVE verdict=pass") ;;
  esac
  XDG_DATA_HOME="$NK3_EVIDENCE/user-data" python3 "$ROOT/tools/godot/run_checked.py" --timeout 600 --out-dir "$NK3_EVIDENCE/checks" \
    --label "nk3-package-$mode" "${required_markers[@]}" -- \
    "$LINUX_EXE" --headless --audio-driver Dummy -- --quick-flight "--native-qualification=$mode"
done

echo "== NK-3: replay the recorded native flight with the shipped executable and player CLI"
mapfile -d '' -t NK3_NATIVE_LOGS < <(find "$NK3_EVIDENCE/user-data" -type f -name native.orfl -print0)
if [[ "${#NK3_NATIVE_LOGS[@]}" -ne 1 ]]; then
  echo "expected exactly one recorded native flight in $NK3_EVIDENCE/user-data"; exit 1
fi
python3 "$ROOT/tools/flight_log/flight_log.py" replay "${NK3_NATIVE_LOGS[0]}" \
  --release-executable "$LINUX_EXE" --out "$NK3_EVIDENCE/player-replay" --timeout 300
python3 - "$NK3_EVIDENCE/player-replay/replay.json" <<'PYREPLAY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
baseline = report.get("baseline_stage_backend")
if not isinstance(baseline, dict) or baseline.get("backend") != "native" \
        or report.get("current_stage_backend") != baseline:
    raise SystemExit("player replay did not use the recorded native stage")
print("player CLI exactly replayed the recorded native stage")
PYREPLAY

echo "== NK-3: compare reference and native production sessions in the exported executable"
python3 "$ROOT/research/performance/session_baseline.py" --release-executable --godot "$LINUX_EXE" \
  --out "$NK3_EVIDENCE/production-pair" --aircraft jensen-das-ugly-stik-60 --case trim,runway \
  --warmup-ticks 24 --sample-ticks 240 --repeats 1 --compare-backends --timeout 300

echo "== NK-3: check default selection, explicit reference and fallback in the exported executable"
python3 "$ROOT/research/native-kernel/test_default_route.py" --release-executable "$LINUX_EXE" \
  --out "$NK3_EVIDENCE/default-route"

echo "== smoke test: the exported Linux binary flies trimmed level flight with native physics"
TRACE="$NK3_EVIDENCE/trimmed.csv"
python3 "$ROOT/tools/godot/run_checked.py" --timeout 180 --out-dir "$NK3_EVIDENCE/checks" \
  --label nk3-package-trimmed -- "$LINUX_EXE" --headless --audio-driver Dummy -- --trace="$TRACE" --t=3 > "$LOG" 2>&1 \
  || { cat "$LOG"; echo "exported binary failed"; exit 1; }
cat "$LOG"
python3 - "$LOG" "$TRACE" <<'PYBACKEND'
import json
from pathlib import Path
import sys

log, trace = (Path(path).read_text(encoding="utf-8") for path in sys.argv[1:])
statuses = [line.removeprefix("physics backend: ") for line in log.splitlines() if line.startswith("physics backend: ")]
identities = [line.removeprefix("# stage_backend: ") for line in trace.splitlines() if line.startswith("# stage_backend: ")]
if len(statuses) != 1 or len(identities) != 1:
    raise SystemExit("exported flight did not report exactly one backend status and trace identity")
status = json.loads(statuses[0])
identity = json.loads(identities[0].replace('&"', '"'))
if status.get("requested") != "native" or status.get("reason") != "" \
        or status.get("identity", {}).get("backend") != "native" or identity != status["identity"]:
    raise SystemExit("exported default flight did not install and record the verified native stage")
print("exported flight requested, installed and recorded the native stage")
PYBACKEND
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3
grep -qxF "# app_build: $VERSION" "$TRACE" || { grep "^# app_" "$TRACE"; echo "the exported binary does not report build $VERSION"; exit 1; }
echo "exported binary reports build $VERSION; NK-3 evidence: $NK3_EVIDENCE"

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
PACKAGES=("openrc-simulator-$VERSION-linux-x86_64.zip"
          "openrc-simulator-$VERSION-windows-x86_64.zip"
          "openrc-simulator-$VERSION-macos-universal.zip")
for package in "${PACKAGES[@]}"; do
  [ -s "$DIST/$package" ] || { echo "missing package: $package" >&2; exit 1; }
done
echo "== final archive ABI inventory and release manifest"
python3 "$ROOT/tools/release/elf_audit.py" "$DIST/${PACKAGES[0]}" --output "$DIST/linux-abi.json"
python3 "$ROOT/tools/release/manifest.py" finalize --root "$ROOT" --directory "$DIST" \
  --inputs "$DIST/.release-inputs.json"
(cd "$DIST" && sha256sum --check --strict SHA256SUMS)
# CI consumes only this successful run; a failed export must never publish an output handle.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'package_dir=%s\nversion=%s\n' "$DIST" "$VERSION" >> "$GITHUB_OUTPUT"
fi
echo "== verified packages: $DIST"
