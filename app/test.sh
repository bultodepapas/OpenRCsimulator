#!/usr/bin/env bash
# Headless checks (no display needed). Fails if any script fails to parse or any test fails.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT="$("$HERE/get-godot.sh")"
run() { timeout 60 "$GODOT" --headless --path "$HERE" --audio-driver Dummy "$@"; }

echo "== float64 guard: no 32-bit math types in simulation code"
# Godot's Vector3/Basis/Quaternion/Transform3D are 32-bit; simulation state must stay in 64-bit floats.
# Comment lines are ignored. Rendering code (render/) may use them at the boundary.
SIM_DIRS=()
for d in sim physics; do [ -d "$HERE/$d" ] && SIM_DIRS+=("$HERE/$d"); done
if [ ${#SIM_DIRS[@]} -gt 0 ] && grep -rnE '^\s*[^#[:space:]].*\b(Vector2|Vector3|Vector4|Basis|Quaternion|Transform3D)\b' "${SIM_DIRS[@]}"; then
  echo "32-bit math type found in simulation code (see lines above)"; exit 1
fi

echo "== shaders never read TIME (LANDSCAPE-PLAN L0d: animation runs on sim_clock, so captures repeat)"
# Shader files, plus any script that embeds shader code. Comment lines (// or #) are ignored.
SHADER_FILES=$(cd "$HERE" && { find . \( -name '*.gdshader' -o -name '*.gdshaderinc' \) -not -path './.godot/*'; grep -rl --include='*.gd' 'shader_type' . 2>/dev/null | grep -v '^./.godot/' || true; } | sort -u)
for f in $SHADER_FILES; do
  if grep -nE '^\s*[^/#[:space:]].*\bTIME\b' "$HERE/$f"; then echo "TIME used in $f (use the sim_clock global uniform)"; exit 1; fi
done

echo "== parse check: every script"
(cd "$HERE" && find . -name '*.gd' -not -path './.godot/*' | sort) | while read -r f; do
  run --check-only --script "res://${f#./}" > /dev/null || { echo "parse error in $f"; exit 1; }
done

LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
for t in "$HERE"/tests/test_*.gd; do
  echo "== $(basename "$t")"
  run --script "res://tests/$(basename "$t")" 2>&1 | tee "$LOG"
  # Godot reports runtime script errors without failing the run; treat any as a failure.
  if grep -qE "^(SCRIPT )?ERROR:" "$LOG"; then echo "engine error during $(basename "$t") (see above)"; exit 1; fi
done

echo "== aircraft model contract (aircraft/verify_model.gd, owned by the model team)"
run --script res://aircraft/verify_model.gd 2>&1 | tee "$LOG" | tail -1
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "aircraft model contract failed (see above)"; exit 1; fi

echo "== Extra 300S .60 preview contract (aircraft/verify_extra.gd, EX-02: visual only, not flyable)"
run --script res://aircraft/verify_extra.gd 2>&1 | tee "$LOG" | tail -2
if grep -qE "^(SCRIPT )?ERROR:|FAIL" "$LOG"; then echo "Extra preview contract failed (see above)"; exit 1; fi

echo "== app: headless --trace starts in trimmed level flight"
TRACE="$(mktemp --suffix=.csv)"
run -- --trace="$TRACE" --t=3 > /dev/null 2>&1
python3 "$HERE/tests/check_trimmed_flight.py" "$TRACE"; rm -f "$TRACE"

echo "== frame-time logger writes its report (LANDSCAPE-PLAN L0e; headless numbers are plumbing, not performance)"
FT="$(mktemp --suffix=.json)"
run -- --frametimes="$FT" --t=1.5 > /dev/null 2>&1
python3 - "$FT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
ms = r["frame_ms"]
assert r["frames"] > 10 and r["seconds"] >= 1.5, r
assert 0 < ms["p50"] <= ms["p95"] <= ms["p99"] <= ms["max"], ms
assert all(k in r for k in ("adapter", "api", "godot", "os", "vsync", "physics_us_per_tick")), sorted(r)
print(f"frame-time report: {r['frames']} frames, p50 {ms['p50']:.2f} <= p95 {ms['p95']:.2f} <= p99 {ms['p99']:.2f} ms")
PY
rm -f "$FT"

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

