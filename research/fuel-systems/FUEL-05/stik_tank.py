"""FUEL-05f: the base Jensen Ugly Stik declares its tank and is balanced with the tank empty.

The base Stik is authored data without a generator; this script is the reproducible edit (run --check in review):
- fuel_system: one 350 cc tank (O.S. 40-91FX manual, the Stik's MAX-61FX), registry glow blend, clunk, muffler feed;
- liquid: a fixed half tank (prescribed fuel: no burn) = 0.35 l x registry density x 0.5, a box holding the capacity,
  at the FX manual's height (tank top 7.5 mm above the needle; the carburetor estimate is NITRO-05's 2T value);
- balance: the Jensen plan CG arrow is taken with the tank empty (D3); the D1-R1 virtual balancing mass at
  x = 0.85 m is recomputed for the dry inventory, so the flown half-tank CG moves forward.
The tank shell stays the base hardware record (economics BOM). Every other value is untouched.

Usage: python3 -I research/fuel-systems/FUEL-05/stik_tank.py [--check]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "research/fuel-systems"))
import fuel_registry  # noqa: E402

PATH = ROOT / "app/data/aircraft/jensen_ugly_stik_60.json"
BLEND = "glow_10n_18castor"
CAPACITY_L = 0.35
FIXED_FILL = 0.5
CAPACITY_SOURCE = ('O.S. 40-91FX manual (os-engines.co.jp 50sx_40-91fx.pdf): 61FX "approx 350cc", '
                   '"12-13 minute flights"')
LIQUID_BOX = [0.115, 0.065, 0.047]
CARBURETOR_Z = 0.02  # NITRO-05 2T estimate (research/glow-engines/build_installations.py fuel_feed)
TANK_Z = CARBURETOR_Z + 0.0075 - LIQUID_BOX[2] / 2
BALLAST_X = 0.85  # D1-R1 virtual balancing station inside the aft fuselage
TAG = "FUEL-05f"


def q(value, unit, kind, source):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def left_to_right_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def apply(raw):
    inv = raw["inventory"]
    by_id = {item["id"]: item for item in inv}
    fuel = by_id["item_fuel_main"]
    ballast = by_id["item_balance_mass_virtual"]
    density = fuel_registry.blend_density(BLEND)
    fuel["mass"] = q(CAPACITY_L * 1e-3 * density * FIXED_FILL, "kg", "derived",
                     "%s: fixed half of the %s l tank (prescribed fuel, no burn) x %s"
                     % (TAG, CAPACITY_L, fuel_registry.blend_source(BLEND)))
    fuel["position"] = q([-0.1, 0.0, TANK_Z], "m", "estimated",
                         "%s: plan fuel-tank compartment F1-F2 (x); FX manual height: tank top 5-10 mm above the "
                         "needle (7.5 mm used) with the NITRO-05 2T carburetor estimate" % TAG)
    fuel["size"] = q(LIQUID_BOX, "m", "estimated",
                     "%s: uniform liquid box holding the %s l capacity; no measured tank interior" % (TAG, CAPACITY_L))
    plan = raw["balance"]["plan_cg"]["value"]
    parts = [item for item in inv if item is not ballast and item is not fuel]
    mass = left_to_right_sum(i["mass"]["value"] for i in parts)
    first = [left_to_right_sum(i["mass"]["value"] * i["position"]["value"][k] for i in parts) for k in range(3)]
    m_b = (mass * plan[0] - first[0]) / (BALLAST_X - plan[0])
    ballast["mass"]["value"] = m_b
    ballast["position"]["value"] = [BALLAST_X, ((mass + m_b) * plan[1] - first[1]) / m_b,
                                    ((mass + m_b) * plan[2] - first[2]) / m_b]
    for key in ("mass", "position"):
        if TAG not in ballast[key]["source"]:
            ballast[key]["source"] += "; %s: recomputed for the empty-tank (dry) inventory" % TAG
    balance = raw["balance"]
    if TAG not in balance["plan_cg"]["source"]:
        balance["plan_cg"]["source"] += "; %s: taken with the tank empty, as RC manuals balance" % TAG
    balance["configuration"] = "virtual-balanced-reference-v2-empty-tank"
    balance["fuel_state"] = "empty_tanks"
    system = {"tanks": [{
        "id": "main_tank", "fuel": BLEND, "liquid_inventory_id": "item_fuel_main", "shell_inventory_id": "item_fuel_tank",
        "capacity": q(CAPACITY_L, "l", "manual", CAPACITY_SOURCE),
        "unusable": q(0.005, "l", "estimated", "%s: clunk residue estimate; no published value "
                      "(docs/research/fuel-systems/FUEL-00 section 6.3)" % TAG),
        "pickup": "clunk", "feed": "suction_muffler"}]}
    out = {}
    for key, value in raw.items():
        if key == "fuel_system":
            continue
        out[key] = value
        if key == "inventory":
            out["fuel_system"] = system
    return out


def render(raw):
    return (json.dumps(raw, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    current = PATH.read_bytes()
    rendered = render(apply(json.loads(current.decode("utf-8"))))
    if rendered == current:
        print("base Stik tank current")
    elif args.check:
        sys.exit("stale: " + str(PATH.relative_to(ROOT)))
    else:
        PATH.write_bytes(rendered)
        print("wrote " + str(PATH.relative_to(ROOT)))


if __name__ == "__main__":
    main()
