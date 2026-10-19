"""FUEL-01e: mass and balance of every fixed-wing aircraft at its declared and empty-fuel states.

Usage:
  python3 -I research/fuel-systems/mass_balance_report.py                 # markdown table
  python3 -I research/fuel-systems/mass_balance_report.py --write PATH    # write the JSON report
  python3 -I research/fuel-systems/mass_balance_report.py --check PATH    # recompute and compare

Reads app/data/aircraft/*.json (openrc-aircraft v2 with an inventory) and the neutral-point register
research/fuel-systems/neutral_points.json. Liquid fuel is any inventory item whose energy_source is a
liquid fuel; "empty" removes those items and nothing else. "full" sets each declared fuel_system tank's
liquid to its capacity x registry density (FUEL-03); aircraft without fuel_system report no full state.

--check fails only when an aircraft with a registered neutral point has a static margin <= 0 at any
reported state, or when the data cannot be read. Differences from the stored report are printed as
DRIFT for review but do not fail: other tracks change aircraft data legitimately.
Mirrors the loader's inventory arithmetic; it is not a runtime call and not a physical measurement.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuel_registry  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT_DIR = ROOT / "app" / "data" / "aircraft"
REGISTER = ROOT / "research" / "fuel-systems" / "neutral_points.json"
FORMAT = "openrc-mass-balance-report v1"
LIQUID_FUELS = ("glow_fuel", "gasoline", "kerosene")
ELECTRIC_ENERGY = ("fixed_voltage", "ocv_resistance", "pack_ecm")


def value(quantity):
    return quantity["value"] if isinstance(quantity, dict) else quantity


def mean_aerodynamic_chord(reference: dict) -> float:
    if value(reference.get("planform")) == "tapered" and "root_chord" in reference and "tip_chord" in reference:
        root, tip = value(reference["root_chord"]), value(reference["tip_chord"])
        taper = tip / root
        return 2.0 / 3.0 * root * (1.0 + taper + taper * taper) / (1.0 + taper)
    return value(reference["mean_chord"])


def mass_and_cg(items: list[dict]) -> tuple[float, list[float]]:
    mass = 0.0
    first = [0.0, 0.0, 0.0]
    for item in items:  # left to right, like the loader
        m = value(item["mass"])
        mass += m
        for k in range(3):
            first[k] += m * value(item["position"])[k]
    return mass, [first[k] / mass for k in range(3)]


def neutral_points() -> dict[str, dict]:
    register = json.loads(REGISTER.read_text(encoding="utf-8"))
    out = {}
    for key, entry in register["aircraft"].items():
        for aircraft_id in entry.get("applies_to", [key]):
            out[aircraft_id] = {"np_x_m": entry["np_x_m"], "register_key": key}
    return out


def aircraft_rows() -> list[dict]:
    nps = neutral_points()
    rows = []
    for path in sorted(AIRCRAFT_DIR.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
        if raw.get("format") != "openrc-aircraft v2" or not isinstance(raw.get("inventory"), list):
            continue
        capabilities = raw.get("capabilities") if isinstance(raw.get("capabilities"), dict) else {}
        if "reference" not in raw or "balance" not in raw:
            continue
        inventory = raw["inventory"]
        fuel = [i for i in inventory if i.get("energy_source") in LIQUID_FUELS]
        dry = [i for i in inventory if i.get("energy_source") not in LIQUID_FUELS]
        mac = mean_aerodynamic_chord(raw["reference"])
        plan = value(raw["balance"]["plan_cg"])
        tolerance = value(raw["balance"].get("cg_tolerance", 0.0))
        states = {"declared": mass_and_cg(inventory)}
        if fuel:
            states["empty"] = mass_and_cg(dry)
        # FUEL-03: a declared fuel_system gives each tank's capacity, so the full state is known.
        tanks = raw.get("fuel_system", {}).get("tanks", [])
        if tanks:
            capacity_kg = {t["liquid_inventory_id"]: value(t["capacity"]) * 1e-3 * fuel_registry.blend_density(t["fuel"])
                           for t in tanks}
            full = [dict(i, mass={"value": capacity_kg[i.get("id")]}) if i.get("id") in capacity_kg else i
                    for i in inventory]
            states["full"] = mass_and_cg(full)
        np_entry = nps.get(raw["id"])
        row = {
            "id": raw["id"],
            "file": path.name,
            "energy": capabilities.get("energy"),
            "mac_m": round(mac, 6),
            "plan_cg_m": [round(v, 6) for v in plan],
            "plan_cg_matches_inventory": all(abs(states["declared"][1][k] - plan[k]) <= tolerance + 1e-12 for k in range(3)),
            "fuel_items": [{"id": i.get("id"), "energy_source": i["energy_source"], "mass_kg": value(i["mass"]),
                            "position_m": value(i["position"]), "size_m": value(i.get("size", {"value": [0, 0, 0]}))}
                           for i in fuel],
            "flags": [],
            "balance_fuel_state": raw["balance"].get("fuel_state", "as_inventory"),
            "states": {},
        }
        for i in fuel:
            if not any(value(i.get("size", {"value": [0, 0, 0]}))):
                row["flags"].append("point_mass_fuel:" + str(i.get("id")))
        missing = sum(1 for i in inventory if not i.get("id"))
        if missing:
            row["flags"].append("missing_id:%d_items" % missing)
        if capabilities.get("energy") in ELECTRIC_ENERGY and any("fuel" in i.get("name", "").lower() and not i.get("name", "").startswith("donor mass") for i in inventory):
            row["flags"].append("fuel_named_items_on_electric_aircraft")
        for name, (mass, cg) in states.items():
            state = {"mass_kg": round(mass, 6), "cg_m": [round(v, 6) for v in cg],
                     "cg_shift_from_declared_mm": round((cg[0] - states["declared"][1][0]) * 1000.0, 3)}
            if np_entry is not None:
                state["static_margin_pct_mac"] = round((np_entry["np_x_m"] - cg[0]) / mac * 100.0, 3)
            row["states"][name] = state
        if np_entry is not None:
            row["neutral_point"] = {"np_x_m": np_entry["np_x_m"], "register_key": np_entry["register_key"]}
        rows.append(row)
    return rows


def report() -> dict:
    return {"format": FORMAT, "liquid_fuels": list(LIQUID_FUELS), "aircraft": aircraft_rows()}


def markdown(data: dict) -> str:
    lines = ["| Aircraft file | Energy | Fuel kg | Mass decl. / empty kg | CG shift to empty mm | SM decl. / empty % MAC | Flags |",
             "| --- | --- | ---: | --- | ---: | --- | --- |"]
    for row in data["aircraft"]:
        fuel = sum(i["mass_kg"] for i in row["fuel_items"])
        decl, empty = row["states"]["declared"], row["states"].get("empty")
        mass = "%.3f / %s" % (decl["mass_kg"], "%.3f" % empty["mass_kg"] if empty else "—")
        shift = "%.1f" % empty["cg_shift_from_declared_mm"] if empty else "—"
        if "static_margin_pct_mac" in decl:
            sm = "%.1f / %s" % (decl["static_margin_pct_mac"], "%.1f" % empty["static_margin_pct_mac"] if empty else "—")
        else:
            sm = "no NP registered"
        lines.append("| %s | %s | %.3f | %s | %s | %s | %s |" % (row["file"], row["energy"], fuel, mass, shift, sm,
                                                               ", ".join(row["flags"]) or "—"))
    return "\n".join(lines)


def failures(data: dict) -> list[str]:
    out = []
    for row in data["aircraft"]:
        for name, state in row["states"].items():
            if "static_margin_pct_mac" in state and state["static_margin_pct_mac"] <= 0.0:
                out.append("%s: static margin %.3f %% MAC at %s fuel state" % (row["file"], state["static_margin_pct_mac"], name))
    return out


def drift(stored: dict, current: dict) -> list[str]:
    # Keyed by file: generated APC variants deliberately share their base aircraft id.
    before = {row["file"]: row for row in stored.get("aircraft", [])}
    after = {row["file"]: row for row in current["aircraft"]}
    out = ["%s: %s" % (name, "added" if name not in before else "removed")
           for name in sorted(set(before) ^ set(after))]
    for name in sorted(set(before) & set(after)):
        # Compare the physical content only, so report metadata can grow without a false drift.
        for key in ("states", "fuel_items"):
            if before[name].get(key) != after[name].get(key):
                out.append("%s: %s changed" % (name, key))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", type=Path)
    group.add_argument("--check", type=Path)
    args = parser.parse_args()
    data = report()
    if args.write:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print("wrote %s (%d aircraft)" % (args.write, len(data["aircraft"])))
    elif args.check:
        for line in drift(json.loads(args.check.read_text(encoding="utf-8")), data):
            print("DRIFT " + line + " (review; regenerate the report with --write when intended)")
    else:
        print(markdown(data))
    bad = failures(data)
    for line in bad:
        print("FAIL " + line, file=sys.stderr)
    if args.check and not bad:
        print("mass/balance: %d aircraft, every registered static margin positive" % len(data["aircraft"]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
