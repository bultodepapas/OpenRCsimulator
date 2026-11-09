#!/usr/bin/env python3
"""Generate the experimental Stik's matching ideal and finite-pack aircraft.

Use --draft-dir outside app for admission work; --check compares the published bytes.
This is a source-derived numerical candidate, not a qualified physical conversion.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "research/aircraft-standardization"))
from physical_identity import validate_physical_identity

SOURCE = HERE / "installation.json"
IDEAL = ROOT / "app/data/aircraft/stik_electric_6s.json"
PACK_VARIANT = ROOT / "app/data/aircraft/battery/stik_electric_6s_pack.json"
SCRIPT = "research/propulsion/stik-6s/build_aircraft.py"
EST = "EL1e-STIK-03a: "


def q(value, unit, kind, source):
    return {"value": value, "unit": unit, "kind": kind, "source": source}


def sum_left(values):
    value = 0.0
    for item in values:
        value += item
    return value


def cg(items):
    mass = sum_left(row["mass"]["value"] for row in items)
    return [sum_left(row["mass"]["value"] * row["position"]["value"][k] for row in items) / mass
            for k in range(3)]


def fitted_motor(source):
    # Under the explicit assumption that the chart's listed voltage is the ideal
    # motor command, fit two loaded points. Unknown ESC/lead drop biases the fit.
    (v1, i1, n1), (v2, i2, n2) = source["motor"]["loaded_fit_points"]
    determinant = n1 * i2 - n2 * i1
    inv_kv = (v1 * i2 - v2 * i1) / determinant
    resistance = (n1 * v2 - n2 * v1) / determinant
    return 1.0 / inv_kv, resistance


def record(item_id, name, mass, position, size, source, kind="estimated", energy=None):
    row = {"id": item_id, "name": name, "mass": q(mass, "kg", kind, source),
           "position": q(position, "m", "estimated", EST + "unbuilt installation location; fit unverified"),
           "size": q(size, "m", kind, source)}
    if energy:
        row["energy_source"] = energy
    return row


def aircraft(source, pack, pack_bytes):
    raw = json.loads((ROOT / source["airframe_source"]).read_text(encoding="utf-8"))
    donor_cg = cg(raw["inventory"])
    offset = raw["propulsion"]["propeller"]["thrust_line_offset"]["value"]
    hub = [donor_cg[k] + offset[k] for k in range(3)]
    removed = {"item_engine_main", "item_muffler_main", "item_propeller_main", "item_engine_mount",
               "item_fuel_tank", "item_fuel_main", "item_receiver_battery", "item_balance_mass_virtual"}
    if {row["id"] for row in raw["inventory"]} & removed != removed:
        raise ValueError("donor installation identity changed")
    inventory = [row for row in raw["inventory"] if row["id"] not in removed]
    servos = next(item for item in inventory if item["id"] == "item_fuselage_servos")
    servos["name"] = "elevator and rudder servos (2)"
    servos["mass"] = q(servos["mass"]["value"] * 2.0 / 3.0, "kg", "derived",
                       EST + "two of the donor's three equal estimated fuselage servos; electric throttle uses ESC")
    motor, prop, esc = source["motor"], source["propeller"], source["esc"]
    inventory.append(record("item_motor_main", motor["name"], motor["mass_kg"], motor["position_m"],
                            motor["size_m"], motor["manufacturer_url"], "manual"))
    prop_item = record("item_propeller_main", prop["name"], prop["mass_kg"], prop["position_m"],
                       prop["size_m"], prop["product_url"] + ": 0.92 oz; dimensions other than diameter estimated", "manual")
    prop_item["size"]["kind"] = "estimated"
    inventory.append(prop_item)
    inventory.append(record("item_esc_main", esc["name"], esc["mass_kg"], esc["position_m"], esc["size_m"], esc["source"], "manual"))
    for item in source["installation_items"]:
        inventory.append(record(item["id"], item["name"], item["mass_kg"], item["position_m"], item["size_m"],
                                source["installation_estimate"]))
    battery_mass = pack["mass_kg"]["value"]
    total = sum_left(item["mass"]["value"] for item in inventory) + battery_mass
    x_moment = sum_left(item["mass"]["value"] * item["position"]["value"][0] for item in inventory)
    battery_x = (raw["balance"]["plan_cg"]["value"][0] * total - x_moment) / battery_mass
    restraint = next(item for item in inventory if item["id"] == "item_battery_restraint")
    restraint["position"]["value"][0] = battery_x
    # Moving the tray changes its first moment; solve battery and tray together.
    target_x = raw["balance"]["plan_cg"]["value"][0]
    tray_mass = restraint["mass"]["value"]
    fixed_moment = sum_left(item["mass"]["value"] * item["position"]["value"][0]
                            for item in inventory if item is not restraint)
    battery_x = (target_x * total - fixed_moment) / (battery_mass + tray_mass)
    restraint["position"]["value"][0] = battery_x
    battery_item = record("item_battery_main", pack["display_name"], battery_mass, [battery_x, 0.0, -0.02],
                          pack["dimensions_m"]["value"], pack["mass_kg"]["source"], "manual", "lipo")
    battery_item["size"] = copy.deepcopy(pack["dimensions_m"])
    inventory.append(battery_item)
    datum = cg(inventory)
    raw["id"] = source["id"]
    raw["description"] = ("EXPERIMENTAL Stik electric conversion: estimated installation, Scorpion 4020 motor, APC 12x8E "
                          "and a 6S 4000 mAh pack mass. Fixed 22.2 V supply; no depletion. "
                          "No current or overspeed protection; not physically validated.")
    raw["inventory"] = inventory
    raw.pop("fuel_system", None)
    raw["balance"].pop("fuel_state", None)
    raw["balance"]["configuration"] = "estimated-electric-inventory-v1"
    raw["balance"]["plan_cg"] = q(datum, "m", "derived", EST + "battery station balances the donor's plan longitudinal CG; y/z from inventory. Actual bay fit unverified")
    raw["balance"]["cg_tolerance"] = q(0.001, "m", "estimated", EST + "inventory balance numerical tolerance; physical build unverified")
    raw["capabilities"]["energy"] = "fixed_voltage"
    # Do not retain the donor's projecting glow-cylinder collision envelope.
    # Replace its four probes with extrema of the estimated installed motor box;
    # the remaining airframe/spinner probes and the independent rotating disc stay.
    cx, cy, cz = motor["position_m"]
    sx, sy, sz = motor["size_m"]
    motor_points = {
        "probe_engine_head": ("probe_motor_right", [cx, cy + sy / 2, cz]),
        "probe_engine_top": ("probe_motor_top", [cx, cy, cz + sz / 2]),
        "probe_engine_front_top": ("probe_motor_front_top", [cx - sx / 2, cy, cz + sz / 2]),
        "probe_engine_front_bottom": ("probe_motor_front_bottom", [cx - sx / 2, cy, cz - sz / 2]),
    }
    for index, old_id in enumerate(raw["crash_hull_ids"]):
        if old_id in motor_points:
            new_id, point = motor_points[old_id]
            raw["crash_hull_ids"][index] = new_id
            # The current closed hull enum calls this powerplant region "engine";
            # it does not identify a combustion source or add one to the inventory.
            raw["crash_hull_components"][index] = "engine"
            raw["crash_hull"]["value"][index] = point
    raw["crash_hull"]["source"] += "; EL1e-STIK-03a: glow cylinder probes replaced by estimated motor-box extrema"
    kv, resistance = fitted_motor(source)
    i0 = motor["sample_no_load_current_a_at_20_v"]
    rotor_inertia = prop["mass_kg"] * (prop["size_m"][1] ** 2 + prop["size_m"][2] ** 2) / 12 + prop["motor_rotor_inertia_kg_m2"]
    fitting = EST + motor["fit_note"] + " Source: " + motor["chart_url"]
    map_src = EST + prop["map_note"] + " " + prop["map_url"]
    raw["propulsion"] = {
        "id": "propulsion_main", "kind": "electric_prop",
        "motor": {
            "kv_rpm_per_volt": q(kv, "rpm/V", "estimated", fitting),
            "resistance_scope": "motor_winding_equivalent",
            "resistance_ohm": q(resistance, "ohm", "estimated", fitting),
            "no_load_current_a": q(i0, "A", "manual", motor["chart_url"] + ": sample motor 1.79 A at 20 V; held constant as a model approximation"),
            "no_load_context": {"voltage_v": q(20.0, "V", "manual", motor["chart_url"]),
                                "rpm": q((20.0 - resistance * i0) * kv, "rpm", "derived", fitting + "; model-implied, not measured no-load rpm"),
                                "temperature_c": q(25.0, "°C", "estimated", EST + "reference context only; no motor thermal model")}},
        "battery": {"kind": "fixed_voltage", "voltage_v": q(22.2, "V", "manual", "6S nominal bus; fixed ideal source with no sag or depletion")},
        "esc": {"kind": "ideal_motoring", "command_mapping": "identity"},
        "propeller": {"name": prop["name"], "diameter": q(prop["diameter_m"], "m", "manual", prop["product_url"]),
                      "ct_table": q([[j, ct] for j, ct, cp in prop["j_ct_cp"]], "1", "borrowed", map_src),
                      "cp_table": q([[j, cp] for j, ct, cp in prop["j_ct_cp"]], "1", "borrowed", map_src),
                      "rotating_inertia": q(rotor_inertia, "kg·m2", "estimated", EST + "uniform prop box polar inertia plus assumed motor rotor 0.00004 kg·m2; mass distribution unmeasured"),
                      "thrust_angles": q([0.0, 0.0], "deg", "estimated", EST + "donor thrust direction"),
                      "thrust_line_offset": q([hub[k] - datum[k] for k in range(3)], "m", "derived", EST + "donor fixed LE-frame hub minus new inventory CG")}}
    validate_physical_identity(raw)
    variant = copy.deepcopy(raw)
    variant["description"] = variant["description"].replace("Fixed 22.2 V supply; no depletion.", "Estimated finite 6S pack_ecm with sag and depletion; no validated ESC firmware.")
    variant["capabilities"]["energy"] = "pack_ecm"
    variant["propulsion"]["battery"] = {
        "kind": "pack_ecm", "pack": {"id": source["pack_id"], "sha256": hashlib.sha256(pack_bytes).hexdigest()},
        "mount_inventory_id": "item_battery_main", "initial_soc": q(1.0, "1", "estimated", EST + "fresh balanced charge"),
        "auxiliary_current_a": q(0.2, "A", "estimated", EST + "receiver and four servos via assumed BEC; no measured load"),
        "cooling_airflow_fraction": q(0.1, "1", "estimated", EST + "tentative enclosed bay airflow fraction; cooling not measured"),
        "weak_cell": {"capacity_factor": q(1.0, "1", "estimated", EST + "initial balanced pack"),
                      "resistance_factor": q(1.0, "1", "estimated", EST + "initial balanced pack"),
                      "soc_offset": q(0.0, "1", "estimated", EST + "initial balanced pack")}}
    # The production contract requires an explicit supervisor. This is a generic
    # experimental model setting, not a Tribunus firmware claim.
    lvc_src = EST + "generic model assumption; Tribunus III configuration and firmware unknown"
    variant["propulsion"]["esc"]["low_voltage_cutoff"] = {
        "mode": "soft", "cell_detection": "fixed", "fixed_cells": q(6, "1", "derived", "specified 6S pack"),
        "cutoff_per_cell_v": q(3.2, "V", "estimated", lvc_src), "soft_limit": q(0.5, "1", "estimated", lvc_src),
        "soft_ramp_s": q(3.0, "s", "estimated", lvc_src), "debounce_s": q(0.5, "s", "estimated", lvc_src),
        "recovery": "throttle_reset", "reset_throttle_max": q(0.05, "1", "estimated", lvc_src),
        "voltage_filter_s": q(0.1, "s", "estimated", lvc_src)}
    validate_physical_identity(variant)
    return raw, variant


def render(data):
    return (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--draft-dir", type=Path)
    args = parser.parse_args()
    if args.check and args.draft_dir:
        parser.error("--check and --draft-dir cannot be combined")
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    pack_bytes = (ROOT / "app/data/batteries/packs" / (source["pack_id"] + ".json")).read_bytes()
    pack = json.loads(pack_bytes)
    ideal, finite = aircraft(source, pack, pack_bytes)
    paths = (IDEAL, PACK_VARIANT)
    if args.draft_dir:
        args.draft_dir.mkdir(parents=True, exist_ok=True)
        paths = (args.draft_dir / IDEAL.name, args.draft_dir / PACK_VARIANT.name)
    for path, result in zip(paths, (ideal, finite)):
        data = render(result)
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit("stale: " + str(path))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        print(hashlib.sha256(data).hexdigest(), path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
