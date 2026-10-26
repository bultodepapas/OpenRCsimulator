#!/usr/bin/env bash
# Headless checks (no display needed). Fails if any script fails to parse or any test fails.
set -euo pipefail
HERE="C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-full-suite/app"
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
