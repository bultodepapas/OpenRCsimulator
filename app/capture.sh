#!/usr/bin/env bash
# Capture mode: render t = 3.0 s at 1280x720 under Xvfb (software OpenGL), save PNGs.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/captures/field" # untracked in git: a fresh clone does not have it
exec 9> "$HERE/captures/.capture.lock"
flock -n 9 || { echo "another capture run owns $HERE/captures" >&2; exit 1; }
# The complete-set marker only exists after every capture, image check and trace succeeds.
rm -f "$HERE/captures/run-manifest.json"
GODOT="$("$HERE/get-godot.sh")"
# L6b: fresh checkouts have no imported tree atlas. Import before hashing/rendering any scene.
IMPORT_LOG="$(mktemp)"
if ! timeout 180 "$GODOT" --headless --path "$HERE" --audio-driver Dummy --import > "$IMPORT_LOG" 2>&1 \
  || grep -qE "^(SCRIPT |SHADER )?ERROR:" "$IMPORT_LOG"; then
  cat "$IMPORT_LOG"; rm -f "$IMPORT_LOG"; exit 1
fi
rm -f "$IMPORT_LOG"
VPY="$("$HERE/tests/visual-env.sh")"
"$VPY" "$HERE/tests/test_capture_runner.py"
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
COUNTERS="$HERE/captures/landscape-counters.txt"
: > "$COUNTERS"
# VQ-01a: reference captures run the legacy atmosphere fixture. Production field cases use the real app.
shot() { # shot <file suffix> <user args...>
  local name="capture$1" out="$HERE/captures/capture$1.png"; shift
  local scene="atmosphere" counters="$COUNTERS"
  local entry=("res://tests/fixtures/atmosphere_field.tscn")
  if [[ "$name" == capture-field-* ]]; then
    scene="field"
    name="${name/capture-field-/capture-land-}"
    out="$HERE/captures/field/$name.png"
    counters="$HERE/captures/field/landscape-counters.txt"
    entry=()
  fi
  "$VPY" "$HERE/tests/capture_runner.py" --out "$out" --kind flight --scene "$scene" -- \
    xvfb-run -a -s "-screen 0 1280x720x24" \
    "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy "${entry[@]}" -- --capture "$@" --out="$out"
  sed -n "s|^saved .* (error 0) \(draw_calls=.*\)|$name \1|p" "${out%.png}.log" >> "$counters"
  CAPTURE_NAMES+=("${out#"$HERE/captures/"}")
}
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
# L0c: the airplane-in-view landscape shots again without the airplane: the background for the readability metric.
shot "-land-30m-noplane" --t=1.5 --autozoom=0 --hide_airplane --shadow=off
shot "-land-low3m-noplane" --t=1.5 --alt=3 --autozoom=0 --hide_airplane --shadow=off
# L0b: straight down from 30 m over the pilot station: ground tiling must be judged from above (investigation 06).
shot "-land-top" --t=1.5 --look_az=0 --look_el=-90 --look_alt=30
# Real field, separate from the fixed sky/ground reference; future trees must appear in these views.
: > "$HERE/captures/field/landscape-counters.txt"
for az in 0 90 180 270; do
  for el in 0 10; do shot "-field-az${az}-el${el}" --t=1.5 --look_az=$az --look_el=$el --hide_airplane; done
done
shot "-field-top" --t=1.5 --look_az=0 --look_el=-90 --look_alt=30 --hide_airplane
# UI uses the same process/file guards. Its sidecar is harness metadata, not engine render telemetry.
for lang in en es; do
  for screen in home pause help hint; do
    out="$HERE/captures/ui-$screen-$lang.png"
    "$VPY" "$HERE/tests/capture_runner.py" --out "$out" --kind ui --scene "$screen" -- \
      xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$HERE" --rendering-driver opengl3 --audio-driver Dummy \
      --script res://tests/capture_ui.gd -- --out="$out" --lang="$lang" --screen="$screen"
    CAPTURE_NAMES+=("${out#"$HERE/captures/"}")
  done
done
echo "render counters per view (draw calls and primitives): $COUNTERS"
cat "$COUNTERS"
# Image checks run in the pinned, hashed Python environment (.tools/visual-venv: Pillow, numpy, FLIP), never on the
# system Python: GitHub's runner has no Pillow (CI failure 2026-10-05, invisible locally and under act).
"$VPY" "$HERE/tests/check_landscape_captures.py" "$HERE/captures"
# L0c: airplane readability against its background.
# Readability (L1b thresholds, investigation 09): contrast ≤ −0.40, ≤ 15 % nearly invisible, ΔE ≥ 30. Background
# saturation ≥ 25 ("not a greyed sky") at 30 m; at 3 m the airplane sits against the pale horizon haze (~21 by
# physics), so ≥ 18 there. (Until L3 the metric also counted the D7 pilot shadow as airplane: LANDSCAPE-PLAN L3 log.)
"$VPY" "$HERE/tests/compare_captures.py" readability "$HERE/captures" \
  --require "capture-land-low3m.png:-0.40:0.15:30:18" --require "capture-land-30m.png:-0.40:0.15:30:25"
# C7: flight trace of the same throw, headless (no display needed).
rm -f "$HERE/captures/trace-physics.csv"
if timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy -- --trace="$HERE/captures/trace-physics.csv" --t=1.5 > "$HERE/captures/trace-physics.log" 2>&1; then
  if grep -qE "^[[:space:]]*(SCRIPT |SHADER )?ERROR:" "$HERE/captures/trace-physics.log"; then
    cat "$HERE/captures/trace-physics.log"; exit 1
  fi
else
  status=$?
  cat "$HERE/captures/trace-physics.log"; exit "$status"
fi
python3 "$HERE/tests/check_trimmed_flight.py" "$HERE/captures/trace-physics.csv"
# VQ-01b extends this same guarded producer: 66 fixed images, metadata/parity/readability checks.
"$VPY" "$HERE/tests/test_visual_quality_cases.py"
"$VPY" "$HERE/tests/visual_quality_cases.py" --app "$HERE" --godot "$GODOT" --out "$HERE/captures/vq01b"
# L5: both interactive error routes must show a usable error instead of starting an invalid field.
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_field_failures.py" FieldFailureRoutes.test_interactive_routes_show_a_focused_localized_error_panel
# L6b real GPU path: custom-data packing, sector bounds/draws and deterministic tree views.
python3 "$HERE/../tools/trees/check_review.py" --app "$HERE" --godot "$GODOT" --out "$HERE/captures/l6b"
# Publish exactly this run's inventory, never a glob that can silently include old outputs.
"$VPY" - "$HERE/captures" "${CAPTURE_NAMES[@]}" <<'PYMANIFEST'
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
            'treeline_review': 'l6b/repeat-1/review.json',
            'treeline_review_sha256': hashlib.sha256((root / 'l6b/repeat-1/review.json').read_bytes()).hexdigest(),
            'visual_quality_manifest': 'vq01b/visual-quality-run-manifest.json',
            'visual_quality_manifest_sha256': hashlib.sha256((root / 'vq01b/visual-quality-run-manifest.json').read_bytes()).hexdigest()}
temp = root / 'run-manifest.tmp'
temp.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
temp.replace(root / 'run-manifest.json')
print(f'capture set complete: {len(entries)} fresh images + manifests; trace verified')
PYMANIFEST
