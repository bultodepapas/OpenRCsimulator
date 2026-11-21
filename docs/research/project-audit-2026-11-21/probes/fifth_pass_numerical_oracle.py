#!/usr/bin/env python3
"""Independent plane-intersection and scalar RK4 checks on two emitted logs."""
import json
import math
from pathlib import Path
import sys


def record(path: str, prefix: str):
    line = next(s for s in Path(path).read_text().splitlines() if s.startswith(prefix + " "))
    return json.loads(line[len(prefix) + 1:])


race = record(sys.argv[1], "R5_RACE_RESULT")
h, a, vn, vu, width = 1 / 240, 40.0, 2.0, 40.0, 1.5
v0 = vn - a * h / 2
t_hit = vn * h / (v0 + math.sqrt(v0 * v0 + a * vn * h))
u_hit = width - 0.001 + vu * (t_hit - h / 2)
eps = 250 * h * h / 8
assert abs(-vn * h / 2 + v0 * t_hit + a * t_hit * t_hit / 2) < 1e-15
assert v0 > 1 and a < 250 and a * h * h / 8 < eps
assert width - 0.001 < width - eps and u_hit > width
assert race["gate_count"] == 1 and "race_gate" in race["event_types"]
assert math.isclose(race["analytic_u_m"], u_hit, abs_tol=1e-13)
assert math.isclose(race["intersection_error_m"], u_hit - (width - 0.001), abs_tol=1e-13)
assert math.isclose(race["projected_uncertainty_m"], eps * math.hypot(1, vu / vn), abs_tol=1e-13)
print("plane-intersection error %.12g m; pointwise chord allowance %.12g m" %
      (u_hit - (width - 0.001), eps))

thermal = record(sys.argv[2], "R5_THERMAL_RESULT")
startup = record(sys.argv[2], "R5_THERMAL_STARTUP_RESULT")
refinement = record(sys.argv[2], "R5_THERMAL_REFINEMENT_RESULT")
tau = 0.001


def rk4(z):
    return 1 + z + z * z / 2 + z**3 / 6 + z**4 / 24


assert thermal["thermal_tau_s"] == tau and thermal["pack_current_a"] == 0
assert thermal["final_tick"] == thermal["initial_tick"] + 1 and not thermal["fault"]
assert thermal["old_pack_step_ratio"] < 0.25
assert math.isclose(thermal["after_k"] - thermal["ambient_k"], 0.1 * rk4(-h / tau), abs_tol=1e-10)
assert rk4(-h / tau) > 1 and 0 < math.exp(-h / tau) < 1
assert startup["before_k"] == startup["ambient_k"]
assert startup["initial_heat_w"] > 0 and startup["final_heat_w"] > 0
assert startup["after_k"] < startup["ambient_k"] and not startup["fault"]
assert [r["hz"] for r in refinement] == [240, 480, 960, 1920]
errors = []
for r in refinement:
    count = r["hz"] // 240
    expected = 0.1 * rk4(-1 / (r["hz"] * tau))**count
    assert r["ticks"] == count and not r["fault"]
    assert math.isclose(r["time_s"], h, abs_tol=1e-15)
    assert math.isclose(r["temperature_excess_k"], expected, abs_tol=2e-10)
    errors.append(abs(r["temperature_excess_k"] - 0.1 * math.exp(-h / tau)))
assert all(a > b for a, b in zip(errors, errors[1:]))
print("thermal RK4 factor %.12g vs exact %.12g; same-time refinement errors %s K" %
      (rk4(-h / tau), math.exp(-h / tau), errors))
print("NUMERICAL_ORACLE_COMPLETE")
