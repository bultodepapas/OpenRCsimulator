#!/usr/bin/env bash
# Headless checks (no display needed). Fails if any script fails to parse or any test fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Full local verification remains the default. CI runs every partition as a required job.
TEST_PART="${OPENRC_TEST_PART:-all}"
UNIT_SHARDS="${OPENRC_UNIT_SHARDS:-1}"
UNIT_SHARD="${OPENRC_UNIT_SHARD:-0}"
CHECK_OUT="${OPENRC_CHECK_OUT:-$HERE/../tmp/godot-checks}"
EXPECTED_CHECK_OUT="${OPENRC_EXPECTED_CHECK_OUT:-$HERE/../tmp/godot-checks-expected}"
case "$TEST_PART" in all|integration|units) ;; *) echo "invalid OPENRC_TEST_PART" >&2; exit 2 ;; esac
[[ "$UNIT_SHARDS" =~ ^[1-9][0-9]*$ && "$UNIT_SHARD" =~ ^(0|[1-9][0-9]*)$ ]] || { echo "invalid unit shard numbers" >&2; exit 2; }
(( UNIT_SHARDS <= 128 && UNIT_SHARD < UNIT_SHARDS )) || { echo "unit shard out of range" >&2; exit 2; }
if [[ "$TEST_PART" != units && ( "$UNIT_SHARDS" != 1 || "$UNIT_SHARD" != 0 ) ]]; then
  echo "unit shard selection requires OPENRC_TEST_PART=units" >&2; exit 2
fi
python3 - "$CHECK_OUT" "$EXPECTED_CHECK_OUT" <<'PY'
from pathlib import Path
import sys

positive, expected = (Path(value).resolve() for value in sys.argv[1:])
def contains(parent: Path, child: Path) -> bool:
    return parent == child or parent in child.parents

if contains(positive, expected) or contains(expected, positive):
    raise SystemExit("positive and expected-failure evidence collections must be disjoint")
PY
mkdir -p "$EXPECTED_CHECK_OUT"
GODOT="$("$HERE/get-godot.sh")"
run_with_timeout() {
  local timeout_seconds="$1"
  shift
  local out_dir="${OPENRC_CHECK_OUT:-$CHECK_OUT}"
  local runner_args=(--timeout "$timeout_seconds")
  if [[ "$out_dir" != "$CHECK_OUT" ]]; then
    if [[ -n "${OPENRC_CHECK_LABEL:-}" ]]; then runner_args+=(--label "$OPENRC_CHECK_LABEL"); fi
    if [[ -n "${OPENRC_CHECK_REQUIRED_TEXT:-}" ]]; then runner_args+=(--require-text "$OPENRC_CHECK_REQUIRED_TEXT"); fi
  fi
  runner_args+=(--out-dir "$out_dir")
  python3 "$HERE/../tools/godot/run_checked.py" "${runner_args[@]}" \
    -- "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"
}
run() { run_with_timeout 60 "$@"; }

# L6a imports the runtime PNG before tests; a clean checkout has no editor cache.
IMPORT_LOG="$(mktemp)"
echo "== import resource dependencies"
if ! run_with_timeout 180 --import > "$IMPORT_LOG" 2>&1; then
  cat "$IMPORT_LOG"; rm -f "$IMPORT_LOG"; exit 1
fi
rm -f "$IMPORT_LOG"

if [[ "$TEST_PART" != units ]]; then
echo "== LU-30: downloaded power-line extracts stay current"
python3 "$HERE/../tools/scenery/bake_power_cable.py" --check
python3 "$HERE/../tools/scenery/bake_power_insulator.py" --check --godot "$GODOT"

echo "== PT1h-R1: real-engine diagnostic failure matrix"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/../tools/godot/test_run_checked.py" NativeGodotTests
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/../tools/godot/test_frame_capture.py"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/../tools/godot/test_lifecycle_probe.py" LifecycleProbeFixtureTests

echo "== HELI-03a/04: independent mean-inflow reference stays current"
python3 "$HERE/../research/helicopter/reference/test_johnson_inflow.py"
python3 "$HERE/../research/helicopter/reference/make_oracle.py" --check
run --script res://tests/test_heli_inflow.gd -- --oracle="$HERE/../research/helicopter/reference/oracle.json"

echo "== HELI-04-R1/05: transient flow and main-rotor references stay current"
python3 "$HERE/../research/helicopter/reference/test_dynamic_inflow.py"
python3 "$HERE/../research/helicopter/reference/test_main_rotor.py"
python3 "$HERE/../research/helicopter/reference/make_dynamic_oracle.py" --check
python3 "$HERE/../research/helicopter/reference/make_main_rotor_oracle.py" --check
run --script res://tests/test_heli_dynamic_inflow.gd -- --oracle="$HERE/../research/helicopter/reference/dynamic_oracle.json"
run --script res://tests/test_heli_main_rotor.gd -- --oracle="$HERE/../research/helicopter/reference/main_rotor_oracle.json"

echo "== HELI-06a: linearized tail-rotor reference stays current"
python3 "$HERE/../research/helicopter/reference/test_tail_rotor.py"
python3 "$HERE/../research/helicopter/reference/make_tail_rotor_oracle.py" --check
run --script res://tests/test_heli_tail_rotor.gd -- --oracle="$HERE/../research/helicopter/reference/tail_rotor_oracle.json"

echo "== HELI-06b/c: passive airframe and joint aerodynamic stage"
python3 "$HERE/../research/helicopter/reference/test_airframe.py"
python3 "$HERE/../research/helicopter/reference/make_airframe_oracle.py" --check
run --script res://tests/test_heli_airframe.gd -- --oracle="$HERE/../research/helicopter/reference/airframe_oracle.json"
run --script res://tests/test_heli_aerodynamic_stage.gd

echo "== HELI-16: generated experimental rotorcraft quantities stay current"
python3 "$HERE/../research/helicopter/xcell/derive.py" --check
python3 "$HERE/../research/helicopter/xcell/test_derive.py"

echo "== HELI-36a: advanced laboratory candidate identity and admission"
python3 "$HERE/../research/helicopter/hx700/derive.py" --check
python3 "$HERE/../research/helicopter/hx700/test_derive.py"

echo "== HELI-25c: articulated inspection source, bindings and copy identity"
python3 "$HERE/../research/helicopter/assets/compile_hx700_articulated.py"
python3 "$HERE/../research/helicopter/assets/compile_hx700_motion.py" --check
python3 "$HERE/../research/helicopter/assets/test_compile_hx700_motion.py"

echo "== D11-R1: induced-flow aileron derivation"
python3 -m unittest discover -s "$HERE/../research/aero" -p "test_aileron_effectiveness.py"

echo "== AS-01/02: versioned aircraft contract and migration stay current"
python3 "$HERE/../research/aircraft-standardization/build_schema.py" --check
python3 "$HERE/../research/aircraft-standardization/parameter_register.py" --check
python3 "$HERE/../research/aircraft-standardization/migrate.py" --check-known
python3 "$HERE/../research/aircraft-standardization/test_migrate.py"
python3 "$HERE/../research/aircraft-standardization/test_physical_identity_sources.py"

echo "== AS-07/09: shared aircraft modules and generated model bindings"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/../research/aircraft-standardization/test_modules.py"
python3 "$HERE/../research/aircraft-standardization/build_models.py" --check
python3 "$HERE/../research/aircraft-standardization/test_models.py"

echo "== CR-29: sourced economics catalog and aircraft coverage stay current"
python3 "$HERE/../research/crash-economics/build_catalog.py" --check
python3 "$HERE/../research/crash-economics/build_runtime.py" --check
python3 -m unittest discover -s "$HERE/../research/crash-economics" -p 'test_*.py'

echo "== AE-01: generated Workshop descriptors and exact-byte checkout bindings"
python3 "$HERE/../research/aircraft-editor/build_descriptors.py" --check
python3 "$HERE/../research/aircraft-editor/test_descriptor_checkout.py"

echo "== AE-24: generated presentation bindings and source pins stay current"
python3 "$HERE/../research/aircraft-standardization/build_customization.py" --check
python3 "$HERE/../research/aircraft-standardization/test_customization.py"

echo "== AUD-12: generated Master safety-limiter bus layout stays current"
run --script "$HERE/../tools/audio/make_bus_layout.gd" -- --check

echo "== BAT-05/06: generated battery data and the independent pack_ecm reference stay current"
python3 "$HERE/../research/battery/bat-05/build_batteries.py" --check
python3 "$HERE/../research/battery/test_ecm_reference.py"
BAT06_PROBE="$(mktemp)"
run --script "$HERE/../research/battery/bat-06/law_probe.gd" -- --out="$BAT06_PROBE" > /dev/null
python3 "$HERE/../research/battery/bat-06/compare_law.py" "$BAT06_PROBE" > /dev/null || { rm -f "$BAT06_PROBE"; echo "BAT-06 runtime law disagrees with the reference"; exit 1; }
rm -f "$BAT06_PROBE"

echo "== NITRO-02: distinct 2T/4T profiles and finite-fuel installations stay current"
python3 "$HERE/../research/glow-engines/build_profiles.py" --check
python3 "$HERE/../research/glow-engines/build_installations.py" --check
python3 "$HERE/../research/glow-engines/installation_schema.py" --check
python3 "$HERE/../research/glow-engines/test_profiles.py"
python3 "$HERE/../research/glow-engines/test_calibration_report.py"
python3 "$HERE/../research/glow-engines/test_cycle_oracle.py"
python3 "$HERE/../research/glow-engines/test_installation_schema.py"
python3 "$HERE/../research/glow-engines/test_carburetor.py"
python3 "$HERE/../research/glow-engines/test_installation_line_endings.py"
python3 "$HERE/../research/glow-engines/test_build_installations.py"
python3 "$HERE/../research/glow-engines/test_refinement_report.py"
python3 "$HERE/../research/glow-engines/test_pilot_review.py"
python3 "$HERE/../research/fuel-systems/test_fuel_registry.py"
python3 "$HERE/../research/fuel-systems/test_mass_balance_report.py"
python3 "$HERE/../research/fuel-systems/mass_balance_report.py" --check "$HERE/../research/fuel-systems/mass_balance_current.json" --fail-on-drift
python3 "$HERE/../research/glow-engines/reference/test_reference.py"

echo "== P51-16: separated hardware inventory and physical inertia stay consistent"
python3 "$HERE/../research/p51/p51-15/test_inventory.py"

echo "== D11g: Stik rate derivatives and provenance match the current local law"
run --script "$HERE/../research/aero/d11g/derive_rate_derivatives.gd" -- --check

echo "== AV-15: independent geometry, inventory and fixed-build sensitivity checks"
python3 "$HERE/../research/avanti-s/av14/test_geometry_inventory.py"
python3 "$HERE/../research/avanti-s/av14/test_sensitivity.py"
python3 "$HERE/../research/avanti-s/av17-r2/test_build_polar.py"

echo "== L6b offline tree placement matches committed positions"
python3 "$HERE/../tools/trees/place.py" --field "$HERE/data/fields/default.json" --check
python3 "$HERE/../tools/trees/test_place.py"

echo "== AFC-02-R3: companion re-bind tool and its qualification record stay consistent"
python3 "$HERE/../tools/companions/test_rebind.py"

echo "== L7-R1 woodland-edge recipe and full-envelope exclusions stay current"
python3 "$HERE/../tools/trees/place_woodland_edges.py" --check
python3 "$HERE/../tools/trees/test_place_woodland_edges.py"

echo "== No tracked file above 50 MiB without a recorded reason, none above GitHub's 100 MiB limit"
python3 "$HERE/../tools/repo/check_large_files.py"

echo "== LU-34-R1 scene budget report counts every instance of instanced LOD meshes"
python3 "$HERE/../tools/scenery/test_attribution_report.py"

echo "== SC-HUM-07 field-people outfits, shipped variants and manifests agree; scenery layout matches its generator"
python3 "$HERE/../tools/scenery/population/test_outfits.py"
python3 "$HERE/../tools/scenery/place.py" --check

echo "== L11a offline grass placement matches committed offsets"
python3 "$HERE/../tools/grass/place.py" --check
python3 "$HERE/../tools/grass/test_place.py"

echo "== L9e packed turf data matches its deterministic generator"
python3 "$HERE/../tools/ground/turf_generate.py" --check

echo "== L7 offline hill profile matches committed heights"
python3 "$HERE/../tools/terrain/gen_terrain.py" --check

echo "== FW-21/FW-24 sky table and star list match their generators"
python3 "$HERE/../tools/world/sky_table.py" --check
python3 "$HERE/../tools/world/stars.py" --check

echo "== E0b2: Stik hub and neutral tail geometry stay current"
python3 "$HERE/../research/propwash/e0b2/derive_geometry.py" --check
python3 "$HERE/../research/propwash/e0b2/test_geometry.py"

echo "== E0b3b: neutral Stik wash profiles stay current"
python3 "$HERE/../research/propwash/e0b3b/derive_profile.py" --check
python3 "$HERE/../research/propwash/e0b3b/test_profile.py"

echo "== RCV-04a: independent suspension reference and headless bench exports"
python3 "$HERE/../research/rc-monster-truck/generate_suspension_reference.py" --check
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_rcv_suspension_cli.py"

echo "== RCV-04b: coupled support reference and headless experiments"
python3 "$HERE/../research/rc-monster-truck/generate_support_reference.py" --check
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_rcv_support_cli.py"

echo "== RCV-14a: supplied MT8 visual intake and isolated inspector"
python3 "$HERE/../research/rc-monster-truck/build_visual.py" --check
python3 "$HERE/../research/rc-monster-truck/build_vehicle_data.py" --check
python3 "$HERE/../research/rc-monster-truck/test_vehicle_data_generator.py"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/../research/rc-monster-truck/test_experiments.py"
python3 "$HERE/../research/rc-monster-truck/asset_intake.py" --check
python3 "$HERE/../research/rc-monster-truck/test_asset_intake.py"
run_with_timeout 180 --script "$HERE/../research/rc-monster-truck/visual/test_mt8_visual.gd"
run --script "$HERE/../research/rc-monster-truck/visual/test_preview.gd" -- --lang=en
run --script "$HERE/../research/rc-monster-truck/visual/test_preview.gd" -- --lang=es

echo "== RCV-35: source-derived MONSTER CAR 2 data stays current"
python3 "$HERE/../research/rc-monster-truck/monster-car-2/build_vehicle_data.py" --check
python3 "$HERE/../research/rc-monster-truck/monster-car-2/test_build_vehicle_data.py"
python3 "$HERE/../research/rc-monster-truck/monster-car-2/visual_verify.py"

echo "== float64 guard: no 32-bit math types in simulation code"
# Godot's Vector3/Basis/Quaternion/Transform3D are 32-bit; simulation state must stay in 64-bit floats.
# Comment lines are ignored. Rendering code (render/) may use them at the boundary.
SIM_DIRS=()
for d in sim physics; do [ -d "$HERE/$d" ] && SIM_DIRS+=("$HERE/$d"); done
if [ ${#SIM_DIRS[@]} -gt 0 ] && grep -rnE '^\s*[^#[:space:]].*\b(Vector2|Vector3|Vector4|Basis|Quaternion|Transform3D)\b' "${SIM_DIRS[@]}"; then
  echo "32-bit math type found in simulation code (see lines above)"; exit 1
fi

echo "== H6: transcendental calls stay behind math3d"
python3 "$HERE/tests/check_transcendentals.py"
python3 "$HERE/tests/check_transcendentals.py" --self-test

echo "== shaders never read TIME (LANDSCAPE-PLAN L0d: animation runs on sim_clock, so captures repeat)"
# Shader files, plus any script that embeds shader code. Comment lines (// or #) are ignored.
SHADER_FILES=$(cd "$HERE" && { find . \( -name '*.gdshader' -o -name '*.gdshaderinc' \) -not -path './.godot/*'; grep -rl --include='*.gd' 'shader_type' . 2>/dev/null | grep -v '^./.godot/' || true; } | sort -u)
for f in $SHADER_FILES; do
  if grep -nE '^\s*[^/#[:space:]].*\bTIME\b' "$HERE/$f"; then echo "TIME used in $f (use the sim_clock global uniform)"; exit 1; fi
done

echo "== parse check: every script"
(cd "$HERE" && find . -name '*.gd' -not -path './.godot/*' -not -path './captures/*' | sort) | while read -r f; do
  run --check-only --script "res://${f#./}" > /dev/null || { echo "parse error in $f"; exit 1; }
done

fi # offline generators, references and complete parse checks

LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
expected_failure() {
  local label="$1" expected_exit="$2" expected_error="$3"
  shift 3
  local run_dir actual_exit
  if (
    export OPENRC_CHECK_OUT="$EXPECTED_CHECK_OUT"
    export OPENRC_CHECK_LABEL="$label"
    export OPENRC_CHECK_REQUIRED_TEXT="$expected_error"
    run "$@"
  ) > "$LOG" 2>&1; then
    actual_exit=0
  else
    actual_exit=$?
  fi
  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "$label exited $actual_exit; expected $expected_exit" >&2
    cat "$LOG"
    exit 1
  fi
  if ! run_dir="$(python3 - "$LOG" "$EXPECTED_CHECK_OUT" <<'PY'
from pathlib import Path
import sys

log = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
collection = Path(sys.argv[2]).resolve()
report_path = ""
for line in log.splitlines():
    if line.startswith("Godot check failed: ") and "report: " in line:
        report_path = line.split("report: ", 1)[1]
if not report_path:
    raise SystemExit("checked runner did not report its failure evidence path")
report = Path(report_path).resolve()
if report.name != "report.json" or report.parent.parent != collection:
    raise SystemExit("checked runner wrote outside the expected-failure collection")
print(report.parent)
PY
  )"; then
    echo "$label did not produce an expected-failure report path" >&2
    cat "$LOG"
    exit 1
  fi
  python3 "$HERE/tests/check_expected_cli_failure.py" "$run_dir" "$EXPECTED_CHECK_OUT" "$expected_exit" "$expected_error"
}
if [[ "$TEST_PART" != integration ]]; then
unit_index=0
selected_units=0
for t in "$HERE"/tests/test_*.gd; do
  shard_for_test=$((unit_index % UNIT_SHARDS))
  unit_index=$((unit_index + 1))
  [[ "$shard_for_test" == "$UNIT_SHARD" ]] || continue
  selected_units=$((selected_units + 1))
  echo "== $(basename "$t")"
  test_timeout=60
  # Four 46-second simulated landings at 240/480 Hz: measured 75–82 s wall time on Linux (PT1-rc8).
  if [ "$(basename "$t")" = "test_landing_maneuver.gd" ]; then test_timeout=180; fi
  # Seven catalog aircraft rebuild and crash twice: measured 82.90 s in PT1-rc9.
  if [ "$(basename "$t")" = "test_crash_integration.gd" ]; then test_timeout=180; fi
  # Wreck lifecycle checks include timed scene updates: measured 65.46 s in PT1-rc9.
  if [ "$(basename "$t")" = "test_crash_wreck.gd" ]; then test_timeout=180; fi
  # Multiple complete scenery/aircraft rebuilds; not a physics-tick performance gate.
  case "$(basename "$t")" in
    test_half_power_start.gd) test_timeout=600 ;; # D6e-R3: eight airplanes, each solved and flown three times at 240 Hz; measured 219 s on the shared VM, 300 s under load
    test_glow_session.gd) test_timeout=180 ;; # Four coupled installations with replay and takeoff; measured 67 s on Linux.
    test_companions_lifecycle.gd) test_timeout=180 ;; # 50 headless + 10 visual/audio rebuild cycles; measured 67.719 s natively on 4.8 beta1.
    test_glow_dive_support.gd) test_timeout=120 ;; # NITRO-61FX-R1: two 12 s full-throttle dives at 240 Hz; measured 32 s on the shared VM.
    test_extra_handling.gd|test_extra_runway.gd) test_timeout=120 ;; # EX-14c tail slipstream: measured 66 s / 46 s on the quiet shared VM (53 / 41 s before), 77 / 51 s under load.
    test_pilot_trim.gd) test_timeout=300 ;; # Fleet controls plus frozen/live inventory comparisons; measured 117 s natively.
    test_accident_integration.gd) test_timeout=180 ;; # Multiple complete aircraft/effects rebuilds; native 77-check gate, WSL mounted source exceeds 60 s.
    test_p51_envelope.gd) test_timeout=180 ;; # Segmented slipstream full-flight checks measured 61 s on the native editor.
    test_rcv_powertrain.gd) test_timeout=180 ;; # Nine complete powertrain checks; measured 64 s at 240/480 Hz.
    # Full scene transitions and subprocess startup can exceed 60 s; benchmark tools own timing gates.
    test_ui_pause.gd|test_ui_screen_stack.gd|test_landing_variations.gd|test_input_report_cli.gd|test_latency_patch_cli.gd) test_timeout=180 ;;
    test_ui_home_preview_cache.gd) test_timeout=180 ;; # F4U-20-R2: all 13 imported paints, fresh/cached light parity and eviction; 46 s natively.
    test_heli_session.gd|test_heli_ground_session.gd) test_timeout=300 ;; # Actual preset hover, pilot-compensated landing and checkpoint replay.
    test_failure_session.gd|test_failure_shutdown.gd) test_timeout=180 ;; # EM: real 20-second onsets at 240 Hz, fleet parity and replay
    test_failure_routes.gd) test_timeout=180 ;; # EM: two complete flights and Home/Pause transitions
    test_trim_throttle.gd) test_timeout=300 ;; # D6e-R4: fleet-wide cruise-trim runway starts (three glow solves) and four 40 s hands-off flights; measured 78 s on the shared VM
    # v0.1.4 CI max 53.452 s; v0.1.5 prop-strike measured 55.943 s on WSL and hit CI's 60 s cap.
    # Raise supervision only; bounded test loops and all assertion gates remain unchanged.
    test_workshop_starts.gd|test_p51_ground.gd|test_prop_strike.gd|test_p51_handling.gd|test_ui_modal_responsive.gd|test_rcv_handling.gd) test_timeout=120 ;;
    test_rcv_vehicle_dynamics.gd|test_rcv_session.gd|test_rcv_airfield_course.gd|test_rcv_airfield_track.gd|test_rcv_obstacle_contacts.gd|test_rcv_activity.gd|test_rcv_presentation.gd|test_rcv_menu.gd|test_rcv_nitro_activity.gd|test_rcv_nitro_session.gd|test_nitro_dynamics.gd) test_timeout=300 ;;
    test_aircraft_catalog.gd|test_aircraft_light_control.gd|test_ui_aircraft.gd|test_ui_runway.gd|test_landscapes.gd|test_runway_cli.gd|test_runway_fleet.gd|test_workshop_integration.gd|test_workshop_ui.gd|test_ui_natural_random.gd) test_timeout=600 ;;
  esac
  test_args=()
  # Only these two named physical gates are pending for explicitly experimental aircraft behavior.
  # Stable software releases may include these disclosed experimental limits (release policy, 2026-10-16).
  # Direct script invocation without its matching flag remains strict; all other checks stay mandatory.
  case "$(basename "$t")" in
    test_rudder_authority.gd) test_args=(-- --allow-known-stik-rudder-sideslip) ;;
    test_yaw_damping.gd) test_args=(-- --allow-known-r02-yaw-alpha11) ;;
  esac
  run_with_timeout "$test_timeout" --script "res://tests/$(basename "$t")" "${test_args[@]}" 2>&1 | tee "$LOG"
  # run_with_timeout checks every invocation for engine/script/shader errors,
  # including errors printed with a successful process exit.
done

echo "== unit partition $UNIT_SHARD/$UNIT_SHARDS: $selected_units of $unit_index scripts"
(( selected_units > 0 )) || { echo "empty unit partition" >&2; exit 2; }
fi
[[ "$TEST_PART" != units ]] || exit 0

echo "== H7: exact one-ulp math sensitivity and golden branch signatures"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/check_math_sensitivity.py"

echo "== L5: invalid field files fail before Home or flight can start"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_field_failures.py" FieldFailureRoutes.test_headless_invalid_fields_fail_both_routes

echo "== aircraft model contract (aircraft/verify_model.gd, owned by the model team)"
run --script res://aircraft/verify_model.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "aircraft model contract failed (see above)"; exit 1; fi

echo "== Extra 300S .60 model contract (aircraft/verify_extra.gd: geometry, finish, articulation clearances)"
run --script res://aircraft/verify_extra.gd 2>&1 | tee "$LOG" | tail -2
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "Extra preview contract failed (see above)"; exit 1; fi

echo "== P-51D finish parameters are not stale (assets/aircraft/p51d-mustang-120/compile_appearance.py --check, V08)"
python3 "$HERE/../assets/aircraft/p51d-mustang-120/compile_appearance.py" --check || exit 1
echo "== P-51D physics data and ground-effect table are not stale (research/p51/p51-05/derive_physics.py, p51-20/ground_effect_vlm.py --check)"
python3 "$HERE/../research/p51/p51-20/ground_effect_vlm.py" --check || exit 1
python3 "$HERE/../research/p51/p51-05/derive_physics.py" --check || exit 1

echo "== P-51D Mustang 1/4 model contract (aircraft/verify_p51.gd, P51-02: geometry, articulation, determinism)"
run --script res://aircraft/verify_p51.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "P-51 model contract failed (see above)"; exit 1; fi

echo "== P-51D hinge clearances (aircraft/verify_p51_clearance.gd, P51-04/V01/V14: rudder, elevators and flaps at the flown throws and 45 deg; ~75 s native)"
run_with_timeout 180 --script res://aircraft/verify_p51_clearance.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "P-51 clearance contract failed (see above)"; exit 1; fi

echo "== Ventage Jet Blender source and visual contract (AV-31: imported geometry, controls, sections, no propeller)"
python3 "$HERE/../assets/aircraft/avanti-s-a200/compile_blender.py" --check || exit 1
run --script res://aircraft/verify_avanti.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "Avanti visual contract failed (see above)"; exit 1; fi

echo "== Turbo Lumber Evolution asset identity and generated geometry (TT-01/02/03: manifest, mesh measurements, geometry, constants)"
python3 "$HERE/../research/timber/tt01/manifest.py" --check || exit 1
run --script "$HERE/../research/timber/tt02/measure_mesh.gd" -- --out="$HERE/../assets/aircraft/turbo-lumber-evolution/mesh-measurements.json" --check 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|differ" "$LOG"; then echo "Timber mesh measurements are stale or the importer changed (see above)"; exit 1; fi
python3 "$HERE/../assets/aircraft/turbo-lumber-evolution/build_geometry.py" --check || exit 1
python3 "$HERE/../assets/aircraft/turbo-lumber-evolution/compile_geometry.py" --check || exit 1
python3 "$HERE/../research/timber/tt03/check_asset.py" --check || exit 1
python3 "$HERE/../research/timber/tt07/derive_physics.py" --check
python3 "$HERE/../research/timber/tt07/sensitivity.py" --check
python3 "$HERE/../research/timber/tt07/test_derive.py"

echo "== Turbo Lumber Evolution model contract (aircraft/verify_timber.gd, TT-03/TT-05: imported scene, pivots, signs, propeller, gear)"
run --script res://aircraft/verify_timber.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "Timber model contract failed (see above)"; exit 1; fi

echo "== F4U Corsair identity, generated data and model contract (F4U-03/05/07/11/12: manifest, rig, physics, costing, imported scene)"
python3 "$HERE/../research/f4u-corsair/F4U-03/manifest.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-05/compile_model.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-07/ground_effect_vlm.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-07/fit_propeller.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-11/extract_crash_geometry.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-07/derive_physics.py" --check || exit 1
python3 "$HERE/../research/f4u-corsair/F4U-11/costing_entry.py" --check || exit 1
run --script res://aircraft/verify_f4u.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "F4U Corsair model contract failed (see above)"; exit 1; fi

echo "== X8 flying wing identity, generated data and model contract (X8-00/02/06: manifest, assets, model, physics, imported scene)"
python3 "$HERE/../research/skywalker-x8/X8-00/manifest.py" --check || exit 1
python3 "$HERE/../research/skywalker-x8/X8-02/install_assets.py" --check || exit 1
python3 "$HERE/../research/skywalker-x8/X8-02/compile_model.py" --check || exit 1
python3 "$HERE/../research/skywalker-x8/X8-06/derive_physics.py" --check || exit 1
run --script res://aircraft/verify_skywalker_x8.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "X8 model contract failed (see above)"; exit 1; fi

echo "== C7-R1: trace completion, finite samples and failure exits"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_trace_acceptance.py"

echo "== D8b-R2: synthetic polar fixtures, FASER-analog and post-stall-v2 candidates (D8b-R2d) and explicit experimental flight route"
run --script "$HERE/../research/flight-robustness/d8b-r2/make_candidates.gd" -- --check
run --script "$HERE/../research/flight-robustness/d8b-r2/analog/make_analog.gd" -- --check
run --script "$HERE/../research/flight-robustness/d8b-r2/analog/make_v2.gd" -- --check
echo "== EX-14h: the Extra's post-stall wing polar fit is not stale (research/extra-300/ex14/fit_wing_polar.gd --check)"
run --script "$HERE/../research/extra-300/ex14/fit_wing_polar.gd" -- --check
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_pullup_cli.py"

echo "== M5-W01d: weather CLI, explicit v4 clocks/velocity fields and reader negative controls"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_weather_cli.py"

echo "== M5-W04a: seeded turbulence trace oracle and complete-state FPS independence"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_turbulence_cli.py"

echo "== M5-ATM: independent atmosphere, EAS and environment replay checks"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_atmosphere_cli.py"

echo "== M5-ATM-4 / VAL-AUD-R09: complete v11 standard-column CLI traces and endpoint/k1 ISA reader"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_atmosphere_column_cli.py"

echo "== TOD-09a: independent Gregorian clock fixtures stay current"
python3 "$HERE/../research/time-of-day/tod-09a/calendar_oracles.py" --check

echo "== TOD-05/07: selected time, visual context and unchanged flight physics"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_time_of_day_cli.py"

echo "== G2a/G2b: coupled shaft launch, model identity and complete-state FPS independence"
OPENRC_TEST_GODOT="$GODOT" python3 "$HERE/tests/test_shaft_cli.py"

echo "== app: headless --trace starts in trimmed level flight (all five catalog aircraft)"
TRACE="$(mktemp --suffix=.csv)"
run -- --trace="$TRACE" --t=3 > /dev/null 2>&1
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3; rm -f "$TRACE"
TRACE="$(mktemp --suffix=.csv)"
run -- --aircraft=gp-extra-300s-60 --trace="$TRACE" --t=3 > /dev/null 2>&1
grep -q "gp-extra-300s-60" "$TRACE" || { echo "the Extra trace does not name the Extra"; exit 1; }
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3; rm -f "$TRACE"
TRACE="$(mktemp --suffix=.csv)"
run -- --aircraft=p51d-mustang-120 --trace="$TRACE" --t=3 > /dev/null 2>&1
grep -q "p51d-mustang-120" "$TRACE" || { echo "the P-51 trace does not name the P-51"; exit 1; }
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3; rm -f "$TRACE"
TRACE="$(mktemp --suffix=.csv)"
run -- --aircraft=sebart-avanti-s-a200-p100rx --trace="$TRACE" --t=3 > /dev/null 2>&1
grep -q "sebart-avanti-s-a200-p100rx" "$TRACE" || { echo "the Avanti trace does not name the Avanti"; exit 1; }
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3; rm -f "$TRACE"
TRACE="$(mktemp --suffix=.csv)"
run -- --aircraft=turbo-lumber-evolution --battery=ideal --trace="$TRACE" --t=3 > /dev/null 2>&1
grep -q "turbo-lumber-evolution" "$TRACE" || { echo "the Timber trace does not name the Timber"; exit 1; }
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3 --aircraft-input="$HERE/data/aircraft/turbo_lumber_evolution.json"; rm -f "$TRACE"
# BAT-13: v14 carries live mass; the base format still identifies the finite pack.
TRACE="$(mktemp --suffix=.csv)"
run -- --aircraft=turbo-lumber-evolution --trace="$TRACE" --t=3 > /dev/null 2>&1
grep -q "openrc-trace v14" "$TRACE" && grep -q "mass_base_trace_format.*openrc-trace v13" "$TRACE" || { echo "the default Timber trace is not a finite-pack mass trace"; exit 1; }
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE" --duration=3 --aircraft-input="$HERE/data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"; rm -f "$TRACE"
echo "== Avanti S physics data is not stale (research/avanti-s/av06/derive_physics.py --check, AV-06)"
python3 "$HERE/../research/avanti-s/av06/derive_physics.py" --check || exit 1
echo "== app: an unknown aircraft is refused on the direct route (exit 1, never another airplane)"
expected_failure unknown-aircraft 1 "aircraft 'no-such-aircraft' refused: not in the catalog (" \
  -- --aircraft=no-such-aircraft --trace=/dev/null --t=1
echo "refused"

echo "== NITRO-02: both finite-fuel glow catalog routes emit complete versioned traces"
GLOW_WORK="$(mktemp -d)"
python3 "$HERE/../research/glow-engines/packaged_smoke.py" --godot "$GODOT" --out "$GLOW_WORK/results"
rm -rf "$GLOW_WORK"

echo "== frame-time logger writes its report (LANDSCAPE-PLAN L0e; headless numbers are plumbing, not performance)"
FT="$(mktemp --suffix=.json)"
run -- --frametimes="$FT" --t=1.5 > /dev/null 2>&1
python3 - "$FT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
ms = r["frame_ms"]
assert r["frames"] > 10 and r["seconds"] >= 1.5, r
assert r["format"] == "openrc-frametimes v2" and r["complete"] is True
assert r["route"] == "live-input" and r["input_enabled"] is True
assert len(r["frame_deltas_s"]) == r["frames"]
assert abs(sum(r["frame_deltas_s"]) - r["seconds"]) < 1e-8
assert all(len(values) == r["frames"] for values in r["raw_metrics"].values())
assert r["simulation"]["ticks"] > 0 and r["actual_warmup_s"] >= 1.0
assert 0 < ms["p50"] <= ms["p95"] <= ms["p99"] <= ms["max"], ms
assert all(k in r for k in ("adapter", "api", "godot", "os", "vsync", "physics_us_per_tick")), sorted(r)
print(f"frame-time report: {r['frames']} frames, p50 {ms['p50']:.2f} <= p95 {ms['p95']:.2f} <= p99 {ms['p99']:.2f} ms")
PY
rm -f "$FT"

echo "== VQ-01b: scripted logger disables input and identifies its route"
FT="$(mktemp --suffix=.json)"
run -- --frametimes="$FT" --warmup=0 --t=0.1 --scripted --case=logger-smoke > "$LOG" 2>&1
if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then cat "$LOG"; exit 1; fi
python3 - "$FT" <<'PYLOGGER'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["route"] == "scripted-fixed" and r["case_id"] == "logger-smoke"
assert r["input_enabled"] is False and r["simulation"]["ticks"] == 0
assert r["complete"] is True and r["seconds"] >= 0.1
assert r["seconds"] - r["frame_deltas_s"][-1] < 0.100001
assert r["warmup_s"] == 0 and r["backend"] and r["preset"]
print("scripted route, raw samples and disabled input verified")
PYLOGGER
rm -f "$FT"
echo "== VQ-01b: invalid logger options and output write failures fail the process"
python3 "$HERE/tests/check_expected_cli_failure.py" --self-test
expected_failure frametimes-t-zero 31 "--t must be greater than 0 and at most 300 seconds" \
  -- --frametimes=/dev/null --t=0
expected_failure frametimes-t-nan 31 "--t requires a finite number" \
  -- --frametimes=/dev/null --t=nan
expected_failure frametimes-warmup-negative 31 "--warmup must be between 0 and 3600 seconds" \
  -- --frametimes=/dev/null --warmup=-1
expected_failure frametimes-capture-conflict 31 "--frametimes cannot be combined with --trace or --capture" \
  -- --frametimes=/dev/null --capture
expected_failure frametimes-trace-conflict 31 "--frametimes cannot be combined with --trace or --capture" \
  -- --frametimes=/dev/null --trace=/dev/null
expected_failure frametimes-write-failure 1 "Cannot write frame-time report '" \
  -- --frametimes="$HERE" --warmup=0 --t=0.01

echo "== fixed step: the real app with injected keys reaches the same state at 30, 60 and 144 fps rendering"
HASHES=""
for fps in 30 60 144; do
  out="$(run --fixed-fps "$fps" --script res://tests/run_fixed_step.gd 2>&1)"
  echo "$out" | grep -E "ticks=|ERROR"
  if echo "$out" | grep -qE "^(SCRIPT )?ERROR:"; then echo "engine error at $fps fps"; exit 1; fi
  HASHES="$HASHES $(echo "$out" | sed -n 's/.*state_sha256=\([0-9a-f]*\).*/\1/p')"
done
if [ "$(echo $HASHES | tr ' ' '\n' | sort -u | wc -l)" -ne 1 ] || [ -z "$(echo $HASHES | tr -d ' ')" ]; then
  echo "final state depends on the rendering frame rate:$HASHES"; exit 1
fi
echo "identical"

echo "== TT-08: Timber coupled electric flight is identical at 30/60/144 fps"
HASHES=""
for fps in 30 60 144; do
  out="$(run --fixed-fps "$fps" --script res://tests/run_fixed_step.gd -- --aircraft=turbo-lumber-evolution 2>&1)"
  echo "$out" | grep -E "ticks=|ERROR"
  if echo "$out" | grep -qE "^(SCRIPT )?ERROR:"; then echo "Timber engine error at $fps fps"; exit 1; fi
  HASHES="$HASHES $(echo "$out" | sed -n 's/^flight_sha256=\([0-9a-f]*\)$/\1/p')"
done
if [ "$(echo $HASHES | tr ' ' '\n' | sort -u | wc -l)" -ne 1 ] || [ -z "$(echo $HASHES | tr -d ' ')" ]; then
  echo "Timber complete checkpoint depends on the rendering frame rate:$HASHES"; exit 1
fi
echo "identical Timber complete checkpoints"

echo "== E0b5: experimental wash transport at 30/60/144 fps"
python3 "$HERE/../research/propwash/e0b5/check_frames.py" --godot "$GODOT"

echo "== E0b6p: distributed swirl at 30/60/144 fps"
python3 "$HERE/../research/propwash/e0b6p/check_frames.py" --godot "$GODOT"

echo "== E5a: generated Extra taildragger contacts, P-51 review and session refinement"
E5A_WORK="$(mktemp -d)"
python3 "$HERE/../research/ground-contact/e5a/verify.py" --godot "$GODOT" --out "$E5A_WORK/results"
rm -rf "$E5A_WORK"

echo "== E5b: tail-up pitch threshold, rigid tail lift and synthetic resistance patches"
E5B_WORK="$(mktemp -d)"
python3 "$HERE/../research/ground-contact/e5b/verify.py" --godot "$GODOT" --out "$E5B_WORK/results"
rm -rf "$E5B_WORK"
