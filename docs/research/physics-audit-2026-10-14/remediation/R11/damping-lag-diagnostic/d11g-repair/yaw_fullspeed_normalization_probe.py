"""Quantify the R02 comparison probe's max-plane-speed normalization difference.

The production wing-flow selector normalizes section-plane Vp by the maximum full
3-D strip speed. The matched yaw comparator uses max(Vp), omitting the small side
component created by yaw rate at the ARP-to-CG x-arm. This read-only probe compares
the two normalizers with the same R02 section CL and force equations.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path


ROOT = next(
    parent
    for parent in Path(__file__).resolve().parents
    if (parent / "research/aero/d11f/wing_yaw_damping.py").is_file()
)
HERE = Path(__file__).resolve().parent
COMPARATOR = HERE / "yaw_r02_vs_kj_comparison.py"
INPUT_EXPORT = HERE / "yaw_r02_input_export-v1.json"
AIRCRAFT = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
AERO_SOURCE = ROOT / "app/physics/aero.gd"


def _load_comparator():
    spec = importlib.util.spec_from_file_location("r02_yaw_comparator", COMPARATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load retained R02 comparator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _cg_x_from_inventory(raw: dict) -> tuple[float, float]:
    mass = 0.0
    first_moment_x = 0.0
    for item in raw["inventory"]:
        item_mass = float(item["mass"]["value"])
        x = float(item["position"]["value"][0])
        mass += item_mass
        first_moment_x += item_mass * x
    if mass <= 0.0:
        raise ValueError("aircraft inventory has no positive mass")
    return first_moment_x / mass, mass


def _flows(alpha: float, rate: float, ys: list[float], arm_x: float):
    v0 = 15.0 * math.cos(alpha)
    v2 = 15.0 * math.sin(alpha)
    side = rate * arm_x
    u = [v0 - rate * y for y in ys]
    w = [v2] * len(ys)
    vp = [math.hypot(u[i], w[i]) for i in range(len(ys))]
    angles = [math.atan2(w[i], u[i]) for i in range(len(ys))]
    full = [math.sqrt(u[i] * u[i] + side * side + w[i] * w[i]) for i in range(len(ys))]
    plane_reference = max(vp)
    full_reference = max(full)
    plane_sources = [value / plane_reference for value in vp]
    full_sources = [value / full_reference for value in vp]
    return (u, w, vp, angles, plane_sources), (u, w, vp, angles, full_sources), full, side


def _section_cl(data, ys, e, a0, flow):
    _, _, _, angles, sources = flow
    cl0 = list(map(float, data["geometry"]["strip_cl0"]))
    cl = []
    for i in range(len(ys)):
        value = cl0[i]
        for j in range(len(ys)):
            weight = 1.0 if i == j else sources[j]
            value += a0 * e[i][j] * angles[j] * weight
        cl.append(value)
    return cl


def _cnr_for(comparator, data, ys, e, a0, alpha, arm_x, use_full_reference):
    def moment(rate):
        plane_flow, full_flow, _, _ = _flows(alpha, rate, ys, arm_x)
        flow = full_flow if use_full_reference else plane_flow
        cl = _section_cl(data, ys, e, a0, flow)
        return comparator._r02_forces(
            data, ys, data["aero"], alpha, rate, cl, flow
        )["total"]

    h = comparator.H
    b = float(data["geometry"]["span_m"])
    area = float(data["geometry"]["area_m2"])
    denominator = 0.5 * comparator.RHO * comparator.V**2 * area * b**2 / (2.0 * comparator.V)
    return (moment(h) - moment(-h)) / (2.0 * h) / denominator


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="new report path; existing files are never overwritten")
    args = parser.parse_args()
    if args.output is not None and args.output.exists():
        raise SystemExit(f"refusing to overwrite existing report: {args.output}")

    comparator = _load_comparator()
    data, ys, e, a0, _, _, _ = comparator._setup()
    raw = json.loads(AIRCRAFT.read_text(encoding="utf-8"))
    cg_x, inventory_mass = _cg_x_from_inventory(raw)
    arp_x = float(raw["reference"]["aero_reference_point"]["value"][0])
    arm_x = cg_x - arp_x  # Aero._arm(): body x = -(ARP_LE.x - CG_LE.x)
    alpha_deg = 11.0
    alpha = math.radians(alpha_deg)
    h = comparator.H
    _, _, full_plus, side_plus = _flows(alpha, h, ys, arm_x)
    _, _, full_minus, side_minus = _flows(alpha, -h, ys, arm_x)
    plane_max_plus = max(_flows(alpha, h, ys, arm_x)[0][2])
    plane_max_minus = max(_flows(alpha, -h, ys, arm_x)[0][2])
    full_excess = [
        max(full_plus) - plane_max_plus,
        max(full_minus) - plane_max_minus,
    ]
    weight_gaps = []
    for rate in (h, -h):
        plane_flow, full_flow, _, _ = _flows(alpha, rate, ys, arm_x)
        weight_gaps.extend(
            abs(plane_flow[4][i] - full_flow[4][i]) for i in range(len(ys))
        )

    cnr_plane = _cnr_for(comparator, data, ys, e, a0, alpha, arm_x, False)
    cnr_full = _cnr_for(comparator, data, ys, e, a0, alpha, arm_x, True)
    report = {
        "schema": "r02-yaw-fullspeed-normalization-probe/v1",
        "interpretation": "Read-only numerical comparison of the standalone max-Vp approximation against Aero._wing_flow's max full-speed source normalization; this is a tiny reproducer-fidelity check, not a force-law or physical validation.",
        "identity": {
            "comparator_sha256": hashlib.sha256(COMPARATOR.read_bytes()).hexdigest(),
            "input_export_sha256": hashlib.sha256(INPUT_EXPORT.read_bytes()).hexdigest(),
            "aircraft_sha256": hashlib.sha256(AIRCRAFT.read_bytes()).hexdigest(),
            "aero_source_sha256": hashlib.sha256(AERO_SOURCE.read_bytes()).hexdigest(),
        },
        "condition": {
            "alpha_deg": alpha_deg,
            "speed_mps": comparator.V,
            "density_kg_m3": comparator.RHO,
            "yaw_rate_rad_s": [h, -h],
            "station_y_m": ys,
            "inventory_mass_kg": inventory_mass,
            "arp_x_le_m": arp_x,
            "cg_x_le_m": cg_x,
            "body_arm_x_m": arm_x,
        },
        "rates": [
            {
                "yaw_rate_rad_s": rate,
                "side_velocity_f1_mps": side,
                "max_plane_speed_mps": plane_max,
                "max_full_speed_mps": max(full),
                "full_minus_plane_max_speed_mps": max(full) - plane_max,
            }
            for rate, side, plane_max, full in (
                (h, side_plus, plane_max_plus, full_plus),
                (-h, side_minus, plane_max_minus, full_minus),
            )
        ],
        "max_abs_source_weight_difference": max(weight_gaps),
        "wing_Cnr": {
            "standalone_max_plane_speed": cnr_plane,
            "production_max_full_speed": cnr_full,
            "full_minus_plane": cnr_full - cnr_plane,
        },
    }
    encoded = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")


if __name__ == "__main__":
    main()
