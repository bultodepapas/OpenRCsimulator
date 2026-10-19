#!/usr/bin/env python3
"""Independent P51-15 mass-property oracle for the generated inventory."""

import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PHYSICS = ROOT / "app/data/aircraft/p51d_mustang_120.json"
GEOMETRY = ROOT / "assets/aircraft/p51d-mustang-120/geometry.json"

# Merged-pair (pre-P51-15 representation) tensor of the current build. First computed from the committed
# inventory at df36b44 as (3.412230, 6.817989, 9.496622, 0.0, -0.269807, 0.0); re-based at FUEL-05c (1 l tank as
# a sized liquid box, registry gasoline density, empty-tank rebalance of the virtual mass and airframe scale) as
# the runtime tensor minus the analytic pair delta below. Any later unexplained inventory change still fails.
BASELINE_J = (3.382046, 6.836389, 9.487422, 0.0, -0.259573, 0.0)
PAIR_MASS = {
    "aileron servo": 0.16,
    "flap servo": 0.16,
    "elevator servo": 0.16,
    "main gear assembly": 2.0,
}
PAIR_XZ = {
    "aileron servo": (0.12, -0.1682),
    "flap servo": (0.30, -0.1682),
    "elevator servo": (1.2328, 0.0875),
    "main gear assembly": (0.025, -0.2965),
}
PAIR_OLD_SPAN = {
    "aileron servo": 1.9,
    "flap servo": 0.8,
    "elevator servo": 0.30,
    "main gear assembly": None,  # read the authored track from geometry.json
}
PAIR_NEW_LOCAL_WIDTH = {
    "aileron servo": 0.02,
    "flap servo": 0.02,
    "elevator servo": 0.02,
    "main gear assembly": 0.10,
}


def close(actual: float, expected: float, tolerance: float, label: str) -> None:
    if not math.isfinite(actual) or abs(actual - expected) > tolerance:
        raise AssertionError(f"{label}: got {actual:.9g}, expected {expected:.9g} ± {tolerance:g}")


def inertia_tensor(parts: list[dict], cg: list[float]) -> tuple[float, ...]:
    """Box inertia plus parallel-axis terms, in the runtime's body FRD axes."""
    result = [0.0] * 6
    for part in parts:
        mass = part["mass"]["value"]
        position = part["position"]["value"]
        size = part["size"]["value"]
        x = -(position[0] - cg[0])  # le-frame aft -> body forward
        y = position[1] - cg[1]
        z = -(position[2] - cg[2])  # le-frame up -> body down
        result[0] += mass * (y * y + z * z) + mass * (size[1] ** 2 + size[2] ** 2) / 12.0
        result[1] += mass * (x * x + z * z) + mass * (size[0] ** 2 + size[2] ** 2) / 12.0
        result[2] += mass * (x * x + y * y) + mass * (size[0] ** 2 + size[1] ** 2) / 12.0
        result[3] -= mass * x * y
        result[4] -= mass * x * z
        result[5] -= mass * y * z
    return tuple(result)


def main() -> None:
    model = json.loads(PHYSICS.read_text(encoding="utf-8"))
    geometry = json.loads(GEOMETRY.read_text(encoding="utf-8"))
    parts = model["inventory"]
    mass = sum(part["mass"]["value"] for part in parts)
    cg = [
        sum(part["mass"]["value"] * part["position"]["value"][axis] for part in parts) / mass
        for axis in range(3)
    ]

    close(mass, 21.5, 1e-5, "inventory mass (kg)")
    # FUEL-05c: the plan CG is declared with the tank empty, so it is the CG of the inventory without tank liquid.
    liquid = set()
    if model["balance"].get("fuel_state") == "empty_tanks":
        liquid = {tank["liquid_inventory_id"] for tank in model["fuel_system"]["tanks"]}
    dry = [part for part in parts if part.get("id") not in liquid]
    dry_mass = sum(part["mass"]["value"] for part in dry)
    dry_cg = [sum(part["mass"]["value"] * part["position"]["value"][axis] for part in dry) / dry_mass for axis in range(3)]
    for axis, label in ((0, "x aft"), (2, "z up")):
        close(dry_cg[axis], model["balance"]["plan_cg"]["value"][axis], 1e-6, f"declared-state inventory CG {label} (m)")
    close(cg[1], 0.0, 1e-8, "symmetric inventory CG y (m)")

    wing = geometry["wing"]
    tail = geometry["tail"]
    gear = geometry["gear"]
    expected_half_spans = {
        "aileron servo": (wing["aileron_inner"] + wing["aileron_outer"]) / 2.0,
        "flap servo": (wing["flap_inner"] + wing["flap_outer"]) / 2.0,
        # Former paired box had a 0.30 m lateral extent; retain its inferred root pair centers.
        # The source says “in the stab roots”; this is not a measured mounting coordinate.
        "elevator servo": 0.15,
        "main gear assembly": gear["track"] / 2.0,
    }
    for prefix, pair_mass in PAIR_MASS.items():
        pair = [part for part in parts if part["name"].startswith(prefix)]
        if len(pair) != 2:
            raise AssertionError(f"{prefix}: expected two separate inventory entries, got {len(pair)}")
        pair.sort(key=lambda part: part["name"])
        close(sum(part["mass"]["value"] for part in pair), pair_mass, 1e-6, f"{prefix} pair mass (kg)")
        if any(part["mass"]["kind"] != "estimated" or part["position"]["kind"] != "estimated" for part in pair):
            raise AssertionError(f"{prefix}: pair mass and center estimates must remain labeled estimated")
        lateral = [part["position"]["value"][1] for part in pair]
        x_aft, z_up = PAIR_XZ[prefix]
        half_span = expected_half_spans[prefix]
        close(lateral[0], -half_span, 1e-6, f"{prefix} left pair position (m)")
        close(lateral[1], half_span, 1e-6, f"{prefix} right pair position (m)")
        for part in pair:
            close(part["position"]["value"][0], x_aft, 1e-6, f"{prefix} retained x aft (m)")
            close(part["position"]["value"][2], z_up, 1e-6, f"{prefix} retained z up (m)")
            close(part["size"]["value"][1], PAIR_NEW_LOCAL_WIDTH[prefix], 1e-6, f"{prefix} local lateral envelope (m)")

    tensor = inertia_tensor(parts, cg)
    delta = tuple(after - before for before, after in zip(BASELINE_J, tensor))
    # Independently predict the pair-only change from the authored merged boxes:
    # each pair contributes M * (new center² + local width²/12 - old box width²/12).
    expected_jxx_delta = 0.0
    for prefix, pair_mass in PAIR_MASS.items():
        old_span = PAIR_OLD_SPAN[prefix]
        if old_span is None:
            old_span = gear["track"]
        half_span = expected_half_spans[prefix]
        local_width = PAIR_NEW_LOCAL_WIDTH[prefix]
        expected_jxx_delta += pair_mass * (half_span**2 + local_width**2 / 12.0 - old_span**2 / 12.0)
    close(delta[0], expected_jxx_delta, 5e-5, "paired-mass analytic ΔJxx (kg·m²)")
    close(delta[1], 0.0, 5e-5, "paired-mass ΔJyy (kg·m²)")
    close(delta[2], expected_jxx_delta, 5e-5, "paired-mass analytic ΔJzz (kg·m²)")
    close(delta[3], 0.0, 5e-5, "paired-mass ΔJxy (kg·m²)")
    close(delta[4], 0.0, 5e-5, "paired-mass ΔJxz (kg·m²)")
    close(delta[5], 0.0, 5e-5, "paired-mass ΔJyz (kg·m²)")
    expected_tensor = list(BASELINE_J)
    expected_tensor[0] += expected_jxx_delta
    expected_tensor[2] += expected_jxx_delta
    for index, (actual, expected) in enumerate(zip(tensor, expected_tensor)):
        close(actual, expected, 5e-5, f"runtime-order tensor J[{index}]")

    jxx, jyy, jzz, jxy, jxz, jyz = tensor
    determinant = jxx * (jyy * jzz - jyz * jyz) - jxy * (jxy * jzz - jyz * jxz) + jxz * (jxy * jyz - jyy * jxz)
    if jxx <= 0.0 or jxx * jyy - jxy * jxy <= 0.0 or determinant <= 0.0:
        raise AssertionError("inertia tensor is not positive definite")
    if abs(jxy) > 1e-8 or abs(jyz) > 1e-8:
        raise AssertionError("symmetric inventory should have no xy or yz products of inertia")
    root = math.sqrt((jxx - jzz) ** 2 + 4.0 * jxz**2)
    principal = sorted((0.5 * (jxx + jzz - root), jyy, 0.5 * (jxx + jzz + root)))
    if principal[0] <= 0.0 or principal[2] > principal[0] + principal[1]:
        raise AssertionError("inertia tensor violates a principal-moment triangle inequality")

    # Guard against changing tuned flight coefficients while editing the inventory model.
    sentinels = (
        (model["aero"]["coefficients"]["CLa"]["value"], 4.337736, "CLa"),
        (model["aero"]["coefficients"]["Cma"]["value"], -0.895896, "Cma"),
        # P51-11b: CD0 is gear up; the gear-down drag area moved to landing_gear.retraction (was 0.044672 with the gear).
        (model["aero"]["coefficients"]["CD0"]["value"], 0.028643, "CD0"),
        (model["aero"]["envelope"]["CL_max"]["value"], 1.021297, "CL_max"),
        (model["aero"]["coefficients"]["k_induced"]["value"], 0.073249, "k_induced"),
        (model["propulsion"]["propeller"]["diameter"]["value"], 0.6604, "propeller diameter"),
        # P51-25 adds a flight-calibrated body term; the vertical-fin part must stay unchanged.
        (model["aero"]["coefficients"]["Cnb"]["value"] - model["aero"]["surfaces"].get("body_cn_beta", {}).get("value", 0.0), 0.1394867577485912, "Cnb fin part"),
    )
    for actual, expected, label in sentinels:
        close(actual, expected, 1e-6, f"unchanged physics sentinel {label}")
    for axis, expected in zip(model["propulsion"]["propeller"]["thrust_angles"]["value"], (1.75, 1.0)):
        close(axis, expected, 1e-6, "unchanged thrust angle (deg)")

    print(
        "P51-15 inventory oracle PASS: mass %.6f kg, CG [%+.6f, %+.6f] m, "
        "Jxx %.6f / Jyy %.6f / Jzz %.6f kg·m² (ΔJxx/ΔJzz +%.6f)"
        % (mass, cg[0], cg[2], jxx, jyy, jzz, delta[0])
    )


if __name__ == "__main__":
    main()
