#!/usr/bin/env python3
"""Read-only R06 reproduction of the production propeller/wake equations.

This intentionally evaluates the candidate's authored CT/CP tables with the
same interpolation, extrapolation floors, thrust/power equations and smooth
axial wake equations as app/physics/{propulsion,slipstream}.gd. It does not
modify or import the simulator, and it fails closed if the expected source
identity or source-law text changes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


EXPECTED_CANDIDATE_SHA256 = "dfd289f5c8f392fb12e247b1cb14803feafd337339f1baf372154d2c53cedb20"
RHO_KG_M3 = 1.225
SPEEDS_MPS = (15.0, 29.0)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repo_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "app" / "physics" / "propulsion.gd").is_file():
            return parent
    raise RuntimeError("could not locate repository root from probe path")


def coefficient_raw(rows: list[list[float]], advance_ratio: float) -> float:
    """Piecewise-linear table, with the production terminal extrapolation."""
    if advance_ratio <= rows[0][0]:
        return float(rows[0][1])
    for left, right in zip(rows, rows[1:]):
        if advance_ratio <= right[0]:
            fraction = (advance_ratio - left[0]) / (right[0] - left[0])
            return float(left[1] + fraction * (right[1] - left[1]))
    left, right = rows[-2:]
    slope = (right[1] - left[1]) / (right[0] - left[0])
    return float(right[1] + slope * (advance_ratio - right[0]))


def coefficient_production(rows: list[list[float]], advance_ratio: float, floor: float) -> float:
    raw = coefficient_raw(rows, advance_ratio)
    return max(floor, raw) if advance_ratio > rows[-1][0] else raw


def require_source_contract(propulsion: str, slipstream: str) -> dict[str, str]:
    required_propulsion = (
        "const STOPPED_RPM := 1.0",
        "const CT_FLOOR := -0.1",
        "const CP_FLOOR := 0.0",
        "static func coefficient(table: PackedFloat64Array, J: float, floor_value: float) -> float:",
        "var J := maxf(along, 0.0) / (n * D)",
        "var thrust := coefficient(prop.ct, J, CT_FLOOR) * rho * n * n * M.pow_(D, 4)",
        "var power := coefficient(prop.cp, J, _cp_floor(prop)) * rho * n * n * n * M.pow_(D, 5)",
        "return PackedFloat64Array([thrust, power / (TAU * n), J])",
    )
    required_slipstream = (
        "var u: float = axial if smooth else maxf(axial, 0.0)",
        "var vs := M.sqrt_(maxf(u * u + 2.0 * thrust / (rho * area), 0.0))",
        "var w := 0.5 * (vs - u)",
        "dv = k_w * w",
    )
    for fragment in required_propulsion:
        if fragment not in propulsion:
            raise RuntimeError(f"production propulsion source no longer matches expected law: {fragment}")
    for fragment in required_slipstream:
        if fragment not in slipstream:
            raise RuntimeError(f"production slipstream source no longer matches expected law: {fragment}")
    return {
        "propulsion_source_contract": "matched expected J/table/floor/thrust/power/torque equations",
        "slipstream_source_contract": "matched expected signed smooth axial momentum/wake equations",
    }


def load_expected_sources(root: Path) -> tuple[dict[str, Any], dict[str, Path]]:
    candidate_rel = Path("research/physics-audit-2026-10-14/remediation/stik_wash_candidate/aircraft_v2.json")
    identities_rel = Path("docs/research/physics-audit-2026-10-14/remediation/R06/source-identities.json")
    paths = {
        "candidate_aircraft_v2": root / candidate_rel,
        "source_identities": root / identities_rel,
        "propulsion_gd": root / "app/physics/propulsion.gd",
        "slipstream_gd": root / "app/physics/slipstream.gd",
        "wash_transport_gd": root / "app/physics/wash_transport.gd",
        "baseline_aircraft_v1": root / "app/data/aircraft/jensen_ugly_stik_60.json",
    }
    for label, path in paths.items():
        if not path.is_file():
            raise RuntimeError(f"required input missing: {label}: {path}")
    identity = json.loads(paths["source_identities"].read_text(encoding="utf-8"))
    expected = identity["candidate"]["sha256"]
    actual = sha256(paths["candidate_aircraft_v2"])
    if expected != EXPECTED_CANDIDATE_SHA256 or actual != EXPECTED_CANDIDATE_SHA256:
        raise RuntimeError(f"candidate/source identity mismatch: expected {EXPECTED_CANDIDATE_SHA256}, got {actual}")
    return identity, paths


def run() -> dict[str, Any]:
    root = repo_root()
    identity, paths = load_expected_sources(root)
    candidate = json.loads(paths["candidate_aircraft_v2"].read_text(encoding="utf-8"))
    propulsion_text = paths["propulsion_gd"].read_text(encoding="utf-8")
    slipstream_text = paths["slipstream_gd"].read_text(encoding="utf-8")
    contract = require_source_contract(propulsion_text, slipstream_text)

    prop = candidate["propulsion"]["propeller"]
    engine = candidate["propulsion"]["engine"]
    slip = prop["slipstream"]
    diameter_m = float(prop["diameter"]["value"])
    idle_rpm = float(engine["idle_rpm"]["value"])
    axis_angles = [float(x) for x in prop["thrust_angles"]["value"]]
    if axis_angles != [0.0, 0.0]:
        raise RuntimeError(f"probe assumes candidate's authored zero shaft angles, got {axis_angles}")
    ct_rows = [[float(j), float(c)] for j, c in prop["ct_table"]["value"]]
    cp_rows = [[float(j), float(c)] for j, c in prop["cp_table"]["value"]]
    wash_factors = [float(x) for x in slip["wash_factor"]["value"]]
    if len(wash_factors) != 2:
        raise RuntimeError("expected two authored wash_factor values")

    ct_floor = -0.1
    cp_floor = min(0.0, float(prop.get("cp_min", 0.0)))
    if "const CT_FLOOR := -0.1" not in propulsion_text or "const CP_FLOOR := 0.0" not in propulsion_text:
        raise RuntimeError("production floor constants changed; update this explicitly reviewed probe")

    n_rev_s = idle_rpm / 60.0
    area_m2 = math.pi * (diameter_m * 0.5) ** 2
    rows: list[dict[str, Any]] = []
    for speed in SPEEDS_MPS:
        j = max(speed, 0.0) / (n_rev_s * diameter_m)
        ct_raw = coefficient_raw(ct_rows, j)
        cp_raw = coefficient_raw(cp_rows, j)
        ct_used = coefficient_production(ct_rows, j, ct_floor)
        cp_used = coefficient_production(cp_rows, j, cp_floor)
        thrust_n = ct_used * RHO_KG_M3 * n_rev_s**2 * diameter_m**4
        shaft_power_w = cp_used * RHO_KG_M3 * n_rev_s**3 * diameter_m**5
        torque_nm = shaft_power_w / (2.0 * math.pi * n_rev_s)

        # Candidate has edge_fraction, so production wake() uses signed axial u.
        axial_speed = speed
        radicand = axial_speed**2 + 2.0 * thrust_n / (RHO_KG_M3 * area_m2)
        disc_velocity_mps = math.sqrt(max(radicand, 0.0))
        induced_velocity_mps = 0.5 * (disc_velocity_mps - axial_speed)
        m = axial_speed / max(axial_speed + induced_velocity_mps, 1e-6) if induced_velocity_mps > 0.0 else 1.0
        blend = max(0.0, min(1.0, m / 0.75))
        k_w = wash_factors[0] + blend * (wash_factors[1] - wash_factors[0])
        tail_increment_mps = k_w * induced_velocity_mps

        rows.append({
            "speed_mps": speed,
            "rho_kg_m3": RHO_KG_M3,
            "rpm": idle_rpm,
            "n_rev_s": n_rev_s,
            "diameter_m": diameter_m,
            "advance_ratio_J": j,
            "last_measured_table_J": max(ct_rows[-1][0], cp_rows[-1][0]),
            "outside_table_domain": j > max(ct_rows[-1][0], cp_rows[-1][0]),
            "ct_raw_linear_extrapolation": ct_raw,
            "ct_used_after_production_floor": ct_used,
            "ct_floor": ct_floor,
            "cp_raw_linear_extrapolation": cp_raw,
            "cp_used_after_production_floor": cp_used,
            "cp_floor": cp_floor,
            "thrust_n": thrust_n,
            "shaft_power_w": shaft_power_w,
            "shaft_torque_nm": torque_nm,
            "momentum_discriminant_m2_s2": radicand,
            "disc_far_speed_mps": disc_velocity_mps,
            "actuator_disc_induced_speed_w_mps": induced_velocity_mps,
            "wake_wash_factor_kw": k_w,
            "tail_wash_increment_dv_mps": tail_increment_mps,
        })

    source_paths = {name: path.relative_to(root).as_posix() for name, path in paths.items()}
    source_hashes = {name: sha256(path) for name, path in paths.items()}
    source_hashes["probe_self"] = sha256(Path(__file__).resolve())
    return {
        "record": "r06_stik_idle_propulsion_and_wake_source_equivalent_reproduction",
        "method": "Python evaluation of candidate aircraft-v2 table data with the source-verified equations listed in app/physics/propulsion.gd and app/physics/slipstream.gd; no simulator files modified",
        "runtime_formula_contract": contract,
        "candidate_id": candidate.get("id", ""),
        "candidate_propeller": prop.get("name", ""),
        "engine_idle_rpm": idle_rpm,
        "rho_kg_m3": RHO_KG_M3,
        "shaft_axis_angles_deg": axis_angles,
        "wash_factor_assumptions": wash_factors,
        "propeller_table_provenance": {
            "ct": prop["ct_table"].get("source", ""),
            "cp": prop["cp_table"].get("source", ""),
        },
        "source_identity_candidate_sha256_recorded": identity["candidate"]["sha256"],
        "rows": rows,
        "source_files": source_paths,
        "source_sha256": source_hashes,
        "interpretation_limit": "The J values exceed the last table point (0.788), so CT/CP are extrapolated. The negative CT sign is model output; CP floors to zero, hence this is not an energy-balanced windmilling prediction or physical validation.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="exclusive-create JSON output path; an existing file is never overwritten")
    args = parser.parse_args()
    result = run()
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        try:
            with args.output.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(rendered)
        except FileExistsError:
            raise SystemExit(f"refusing to overwrite existing evidence: {args.output}")
    sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
