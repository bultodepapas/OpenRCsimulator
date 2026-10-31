#!/usr/bin/env bash
# Local CI preflight. It never represents hosted, native or publication gates as passed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
MODE="${1:-quick}"
if [[ $# -gt 1 ]] || [[ "$MODE" != quick && "$MODE" != full && "$MODE" != release ]]; then
  echo "usage: tools/ci/check-local.sh [quick|full|release]" >&2; exit 2
fi
[[ "$(uname -s)" == Linux ]] || { echo "Local checks require Linux or WSL; see docs/TOOLS.md." >&2; exit 1; }

omitted() {
  echo "Not run by this preflight: Linux and Windows ground-native CI builds/parity; the full NK-3 native CI qualification;"
  echo "hosted Actions scope/aggregate, artifact transfer and publication; native desktop, GPU and device acceptance."
  if [[ "$MODE" != release ]]; then echo "Package/export checks are also not run."; fi
}

if [[ "$MODE" == release ]]; then
  # Check before starting the expensive suite. Export applies the full receipt and package gates.
  for receipt in app/native/ground_vehicle/build-receipt.json app/native/kernel/build-receipt.json; do
    [[ -s "$receipt" ]] || { echo "Release preflight missing required native receipt: $receipt" >&2; exit 1; }
  done
  python3 - <<'PY'
import importlib.util, json
from pathlib import Path
root = Path.cwd()
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, root / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
ground = load("ground_preflight", "research/rc-monster-truck/native/build.py")
directory = root / "app/native/ground_vehicle"
receipt = json.loads((directory / "build-receipt.json").read_text())
if receipt.get("format") != "openrc-ground-vehicle-native-receipt":
    raise SystemExit("Invalid ground-native receipt")
lock = json.loads((ground.HERE / "toolchain-lock.json").read_text())
for platform in ("linux", "windows"):
    row = receipt.get("platforms", {}).get(platform)
    ground.validate_platform_receipt(platform, row, lock, ground.source_digest())
    if row.get("binary_sha256") != ground.sha256_file(directory / ground.expected_library_name(platform)):
        raise SystemExit(f"{platform} ground-native binary does not match its receipt")
load("nk3_preflight", "research/native-kernel/package.py").verified_install()
print("Installed Windows/Linux ground and NK-3 receipts match current inputs; export remains required.")
PY
fi

echo "== local quick checks (partial CI scope)"
python3 app/tests/test_ci_partitions.py
python3 app/tests/test_export_identity.py
python3 -m unittest discover -s tools/ci -p 'test_*.py'
if [[ "$MODE" == quick ]]; then
  echo "Quick is partial: app integration/units, schema, offline tools, visuals, site and prototype were not run."
  omitted
  exit 0
fi

python3 - <<'PY'
import importlib.metadata, sys
from pathlib import Path
files = ["research/aircraft-data/schema/requirements.txt", "research/skywalker-x8/X8-06/requirements.txt",
         "tools/godot/requirements-resources.txt", "site/requirements-seo.txt"]
missing = []
for file in files:
    for line in Path(file).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, version = line.strip().split("==", 1)
        try:
            actual = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            actual = "missing"
        if actual != version:
            missing.append(f"{name}=={version} (found {actual})")
if missing:
    print("Missing or unpinned local CI Python dependencies: " + ", ".join(missing), file=sys.stderr)
    print("Install the schema, X8, resource and site requirements files in an isolated venv and put its bin/ on PATH.", file=sys.stderr)
    raise SystemExit(1)
PY
for command in git timeout zip unzip readelf g++ xvfb-run node npm; do
  command -v "$command" > /dev/null || { echo "Missing required local command: $command" >&2; exit 1; }
done
NODE_MAJOR="$(tr -d '[:space:]' < .nvmrc)"
[[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ "$(node --version)" == "v$NODE_MAJOR."* ]] || {
  echo "The frozen prototype requires Node major $(cat .nvmrc); select it before full checks." >&2; exit 1
}
mkdir -p tmp
OUT="$(mktemp -d "$ROOT/tmp/local-checks.XXXXXXXX")"
export OPENRC_CHECK_OUT="$OUT/godot-checks"
export OPENRC_EXPECTED_CHECK_OUT="$OUT/godot-checks-expected"
# Tests must not consume or overwrite the developer's simulator preferences.
# Preserve the caller's export-template and Playwright download cache locations.
(
export XDG_DATA_HOME="$OUT/profile/data" XDG_CONFIG_HOME="$OUT/profile/config"
export XDG_CACHE_HOME="$OUT/profile/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
GODOT="$(app/get-godot.sh)"
echo "== import before schema probes; checked evidence: $OUT"
python3 tools/godot/run_checked.py --timeout 600 --out-dir "$OPENRC_CHECK_OUT" --label local-resource-import -- \
  "$GODOT" --headless --path app --audio-driver Dummy --import
export OPENRC_TEST_GODOT="$GODOT"
python3 research/aircraft-data/schema/check.py
python3 research/aircraft-data/schema/test_contract.py
python3 research/helicopter/hx700/test_schema.py
python3 research/aircraft-standardization/test_schema_v2.py --godot "$GODOT"
python3 research/rc-monster-truck/native/test_install_only.py
python3 research/f4u-corsair/F4U-07/test_generated_identity.py
bash research/test-tools.sh
python3 -m unittest discover -s tools/godot -p 'test_resource*.py'
python3 tools/godot/run_checked.py --timeout 90 --out-dir "$OPENRC_CHECK_OUT" --label nk3-trajectory-policy \
  --require-text 'NK3_TRAJECTORY_POLICY verdict=pass' -- "$GODOT" --headless --path app --audio-driver Dummy \
  --script "$ROOT/research/native-kernel/test_trajectory.gd"
python3 tools/godot/run_checked.py --timeout 90 --out-dir "$OPENRC_CHECK_OUT" --label nk3-fleet-policy \
  --require-text 'NK3 fleet policy:' --require-text 'checks, 0 failed' -- \
  "$GODOT" --headless --path app --audio-driver Dummy --script "$ROOT/research/native-kernel/test_fleet.gd"
env -u OPENRC_PARSE_WITH_UNITS OPENRC_TEST_PART=all OPENRC_UNIT_SHARDS=1 OPENRC_UNIT_SHARD=0 bash app/test.sh
python3 tools/godot/summarize.py "$OPENRC_CHECK_OUT" --junit "$OUT/results.xml"
bash app/capture.sh
)
echo "== website source and download checks"
python3 site/build_locales.py --check
python3 site/test_locales.py
node --test site/test_downloads.cjs
python3 tools/analytics/test_github_history.py
echo "== frozen prototype (requires its pinned Node and installed Playwright Chromium dependencies)"
(cd prototypes/stage0/three && npm ci && npm run typecheck && npm test && npm run capture && npm run e2e)
if [[ "$MODE" == release ]]; then
  bash app/export.sh
  echo "Local package export completed; hosted release gates below remain outstanding."
else
  echo "Full locally selected application, visual, site and prototype checks completed."
fi
omitted
