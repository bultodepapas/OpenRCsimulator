#!/usr/bin/env python3
"""Independent checks on E0b4 measurements, plus isolated evidence-corruption probes."""
import argparse
import copy
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT = ROOT / "docs/research/propwash/E0b4/results.json"


def near(a, b, tol=2e-10):
    assert math.isfinite(a) and math.isfinite(b)
    assert abs(a-b) <= tol*max(1.0, abs(b)), (a, b)


def coefficient(table, advance):
    for (x, y), (x1, y1) in zip(table, table[1:]):
        if advance <= x1:
            return y+(y1-y)*(advance-x)/(x1-x)
    raise AssertionError("Experiment outside tabulated positive-thrust advance ratio")


def validate(data, freshness=True):
    aircraft = json.loads((ROOT / "app/data/aircraft/jensen_ugly_stik_60.json").read_text())
    prop = aircraft["propulsion"]["propeller"]
    diameter = prop["diameter"]["value"]
    disc_area = math.pi*diameter**2/4
    rho = data["rho_kg_m3"]
    if freshness:
        assert len(data["source_sha256"]) == 15
        for path, expected in data["source_sha256"].items():
            assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == expected, f"stale source: {path}"
    assert data["production_slipstream_absent"] and "slipstream" not in prop
    assert data["worst_normalized_derivative_refinement"] < 1e-4
    grid = data["grid"]
    expected = set(itertools.product(grid["ks"], grid["kf"], grid["edge_fraction"], grid["vertical_drift"]))
    actual = {(c["ks"], c["kf"], c["edge"], c["drift"]) for c in data["cases"]}
    assert len(expected) == len(actual) == len(data["cases"]) == 81
    assert actual == expected
    baseline = {r["name"]: r for r in data["baseline"]}
    assert len(baseline) == 7
    all_cases = data["cases"] + [data["source_typical"], {"ks": 2., "kf": 2., "conditions": data["ideal_speed_reference"]}]
    count = 0
    for case in all_cases:
        assert {r["name"] for r in case["conditions"]} == set(baseline)
        for row in case["conditions"]:
            b = baseline[row["name"]]
            for key in ["speed_m_s", "rpm", "throttle", "alpha_deg", "beta_deg", "controls_rad"]:
                assert row[key] == b[key], ("condition changed", key)
            n = row["rpm"]/60
            v = row["speed_m_s"]
            u = v*math.cos(math.radians(row["alpha_deg"]))*math.cos(math.radians(row["beta_deg"]))
            ct = coefficient(prop["ct_table"]["value"], u/(n*diameter))
            thrust = ct*rho*n*n*diameter**4
            near(row["thrust_N"], thrust)
            induced = (math.sqrt(u*u+2*thrust/(rho*disc_area))-u)/2
            near(row["induced_m_s"], induced)
            # Independent momentum conservation, including oblique trim shaft projection.
            near(2*rho*disc_area*induced*(u+induced), thrust)
            ratio = min(max((u/(u+induced))/.75, 0), 1)
            factor = case["ks"]+(case["kf"]-case["ks"])*ratio
            near(row["velocity_factor"], factor)
            dv = factor*induced
            near(row["added_axial_m_s"], dv)
            q0 = rho*v*v/2
            dq = rho*(2*u*dv+dv*dv)/2
            near(row["centre_q_Pa"], q0+dq)
            near(row["wake_radius_m"], diameter/2*math.sqrt((u+induced)/(u+2*induced)))
            assert len(row["increment"]) == 6 and all(math.isfinite(x) for x in row["increment"])
            for surface, coverage in row["coverage"].items():
                area = coverage["weighted_area_m2"]
                assert 0 <= area <= coverage["geometric_area_m2"]+1e-12
                near(coverage["geometric_fraction"], area/coverage["geometric_area_m2"])
                near(coverage["aerodynamic_fraction"], area/coverage["aerodynamic_area_m2"])
                near(coverage["mean_q_proxy_Pa"], q0+coverage["aerodynamic_fraction"]*dq)
                if v:
                    near(coverage["mean_q_proxy_ratio"], coverage["mean_q_proxy_Pa"]/q0)
                else:
                    assert coverage["mean_q_proxy_ratio"] is None
            if v == 0:
                # At rest a squared multiplier belongs in q: q = ks²*T/(4*disc area).
                near(row["centre_q_Pa"], case["ks"]**2*thrust/(4*disc_area))
                assert row["centre_q_ratio"] is None
            else:
                near(row["centre_q_ratio"], (q0+dq)/q0)
                if "derivatives" in row:
                    assert set(row["derivatives"]) == {"Cma", "Cma_held", "Cmq", "Cnb", "Cnr", "Cmde", "Cndr"}
                    assert all(math.isfinite(x) for x in row["derivatives"].values())
            count += 1
    # Units/sign sanity against attached-flow data; this is not a wash acceptance or fidelity band.
    nominal = baseline["baseline_trim_15"]["derivatives"]
    source = aircraft["aero"]["coefficients"]
    for key in ["Cmq", "Cnb", "Cnr", "Cmde", "Cndr"]:
        assert abs(nominal[key]/source[key]["value"]-1) < .02, ("derivative normalization", key)
    # Static flow has m=0 and no drift: forward endpoint/drift cannot change the static answer.
    static = {}
    for case in data["cases"]:
        key = (case["ks"], case["edge"])
        row = next(r for r in case["conditions"] if r["name"] == "axial_full_0")
        value = (row["increment"], row["coverage"], case["static_controls"])
        assert static.setdefault(key, value) == value
        for field in ["static_controls", "static_controls_zero_cl"]:
            for samples in case[field].values():
                assert len(samples) == 17 and all(math.isfinite(p["moment_Nm"]) for p in samples)
    modes = data["baseline_modes"] + data["retrimmed_modes"] + data["source_typical"]["modes"]
    assert len(data["retrimmed_modes"]) == 27 and len(modes) == 33
    for mode in modes:
        assert mode["ok"], mode
        assert mode["trim"]["residual"] < 1e-8
        assert 0 <= mode["trim"]["throttle"] <= 1
        for key in ["short_period", "dutch_roll", "phugoid"]:
            assert math.isfinite(mode[key]["zeta"]) and math.isfinite(mode[key]["f_hz"])
        assert mode["downwash_lag_root"] < 0
    return count


def probes(data):
    changes = [
        ("incorrect velocity factor", lambda x: x["cases"][0]["conditions"][0].__setitem__("added_axial_m_s", 123.)),
        ("missing configuration", lambda x: x["cases"].pop()),
        ("wrong pressure weighting", lambda x: x["cases"][0]["conditions"][0]["coverage"]["horizontal"].__setitem__("mean_q_proxy_Pa", 0.)),
        ("changed comparison throttle", lambda x: x["cases"][0]["conditions"][0].__setitem__("throttle", .9)),
        ("wrong derivative units", lambda x: x["baseline"][1]["derivatives"].__setitem__("Cmq", .01)),
        ("lost lag mode", lambda x: x["retrimmed_modes"][0].__setitem__("downwash_lag_root", 1.)),
    ]
    for label, change in changes:
        modified = copy.deepcopy(data)
        change(modified)
        try:
            validate(modified, False)
        except AssertionError:
            print("rejected:", label)
        else:
            raise AssertionError("evidence corruption accepted: "+label)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("result", nargs="?", type=Path, default=DEFAULT)
    parser.add_argument("--probes", action="store_true")
    args = parser.parse_args()
    data = json.loads(args.result.read_text())
    print(f"E0b4: {validate(data)} conditions independently checked; source hashes current; 33 mode solves valid")
    if args.probes:
        probes(data)
