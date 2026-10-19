"""FUEL-01e/FUEL-05-R1: report fixed-wing mass and balance across the data fleet.

Usage:
  python3 -I research/fuel-systems/mass_balance_report.py
  python3 -I research/fuel-systems/mass_balance_report.py --write PATH
  python3 -I research/fuel-systems/mass_balance_report.py --check PATH
  python3 -I research/fuel-systems/mass_balance_report.py --check PATH --fail-on-drift
  python3 -I research/fuel-systems/mass_balance_report.py --qualify

The report walks app/data/aircraft recursively. It includes every airplane openrc-aircraft v2 data
configuration with inventory, reference and balance fields, plus verifies that each airplane data file
referenced by the aircraft catalog is included. Catalog battery_data modes and non-catalog data variants
are listed separately. Rotorcraft are outside this airplane report.

The declared state uses inventory as authored. Empty removes liquid-fuel items. Full sets each declared
tank liquid to capacity times the registry density. The plan CG comparison uses the state named by
balance.fuel_state (empty_tanks -> empty; as_inventory -> declared); optional CG range checks the authored
plan_cg at that state, matching AircraftData. Static-margin neutral points are estimates, not measurements.
Missing neutral points remain visible in ordinary reports and fail only explicit --qualify runs.

--check preserves its existing status behavior: mass/balance or catalog-coverage failures return nonzero,
but data drift is advisory unless --fail-on-drift is also supplied. This is a read-only independent oracle,
not a runtime call or physical measurement.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fuel_registry  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AIRCRAFT_DIR = ROOT / "app" / "data" / "aircraft"
CATALOG = ROOT / "app" / "app_state" / "aircraft_catalog.gd"
REGISTER = ROOT / "research" / "fuel-systems" / "neutral_points.json"
FORMAT = "openrc-mass-balance-report v2"
LIQUID_FUELS = ("glow_fuel", "gasoline", "kerosene")
ELECTRIC_ENERGY = ("fixed_voltage", "ocv_resistance", "pack_ecm")
CATALOG_ENTRY = re.compile(r"(?ms)^\t\{\r?\n(?P<body>.*?)(?=^\t\},)")
CATALOG_ID = re.compile(r'(?m)^\s*id\s*=\s*"([^"]+)"')
CATALOG_VEHICLE = re.compile(r'(?m)^\s*vehicle\s*=\s*"([^"]+)"')
CATALOG_DATA = re.compile(
    r'(?m)^\s*(?:data|battery_data)\s*=\s*"res://data/aircraft/([^"]+\.json)"'
)


def value(quantity: Any) -> Any:
    return quantity["value"] if isinstance(quantity, dict) else quantity


def mean_aerodynamic_chord(reference: dict) -> float:
    if (
        value(reference.get("planform")) == "tapered"
        and "root_chord" in reference
        and "tip_chord" in reference
    ):
        root, tip = value(reference["root_chord"]), value(reference["tip_chord"])
        taper = tip / root
        return 2.0 / 3.0 * root * (1.0 + taper + taper * taper) / (1.0 + taper)
    return value(reference["mean_chord"])


def mass_and_cg(items: list[dict]) -> tuple[float, list[float]]:
    mass = 0.0
    first = [0.0, 0.0, 0.0]
    for item in items:  # preserve the loader's left-to-right reduction order
        item_mass = value(item["mass"])
        mass += item_mass
        for axis in range(3):
            first[axis] += item_mass * value(item["position"])[axis]
    if mass <= 0.0:
        raise ValueError("inventory state has no positive mass")
    return mass, [first[axis] / mass for axis in range(3)]


def neutral_points() -> dict[str, dict]:
    register = json.loads(REGISTER.read_text(encoding="utf-8"))
    out = {}
    for key, entry in register["aircraft"].items():
        for aircraft_id in entry.get("applies_to", [key]):
            out[aircraft_id] = {
                "np_x_m": entry["np_x_m"],
                "kind": entry.get("kind"),
                "register_key": key,
            }
    return out


def catalog_aircraft_files() -> dict[str, list[str]]:
    """Map each catalog airplane's data path (including battery_data) to its catalog ID."""
    source = CATALOG.read_text(encoding="utf-8")
    out: dict[str, list[str]] = {}
    for match in CATALOG_ENTRY.finditer(source):
        body = match.group("body")
        id_match = CATALOG_ID.search(body)
        if not id_match:
            continue
        vehicle_match = CATALOG_VEHICLE.search(body)
        if vehicle_match and vehicle_match.group(1) == "rotorcraft":
            continue
        aircraft_id = id_match.group(1)
        for filename in CATALOG_DATA.findall(body):
            relative = Path(filename).as_posix()
            out.setdefault(relative, []).append(aircraft_id)
    return out


def _relative_file(path: Path) -> str:
    return path.relative_to(AIRCRAFT_DIR).as_posix()


def _plan_cg_state(fuel_state: str, states: dict) -> str:
    if fuel_state == "empty_tanks":
        return "empty" if "empty" in states else "unknown"
    if fuel_state in ("as_inventory", ""):
        return "declared"
    return "unknown"


def _cg_range_check(balance: dict, plan_cg: list[float], plan_state: str) -> dict:
    range_data = balance.get("cg_range")
    result = {
        "status": "not_declared",
        "plan_state": plan_state,
        "plan_cg_x_m": round(plan_cg[0], 6),
    }
    if range_data is None:
        return result
    try:
        forward = float(value(range_data["forward"]))
        aft = float(value(range_data["aft"]))
    except (KeyError, TypeError, ValueError) as exc:
        return {**result, "status": "invalid", "error": str(exc)}
    if forward >= aft:
        return {**result, "status": "invalid", "forward_x_m": forward, "aft_x_m": aft}
    return {
        "status": "within" if forward <= plan_cg[0] <= aft else "outside",
        "plan_state": plan_state,
        "plan_cg_x_m": round(plan_cg[0], 6),
        "forward_x_m": round(forward, 6),
        "aft_x_m": round(aft, 6),
    }


def _inventory_row(
    path: Path, raw: dict, nps: dict[str, dict], catalog_ids: list[str]
) -> dict:
    capabilities = raw.get("capabilities")
    capabilities = capabilities if isinstance(capabilities, dict) else {}
    inventory = raw["inventory"]
    fuel = [item for item in inventory if item.get("energy_source") in LIQUID_FUELS]
    dry = [item for item in inventory if item.get("energy_source") not in LIQUID_FUELS]
    mac = mean_aerodynamic_chord(raw["reference"])
    balance = raw["balance"]
    plan = value(balance["plan_cg"])
    tolerance = value(balance.get("cg_tolerance", 0.0))
    fuel_state = balance.get("fuel_state", "as_inventory")
    states = {"declared": mass_and_cg(inventory)}
    if fuel:
        states["empty"] = mass_and_cg(dry)

    tanks = raw.get("fuel_system", {}).get("tanks", [])
    if tanks:
        capacity_kg = {
            tank["liquid_inventory_id"]: value(tank["capacity"])
            * 1.0e-3
            * fuel_registry.blend_density(tank["fuel"])
            for tank in tanks
        }
        full = [
            dict(item, mass={"value": capacity_kg[item["id"]]})
            if item.get("id") in capacity_kg
            else item
            for item in inventory
        ]
        states["full"] = mass_and_cg(full)

    plan_state = _plan_cg_state(fuel_state, states)
    selected = states.get(plan_state)
    plan_matches = (
        all(abs(selected[1][axis] - plan[axis]) <= tolerance + 1e-12 for axis in range(3))
        if selected is not None
        else None
    )
    range_check = _cg_range_check(balance, plan, plan_state)
    np_entry = nps.get(raw["id"])
    neutral_donors = [
        {
            "id": item.get("id"),
            "mass_kg": value(item["mass"]),
            "position_m": value(item["position"]),
        }
        for item in inventory
        if item.get("name", "").lower().startswith("donor mass")
    ]
    missing_donor_ids = sum(1 for item in neutral_donors if not item["id"])
    missing_inventory_ids = sum(1 for item in inventory if not item.get("id"))
    flags = []
    if any(not any(value(item.get("size", {"value": [0, 0, 0]}))) for item in fuel):
        flags.append("point_mass_fuel")
    if capabilities.get("energy") in ELECTRIC_ENERGY and any(
        "fuel" in item.get("name", "").lower()
        and not item.get("name", "").lower().startswith("donor mass")
        for item in inventory
    ):
        flags.append("fuel_named_items_on_electric_aircraft")
    if missing_donor_ids:
        flags.append("neutral_donor_missing_id:%d" % missing_donor_ids)
    if missing_inventory_ids and raw.get("physical_identity_version") == 1:
        flags.append("physical_identity_missing_inventory_id:%d" % missing_inventory_ids)
    if np_entry is None:
        flags.append("missing_neutral_point")
    if range_check["status"] == "not_declared":
        flags.append("cg_range_not_declared")
    if range_check["status"] in ("invalid", "outside"):
        flags.append("cg_range_" + range_check["status"])
    if plan_state == "unknown":
        flags.append("unsupported_balance_fuel_state:" + str(fuel_state))
    if plan_matches is False:
        flags.append("plan_cg_mismatch:" + plan_state)

    row = {
        "id": raw["id"],
        "file": _relative_file(path),
        "energy": capabilities.get("energy"),
        "catalog_ids": sorted(catalog_ids),
        "variant_kind": "catalog" if catalog_ids else "data_variant",
        "mac_m": round(mac, 6),
        "plan_cg_m": [round(component, 6) for component in plan],
        "plan_cg_state": plan_state,
        "plan_cg_matches_inventory": plan_matches,
        "cg_tolerance_m": round(tolerance, 6),
        "cg_range_check": range_check,
        "balance_fuel_state": fuel_state,
        "fuel_items": [
            {
                "id": item.get("id"),
                "energy_source": item["energy_source"],
                "mass_kg": value(item["mass"]),
                "position_m": value(item["position"]),
                "size_m": value(item.get("size", {"value": [0, 0, 0]})),
            }
            for item in fuel
        ],
        "neutral_donor_items": neutral_donors,
        "inventory_identity": {
            "physical_identity_version": raw.get("physical_identity_version"),
            "idless_inventory_items": missing_inventory_ids,
        },
        "neutral_point": (
            {
                "np_x_m": np_entry["np_x_m"],
                "kind": np_entry["kind"],
                "register_key": np_entry["register_key"],
            }
            if np_entry is not None
            else None
        ),
        "flags": flags,
        "states": {},
    }
    for state_name, (mass, cg) in states.items():
        state = {
            "mass_kg": round(mass, 6),
            "cg_m": [round(component, 6) for component in cg],
            "cg_shift_from_declared_mm": round(
                (cg[0] - states["declared"][1][0]) * 1000.0, 3
            ),
        }
        if np_entry is not None:
            state["static_margin_pct_mac"] = round(
                (np_entry["np_x_m"] - cg[0]) / mac * 100.0, 3
            )
        row["states"][state_name] = state
    return row


def aircraft_rows() -> list[dict]:
    nps = neutral_points()
    catalog_files = catalog_aircraft_files()
    rows = []
    for path in sorted(
        AIRCRAFT_DIR.rglob("*.json"),
        key=lambda item: item.relative_to(AIRCRAFT_DIR).as_posix(),
    ):
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
        if (
            raw.get("format") != "openrc-aircraft v2"
            or raw.get("vehicle") == "rotorcraft"
            or not isinstance(raw.get("inventory"), list)
            or "reference" not in raw
            or "balance" not in raw
        ):
            continue
        relative = _relative_file(path)
        rows.append(
            _inventory_row(path, raw, nps, catalog_files.get(relative, []))
        )
    return rows


def coverage_report(rows: list[dict]) -> dict:
    catalog_files = catalog_aircraft_files()
    reported = {row["file"] for row in rows}
    expected = sorted(catalog_files)
    missing = sorted(set(expected) - reported)
    return {
        "catalog_aircraft_ids": sorted(
            {aircraft_id for ids in catalog_files.values() for aircraft_id in ids}
        ),
        "catalog_data_files": expected,
        "catalog_covered_files": sorted(set(expected) & reported),
        "catalog_missing_files": missing,
        "supported_data_variants": sorted(
            row["file"] for row in rows if not row["catalog_ids"]
        ),
        "reported_airplane_files": sorted(reported),
        "errors": [
            "catalog airplane data file is not reportable: " + filename
            for filename in missing
        ],
    }


def report() -> dict:
    rows = aircraft_rows()
    return {
        "format": FORMAT,
        "liquid_fuels": list(LIQUID_FUELS),
        "coverage": coverage_report(rows),
        "aircraft": rows,
    }


def markdown(data: dict) -> str:
    lines = [
        "| Aircraft data file | Catalog IDs | Energy | Plan state | Declared / empty / full mass kg | Range | SM declared / empty / full % MAC | Neutral point | Flags |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in data["aircraft"]:
        states = row["states"]
        masses = " / ".join(
            "%.3f" % states[name]["mass_kg"] if name in states else "n/a"
            for name in ("declared", "empty", "full")
        )
        margins = " / ".join(
            "%.1f" % states[name]["static_margin_pct_mac"]
            if name in states and "static_margin_pct_mac" in states[name]
            else "n/a"
            for name in ("declared", "empty", "full")
        )
        cg_range = row["cg_range_check"]["status"]
        neutral_point = (
            "%.4f m" % row["neutral_point"]["np_x_m"]
            if row["neutral_point"]
            else "missing"
        )
        lines.append(
            "| %s | %s | %s | %s | %s | %s | %s | %s | %s |"
            % (
                row["file"],
                ", ".join(row["catalog_ids"]) or "n/a",
                row["energy"] or "n/a",
                row["plan_cg_state"],
                masses,
                cg_range,
                margins,
                neutral_point,
                ", ".join(row["flags"]) or "n/a",
            )
        )
    coverage = data.get("coverage", {})
    lines.extend(
        [
            "",
            "Catalog airplane files: %d/%d covered; non-catalog data variants: %d."
            % (
                len(coverage.get("catalog_covered_files", [])),
                len(coverage.get("catalog_data_files", [])),
                len(coverage.get("supported_data_variants", [])),
            ),
        ]
    )
    return "\n".join(lines)


def failures(data: dict) -> list[str]:
    """Return ordinary report failures, preserving default check exit semantics."""
    out = []
    for error in data.get("coverage", {}).get("errors", []):
        out.append("coverage: " + error)
    for row in data.get("aircraft", []):
        label = row.get("file", row.get("id", "<unknown>"))
        if row.get("plan_cg_state") == "unknown":
            out.append("%s: unsupported balance fuel state" % label)
        if row.get("plan_cg_matches_inventory") is False:
            out.append("%s: plan CG does not match %s inventory" % (label, row["plan_cg_state"]))
        range_status = row.get("cg_range_check", {}).get("status")
        if range_status in ("outside", "invalid"):
            out.append("%s: declared plan CG range is %s" % (label, range_status))
        for name, state in row.get("states", {}).items():
            if (
                "static_margin_pct_mac" in state
                and state["static_margin_pct_mac"] <= 0.0
            ):
                out.append(
                    "%s: static margin %.3f %% MAC at %s fuel state"
                    % (label, state["static_margin_pct_mac"], name)
                )
    return out


def qualification_failures(data: dict) -> list[str]:
    """Extra opt-in checks that require a longitudinal neutral-point estimate."""
    out = []
    for row in data.get("aircraft", []):
        if row.get("neutral_point") is None:
            out.append(
                "%s: no neutral-point estimate for longitudinal qualification"
                % row.get("file", row.get("id", "<unknown>"))
            )
    return out


def drift(stored: dict, current: dict) -> list[str]:
    """Compare full report content by relative file, including coverage and plan interpretation."""
    out = []
    if stored.get("format") != current.get("format"):
        out.append("report format changed")
    for key in ("liquid_fuels", "coverage"):
        if stored.get(key) != current.get(key):
            out.append("%s changed" % key)
    before = {row["file"]: row for row in stored.get("aircraft", [])}
    after = {row["file"]: row for row in current.get("aircraft", [])}
    for name in sorted(set(before) ^ set(after)):
        out.append("%s: %s" % (name, "added" if name not in before else "removed"))
    for name in sorted(set(before) & set(after)):
        keys = set(before[name]) | set(after[name])
        for key in sorted(keys):
            if before[name].get(key) != after[name].get(key):
                out.append("%s: %s changed" % (name, key))
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--write", type=Path)
    group.add_argument("--check", type=Path)
    parser.add_argument(
        "--fail-on-drift",
        action="store_true",
        help="make --check return nonzero when the stored report differs",
    )
    parser.add_argument(
        "--qualify",
        action="store_true",
        help="also fail when any reported airplane lacks a neutral-point estimate",
    )
    args = parser.parse_args(argv)
    if args.fail_on_drift and not args.check:
        parser.error("--fail-on-drift requires --check")
    data = report()
    differences = []
    if args.write:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(
            json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8"
        )
        print("wrote %s (%d aircraft configurations)" % (args.write, len(data["aircraft"])))
    elif args.check:
        stored = json.loads(args.check.read_text(encoding="utf-8"))
        differences = drift(stored, data)
        for line in differences:
            prefix = "FAIL DRIFT " if args.fail_on_drift else "DRIFT "
            print(prefix + line, file=sys.stderr if args.fail_on_drift else sys.stdout)
        if differences and not args.fail_on_drift:
            print("review report differences; regenerate with --write when intended")
    else:
        print(markdown(data))

    bad = failures(data)
    for line in bad:
        print("FAIL " + line, file=sys.stderr)
    qualification_bad = qualification_failures(data) if args.qualify else []
    for line in qualification_bad:
        print("QUALIFICATION FAIL " + line, file=sys.stderr)
    if args.check and not bad:
        coverage = data["coverage"]
        print(
            "mass/balance: %d airplane configurations, catalog files %d/%d covered, %d data variants; every registered static margin positive"
            % (
                len(data["aircraft"]),
                len(coverage["catalog_covered_files"]),
                len(coverage["catalog_data_files"]),
                len(coverage["supported_data_variants"]),
            )
        )
    return 1 if bad or qualification_bad or (args.fail_on_drift and differences) else 0


if __name__ == "__main__":
    sys.exit(main())
