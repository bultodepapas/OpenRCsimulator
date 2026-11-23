set -euo pipefail
repo=$PWD
base=85a2475f60029a4b6b09f23f643119bceea84a45
scratch="$RUNNER_TEMP/companion-v034"
out="$scratch/evidence"
baseline="$scratch/baseline"
mkdir -p "$out" "$baseline/app"
git fetch --no-tags --depth=1 origin "$base"
git archive "$base" app | tar -xf - -C "$baseline"
godot=$(bash app/get-godot.sh)
"$godot" --version
sha256sum "$godot"
run() {
  label="$1"
  project="$2"
  duration="$3"
  shift 3
  profile="$scratch/profile-${project##*/}"
  XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" \
  python3 "$repo/tools/godot/run_checked.py" --timeout "$duration" --out-dir "$out/checks" --label "$label" -- \
    "$godot" --headless --path "$project/app" --audio-driver Dummy "$@"
}
run import-baseline "$baseline" 900 --import
mkdir "$repo/app/.godot"
cp -a "$baseline/app/.godot/imported" "$repo/app/.godot/"
run import-candidate "$repo" 900 --import
git diff --exit-code HEAD -- app/
test -z "$(git ls-files --others --exclude-standard -- app)"
probe="$repo/research/ai-companions/production_probe.gd"
git diff --exit-code "$base" HEAD -- research/ai-companions/production_probe.gd "$probe" || exit 1
for label in baseline candidate; do
  project="$baseline"
  if [ "$label" = candidate ]; then project="$repo"; fi
  run "production-$label" "$project" 420 --script "$probe" -- "--out=$out/$label.json"
done
cmp "$out/baseline.json" "$out/candidate.json"
python3 - "$out/candidate.json" <<'PY_CHECK'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_bytes())
assert data["complete"] and data["ticks"] == 28800 and data["count"] == 3
assert data["min_clearance_m"] >= 20
print(data)
PY_CHECK
for suite in companions_profiles companions_behavior_manifest companions_manager companions_shell scenery_loader scenery_destruction rcv_scenery_collision vehicle_paint livery_picker; do
  run "$suite" "$repo" 180 --script "res://tests/test_$suite.gd"
done
git diff --exit-code HEAD -- app/
test -z "$(git ls-files --others --exclude-standard -- app)"
