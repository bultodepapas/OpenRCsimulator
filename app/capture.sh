#!/usr/bin/env bash
# Capture mode: render t = 3.0 s at 1280x720 under Xvfb (software OpenGL), save PNGs.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
# SC-02a: retain the existing landscape baselines; scenery captures select their layer explicitly.
export OPENRC_SCENERY=off
export OPENRC_SCENERY_BIRDS=off OPENRC_ENGINE_SHADOWS=off
HERE="$(cd "$(dirname "$0")" && pwd)"
GROUP=all
OUTPUT=""
RUN_ID=""
usage() {
  echo "Usage: app/capture.sh [--group GROUP --out NEW_ABSOLUTE_DIRECTORY [--run-id UNIQUE_ID]]"
  echo "Groups: core, ui, quality, terrain-atmosphere, ground, vegetation, scenario"
  echo "Groups are experimental partial checks, not complete capture-set evidence."
  echo "--run-id opts into experimental group receipts; use a fresh ID for each coordinated run."
  echo "Use independent checkouts and run only one rendered capture per host."
}
while (($#)); do
  case "$1" in
    --group) (($# >= 2)) || { usage >&2; exit 2; }; GROUP="$2"; shift 2 ;;
    --out) (($# >= 2)) || { usage >&2; exit 2; }; OUTPUT="$2"; shift 2 ;;
    --run-id) (($# >= 2)) && [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] || { usage >&2; exit 2; }; RUN_ID="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$GROUP" in all|core|ui|quality|terrain-atmosphere|ground|vegetation|scenario) ;; *) usage >&2; exit 2 ;; esac
if [[ "$GROUP" == all ]]; then
  [[ -z "$OUTPUT" && -z "$RUN_ID" ]] || { echo "--out and --run-id require a partial --group" >&2; exit 2; }
  CAPTURES="$HERE/captures"
else
  [[ "$OUTPUT" == /* ]] || { echo "--group requires an absolute --out" >&2; exit 2; }
  [[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || { echo "group output must be new: $OUTPUT" >&2; exit 2; }
  CAPTURES="$(realpath -m "$OUTPUT")"
  APP_REAL="$(cd "$HERE" && pwd -P)"
  case "$CAPTURES" in "$APP_REAL"|"$APP_REAL"/*) echo "group output must be outside app/" >&2; exit 2 ;; esac
  [[ ! -e "$CAPTURES" && ! -L "$CAPTURES" ]] || { echo "group output must be new: $CAPTURES" >&2; exit 2; }
fi
mkdir -p "$HERE/captures" # untracked in git: a fresh clone does not have it
exec 9> "$HERE/captures/.capture.lock"
flock -n 9 || { echo "another capture run owns $HERE/captures" >&2; exit 1; }
# The complete-set marker only exists after every capture, image check and trace succeeds.
rm -f "$CAPTURES/run-manifest.json"
if [[ "$GROUP" != all ]]; then
  mkdir -p "$(dirname "$CAPTURES")"
  mkdir "$CAPTURES"
  # Separate Godot settings and caches; a separate checkout is still needed for parallel hosts.
  export XDG_DATA_HOME="$CAPTURES/.capture-profile/data" XDG_CONFIG_HOME="$CAPTURES/.capture-profile/config"
  export XDG_CACHE_HOME="$CAPTURES/.capture-profile/cache"
fi
mkdir -p "$CAPTURES/field"
# Captures are outputs, not game textures: keep the editor from importing and duplicating every PNG.
touch "$CAPTURES/.gdignore"
includes() { [[ "$GROUP" == all || "$GROUP" == "$1" ]]; }
PHASE=""
PHASE_START=0
printf 'phase\tseconds\tresult\n' > "$CAPTURES/timings.tsv"
start_phase() { PHASE="$1"; PHASE_START=$SECONDS; }
finish_phase() { printf '%s\t%d\tpass\n' "$PHASE" "$((SECONDS - PHASE_START))" >> "$CAPTURES/timings.tsv"; PHASE=""; }
trap 'status=$?; if [[ -n "$PHASE" ]]; then printf "%s\t%d\tfail (%d)\n" "$PHASE" "$((SECONDS - PHASE_START))" "$status" >> "$CAPTURES/timings.tsv"; fi' EXIT
start_phase setup
GODOT="$("$HERE/get-godot.sh")"
if [[ -n "$RUN_ID" ]]; then
  python3 "$HERE/../tools/ci/capture_groups.py" begin --repo "$HERE/.." --group "$GROUP" \
    --run-id "$RUN_ID" --godot "$GODOT" --out "$CAPTURES"
fi
record_check() { if [[ -n "$RUN_ID" ]]; then printf '%s\n' "$1" >> "$CAPTURES/.capture-checks"; fi; }
# L6b: fresh checkouts have no imported tree atlas. Import before hashing/rendering any scene.
IMPORT_LOG="$(mktemp)"
if ! timeout 600 "$GODOT" --headless --path "$HERE" --audio-driver Dummy --import > "$IMPORT_LOG" 2>&1 \
  || grep -qE "^(SCRIPT |SHADER )?ERROR:" "$IMPORT_LOG"; then
  cat "$IMPORT_LOG"; rm -f "$IMPORT_LOG"; exit 1
fi
rm -f "$IMPORT_LOG"
record_check setup:import
VPY="$("$HERE/tests/visual-env.sh")"
"$VPY" "$HERE/tests/test_capture_runner.py"
record_check setup:capture-runner-tests
finish_phase
# A dirty checkout is identified by revision plus per-file hashes in native evidence.
if [ -z "${OPENRC_CODE_REVISION:-}" ]; then
  OPENRC_CODE_REVISION="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unavailable)"
  if [ -n "$(git -C "$HERE" status --porcelain --untracked-files=normal)" ]; then OPENRC_CODE_REVISION+="-dirty"; fi
  export OPENRC_CODE_REVISION
fi
CAPTURE_NAMES=()
# L0b: llvmpipe thread count pinned. 1 and 12 threads gave byte-identical captures on Mesa 25.2.8 (2026-10-05), so
# this is cheap insurance for machines with other core counts (CI runners); 1 thread costs ~5 s per run.
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"
COUNTERS="$CAPTURES/landscape-counters.txt"
: > "$COUNTERS"
# VQ-01a: reference captures run the legacy atmosphere fixture. Production field cases use the real app.
shot() { # shot <file suffix> <user args...>
  local name="capture$1" out="$CAPTURES/capture$1.png"; shift
  local scene="atmosphere" counters="$COUNTERS"
  local entry=("res://tests/fixtures/atmosphere_field.tscn")
  if [[ "$name" == capture-field-* ]]; then
    scene="field"
    name="${name/capture-field-/capture-land-}"
    out="$CAPTURES/field/$name.png"
    counters="$CAPTURES/field/landscape-counters.txt"
    entry=()
  fi
  "$VPY" "$HERE/tests/capture_runner.py" --out "$out" --kind flight --scene "$scene" -- \
    xvfb-run -a -s "-screen 0 1280x720x24" \
    "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy "${entry[@]}" -- --capture "$@" --out="$out"
  sed -n "s|^saved .* (error 0) \(draw_calls=.*\)|$name \1|p" "${out%.png}.log" >> "$counters"
  CAPTURE_NAMES+=("${out#"$CAPTURES/"}")
}
if includes core; then
start_phase core-render
# Stage 0/1 views on the scripted circle (stable references).
shot "" --scripted
shot "-inspect" --scripted --inspect
shot "-inspect-deflected" --scripted --inspect --roll=1 --pitch=1 --yaw=1
# Physics (trimmed flight) at t = 1.5 s, pilot view (auto-zoom) and close-up.
shot "-physics" --t=1.5
shot "-physics-inspect" --t=1.5 --inspect
# D7: the same pilot view without auto-zoom (the readability problem auto-zoom addresses).
shot "-physics-nozoom" --t=1.5 --autozoom=0
# D7: a low pass at 0.8 m, close-up: the ground shadow under the airplane (from the pilot at 77 m the grazing
# angle makes it < 1 px thick: the shadow is a cue for close passes and landings).
shot "-physics-low-inspect" --t=1.5 --alt=0.8 --inspect
# L3: the same close-ups without the airplane: the sun shadow's position and the wing's clipping are measured against them.
shot "-physics-low-inspect-noplane" --t=1.5 --alt=0.8 --inspect --hide_airplane
shot "-physics-inspect-noplane" --t=1.5 --inspect --hide_airplane
# L0 (LANDSCAPE-PLAN): landscape review set. Horizon from the pilot's eye at 4 azimuths, level and 10° up; the 30 m
# trimmed view and the 3 m low pass without auto-zoom; a view toward the sun (Spec.ATMOSPHERE: azimuth 225°, elevation 45°).
for az in 0 90 180 270; do
  for el in 0 10; do shot "-land-az${az}-el${el}" --t=1.5 --look_az=$az --look_el=$el; done
done
# L4: the same view 10 s later: only the clouds may change.
shot "-land-az90-el10-t11" --t=11.5 --look_az=90 --look_el=10
# L2: the horizon from 100 m up (the ground's rim is 0.3° below the horizon there), including toward the sun.
for az in 0 90 180 225 270; do shot "-land-az${az}-el0-100m" --t=1.5 --look_az=$az --look_el=0 --look_alt=100; done
# Readability views (L0c): no ground shadow, so the with/without difference is the airplane only (its shadow is
# checked in the 0.8 m close-up, L3).
shot "-land-30m" --t=1.5 --autozoom=0 --shadow=off
shot "-land-low3m" --t=1.5 --alt=3 --autozoom=0 --shadow=off
shot "-land-sun" --t=1.5 --look_az=225 --look_el=25
# The review image above keeps full glare/cloud appearance. L1's alignment gate uses a separate, cloud/aureole/glare-
# free view of the same solar direction so it can measure the disc itself instead of the clipped light field.
SUN_ALIGNMENT="$CAPTURES/sun-alignment"
mkdir -p "$SUN_ALIGNMENT"
rm -f "$SUN_ALIGNMENT/sun_alignment.png" "$SUN_ALIGNMENT/report.json"
if ! timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$HERE" \
  --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_landscape_upgrade.gd \
  -- --out="$SUN_ALIGNMENT" --cases=sun_alignment > "$SUN_ALIGNMENT/run.log" 2>&1 \
  || grep -qE "^[[:space:]]*(SCRIPT |SHADER )?ERROR:" "$SUN_ALIGNMENT/run.log"; then
  cat "$SUN_ALIGNMENT/run.log"; exit 1
fi
record_check core:sun-alignment
# L0c: the airplane-in-view landscape shots again without the airplane: the background for the readability metric.
shot "-land-30m-noplane" --t=1.5 --autozoom=0 --hide_airplane --shadow=off
shot "-land-low3m-noplane" --t=1.5 --alt=3 --autozoom=0 --hide_airplane --shadow=off
# L0b: straight down from 30 m over the pilot station: ground tiling must be judged from above (investigation 06).
shot "-land-top" --t=1.5 --look_az=0 --look_el=-90 --look_alt=30
# Real field, separate from the fixed sky/ground reference; future trees must appear in these views.
: > "$CAPTURES/field/landscape-counters.txt"
for az in 0 90 180 270; do
  for el in 0 10; do shot "-field-az${az}-el${el}" --t=1.5 --look_az=$az --look_el=$el --hide_airplane; done
done
shot "-field-top" --t=1.5 --look_az=0 --look_el=-90 --look_alt=30 --hide_airplane
record_check core:shots
finish_phase
fi
if includes ui; then
start_phase ui
# UI uses the same process/file guards. Its sidecar is harness metadata, not engine render telemetry.
for lang in en es; do
  for screen in home pause help hint; do
    out="$CAPTURES/ui-$screen-$lang.png"
    # Flight-backed Pause/Hint captures rebuild the Club field under llvmpipe.
    # The old 60 s bound expired on CI; a Linux/Xvfb pause run took 76.65 s.
    ui_timeout=60
    if [[ "$screen" == pause || "$screen" == hint ]]; then ui_timeout=120; fi
    "$VPY" "$HERE/tests/capture_runner.py" --out "$out" --kind ui --scene "$screen" --timeout "$ui_timeout" -- \
      xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy \
      --script res://tests/capture_ui.gd -- --out="$out" --lang="$lang" --screen="$screen"
    CAPTURE_NAMES+=("${out#"$CAPTURES/"}")
  done
done
record_check ui:captures
finish_phase
fi
if includes core; then
start_phase core-checks
echo "render counters per view (draw calls and primitives): $COUNTERS"
cat "$COUNTERS"
# Image checks run in the pinned, hashed Python environment (.tools/visual-venv: Pillow, numpy, FLIP), never on the
# system Python: GitHub's runner has no Pillow (CI failure 2026-10-05, invisible locally and under act).
"$VPY" "$HERE/tests/check_landscape_captures.py" "$CAPTURES"
record_check core:landscape
# L0c: airplane readability against its background.
# Readability (L1b thresholds, investigation 09): contrast ≤ −0.40, ≤ 15 % nearly invisible, ΔE ≥ 30. Background
# saturation ≥ 25 ("not a greyed sky") at 30 m; at 3 m the airplane sits against the pale horizon haze (~21 by
# physics), so ≥ 18 there. (Until L3 the metric also counted the D7 pilot shadow as airplane: LANDSCAPE-PLAN L3 log.)
"$VPY" "$HERE/tests/compare_captures.py" readability "$CAPTURES" \
  --require "capture-land-low3m.png:-0.40:0.15:30:18" --require "capture-land-30m.png:-0.40:0.15:30:25"
record_check core:readability
# C7: flight trace of the same throw, headless (no display needed).
rm -f "$CAPTURES/trace-physics.csv"
if timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy -- --trace="$CAPTURES/trace-physics.csv" --t=1.5 > "$CAPTURES/trace-physics.log" 2>&1; then
  if grep -qE "^[[:space:]]*(SCRIPT |SHADER )?ERROR:" "$CAPTURES/trace-physics.log"; then
    cat "$CAPTURES/trace-physics.log"; exit 1
  fi
else
  status=$?
  cat "$CAPTURES/trace-physics.log"; exit "$status"
fi
record_check core:trace
python3 "$HERE/tests/check_trimmed_flight.py" "$CAPTURES/trace-physics.csv" --duration=1.5
record_check core:trace-check
finish_phase
fi
if includes quality; then
start_phase quality
# VQ-01b extends this same guarded producer: 66 fixed images, metadata/parity/readability checks.
"$VPY" "$HERE/tests/test_visual_quality_cases.py"
record_check quality:tests
"$VPY" "$HERE/tests/visual_quality_cases.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/vq01b"
record_check quality:cases
# FW-62-R1: the night kit must add light, retain its underside cue, and stay bounded under camera zoom.
mkdir -p "$CAPTURES/aircraft-lights"
if ! timeout 120 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$HERE" \
  --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_aircraft_lights.gd \
  -- --out="$CAPTURES/aircraft-lights" > "$CAPTURES/aircraft-lights/run.log" 2>&1 \
  || grep -qE "^[[:space:]]*(SCRIPT |SHADER )?ERROR:" "$CAPTURES/aircraft-lights/run.log"; then
  cat "$CAPTURES/aircraft-lights/run.log"; exit 1
fi
record_check quality:aircraft-lights
# L5: both interactive error routes must show a usable error instead of starting an invalid field.
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_field_failures.py" FieldFailureRoutes.test_interactive_routes_show_a_focused_localized_error_panel
record_check quality:field-failures
finish_phase
fi
if includes terrain-atmosphere; then
start_phase terrain-atmosphere
# L6b real GPU path: custom-data packing, sector bounds/draws and deterministic tree views.
python3 "$HERE/../tools/trees/check_review.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l6b"
record_check terrain-atmosphere:tree-review
# The guarded landscape tools require fresh outputs. Replace only these generated directories under the capture lock.
rm -rf "$CAPTURES/l7" "$CAPTURES/l4b" "$CAPTURES/l9c" "$CAPTURES/l10a" "$CAPTURES/l10b" "$CAPTURES/l10c" "$CAPTURES/l10d" "$CAPTURES/l11a" "$CAPTURES/l15b"
# L7: combined forest/hill A/B at three heights, repeated bytes and all visibility-preset rim checks.
"$VPY" "$HERE/../tools/terrain/check_horizon.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l7"
record_check terrain-atmosphere:horizon
# L4b/L15d: production sky/shadow A/B, sim-time drift, repeated bytes and periodic cloud projection.
"$VPY" "$HERE/../tools/atmosphere/check_phase6.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l4b"
record_check terrain-atmosphere:phase6
"$VPY" "$HERE/../tools/atmosphere/check_cloud_probe.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l15d"
record_check terrain-atmosphere:cloud-probe
finish_phase
fi
if includes ground; then
start_phase ground
# L9c: ground-pass runway/mown coverage, repeated frames, overlap priority and filtering controls.
"$VPY" "$HERE/../tools/ground/check_surfaces.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l9c"
record_check ground:surfaces
"$VPY" "$HERE/../tools/ground/test_stripes.py"
record_check ground:stripe-tests
"$VPY" "$HERE/../tools/ground/check_stripes.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l9c/stripes"
record_check ground:stripes
"$VPY" "$HERE/../tools/ground/check_windsock.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l10a"
record_check ground:windsock
"$VPY" "$HERE/../tools/ground/check_windsock.py" --cue pilot_station --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l10b"
record_check ground:pilot-station
"$VPY" "$HERE/../tools/ground/check_windsock.py" --cue flightline_barrier --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l10c"
record_check ground:flightline-barrier
"$VPY" "$HERE/../tools/ground/check_windsock.py" --cue contact_shadows --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l10d"
record_check ground:contact-shadows
finish_phase
fi
if includes vegetation; then
start_phase vegetation
# L11a: grass budget, seam, wind wrap and reuse of existing opt-in scenery flowers.
"$VPY" "$HERE/../tools/grass/check_grass.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l11a" --timeout 600
record_check vegetation:grass
"$VPY" "$HERE/../tools/grass/check_grass_seam.py" --captures "$CAPTURES/l11a/candidate-repeat-1" --out "$CAPTURES/l11a/seam-summary.json" --self-test
record_check vegetation:grass-seam
# L15b: rooted tree sway, calm parity, fixed-clock repeats and GPU geometry readback.
"$VPY" "$HERE/../tools/trees/check_wind.py" --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l15b" --timeout 1200
record_check vegetation:tree-wind
# L6c: the airplane against trees, treetop edge, sky and grass at 100 m (numbers recorded for Gate L, case guards
# only) and the blinded 24-image attitude kit for the human playtest (captures/l6c/kit).
"$VPY" "$HERE/tests/test_treeline_readability.py"
record_check vegetation:treeline-tests
"$VPY" "$HERE/tests/treeline_readability.py" capture --app "$HERE" --godot "$GODOT" --out "$CAPTURES/l6c"
record_check vegetation:treeline
finish_phase
fi
if includes scenario; then
start_phase scenario
# Runway scenario (SCENERY-PLAN): the airplane at the runway threshold, a scripted takeoff from five cameras at fixed
# times, automatic physics-render sync checks, and a frame-by-frame comparison with the previous run
# (captures/scenario/latest/report.html; history in captures/scenario/history/index.html).
"$HERE/../tools/scenery/scenario.sh" "$CAPTURES/scenario"
record_check scenario:run
finish_phase
fi
if [[ "$GROUP" != all ]]; then
  if [[ -n "$RUN_ID" ]]; then
    python3 "$HERE/../tools/ci/capture_groups.py" finish --repo "$HERE/.." --group "$GROUP" \
      --run-id "$RUN_ID" --godot "$GODOT" --visual-python "$VPY" --out "$CAPTURES"
  fi
  echo "partial capture group '$GROUP' passed; no complete-set manifest was produced"
  exit 0
fi
# Publish exactly this run's inventory, never a glob that can silently include old outputs.
"$VPY" - "$CAPTURES" "${CAPTURE_NAMES[@]}" <<'PYMANIFEST'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
entries = []
for name in sys.argv[2:]:
    png = root / name
    sidecar = png.with_suffix('.json')
    data = json.loads(sidecar.read_text())
    entries.append({'image': name, 'capture_scene': data['capture_scene'],
                    'sha256': data['sha256'],
                    'manifest_sha256': hashlib.sha256(sidecar.read_bytes()).hexdigest()})
trace = hashlib.sha256((root / 'trace-physics.csv').read_bytes()).hexdigest()
manifest = {'format': 'openrc-capture-set v1', 'complete': True, 'captures': entries, 'trace_sha256': trace,
            'aircraft_lights_review': 'aircraft-lights/summary.json',
            'aircraft_lights_review_sha256': hashlib.sha256((root / 'aircraft-lights/summary.json').read_bytes()).hexdigest(),
            'treeline_review': 'l6b/repeat-1/review.json',
            'treeline_review_sha256': hashlib.sha256((root / 'l6b/repeat-1/review.json').read_bytes()).hexdigest(),
            'horizon_review': 'l7/capture-summary.json',
            'horizon_review_sha256': hashlib.sha256((root / 'l7/capture-summary.json').read_bytes()).hexdigest(),
            'atmosphere_review': 'l4b/capture-summary.json',
            'atmosphere_review_sha256': hashlib.sha256((root / 'l4b/capture-summary.json').read_bytes()).hexdigest(),
            'field_surfaces_review': 'l9c/summary.json',
            'field_surfaces_review_sha256': hashlib.sha256((root / 'l9c/summary.json').read_bytes()).hexdigest(),
            'stripe_reference_review': 'l9c/stripes/summary.json',
            'stripe_reference_review_sha256': hashlib.sha256((root / 'l9c/stripes/summary.json').read_bytes()).hexdigest(),
            'pilot_station_review': 'l10b/summary.json',
            'pilot_station_review_sha256': hashlib.sha256((root / 'l10b/summary.json').read_bytes()).hexdigest(),
            'windsock_review': 'l10a/summary.json',
            'windsock_review_sha256': hashlib.sha256((root / 'l10a/summary.json').read_bytes()).hexdigest(),
            'flightline_barrier_review': 'l10c/summary.json',
            'flightline_barrier_review_sha256': hashlib.sha256((root / 'l10c/summary.json').read_bytes()).hexdigest(),
            'cue_contact_shadows_review': 'l10d/summary.json',
            'cue_contact_shadows_review_sha256': hashlib.sha256((root / 'l10d/summary.json').read_bytes()).hexdigest(),
            'near_grass_seam': 'l11a/seam-summary.json',
            'near_grass_seam_sha256': hashlib.sha256((root / 'l11a/seam-summary.json').read_bytes()).hexdigest(),
            'tree_wind_review': 'l15b/capture-summary.json',
            'tree_wind_review_sha256': hashlib.sha256((root / 'l15b/capture-summary.json').read_bytes()).hexdigest(),
            'near_grass_review': 'l11a/capture-summary.json',
            'near_grass_review_sha256': hashlib.sha256((root / 'l11a/capture-summary.json').read_bytes()).hexdigest(),
            'cloud_probe': 'l15d/summary.json',
            'cloud_probe_sha256': hashlib.sha256((root / 'l15d/summary.json').read_bytes()).hexdigest(),
            'treeline_readability': 'l6c/l6c-run-manifest.json',
            'treeline_readability_sha256': hashlib.sha256((root / 'l6c/l6c-run-manifest.json').read_bytes()).hexdigest(),
            'visual_quality_manifest': 'vq01b/visual-quality-run-manifest.json',
            'visual_quality_manifest_sha256': hashlib.sha256((root / 'vq01b/visual-quality-run-manifest.json').read_bytes()).hexdigest(),
            'sun_alignment_review': 'sun-alignment/report.json',
            'sun_alignment_review_sha256': hashlib.sha256((root / 'sun-alignment/report.json').read_bytes()).hexdigest()}
temp = root / 'run-manifest.tmp'
temp.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
temp.replace(root / 'run-manifest.json')
print(f'capture set complete: {len(entries)} fresh images + manifests; trace verified')
PYMANIFEST
