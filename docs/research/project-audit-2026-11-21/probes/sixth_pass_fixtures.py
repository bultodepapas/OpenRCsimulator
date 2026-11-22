"""Generate explicitly synthetic A36 R6 inputs beside untouched stock files.

These are reproducible domain witnesses, not measured aircraft/propeller data.
The returned hashes identify the complete generated files. No source data or
production implementation is changed.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path


def write_input(project: Path, name: str, value: dict) -> dict:
    data = (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()
    (project / name).write_bytes(data)
    return {"path": name, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def create_propeller_inputs(project: Path) -> list[dict]:
    stock = json.loads((project / "data/aircraft/turbo_lumber_evolution.json").read_bytes())
    minimal = copy.deepcopy(stock)
    cp = minimal["propulsion"]["propeller"]["cp_table"]
    row = next(row for row in cp["value"] if row[0] == 0.655)
    assert row[1] == 0.038
    row[1] = 0.020
    cp.update(kind="estimated", source="R6 synthetic partial-advance power deficit witness; not real propeller")
    normal = copy.deepcopy(stock)
    ct = normal["propulsion"]["propeller"]["ct_table"]["value"]
    cp = normal["propulsion"]["propeller"]["cp_table"]
    assert len(ct) == len(cp["value"])
    for thrust, power in zip(ct, cp["value"]):
        assert thrust[0] == power[0]
        if thrust[0] >= 0.373:
            power[1] = min(power[1], max(0.001, round(0.8 * thrust[0] * thrust[1], 8)))
    cp.update(kind="estimated", source="R6 synthetic energy-deficit flight-start witness, not real propeller")
    return [write_input(project, "r6_custom_power.json", minimal),
            write_input(project, "r6_custom_trim.json", normal)]


def create_tailless_wake_inputs(project: Path) -> list[dict]:
    x8 = json.loads((project / "data/aircraft/moonrunner_x99.json").read_bytes())
    stik = json.loads((project / "data/aircraft/jensen_ugly_stik_60.json").read_bytes())

    def quantity(value: object, unit: str) -> dict:
        return {"value": value, "unit": unit, "kind": "estimated",
                "source": "R4-F01 synthetic tractor/vertical-wake diagnostic; not measured aircraft geometry"}

    candidate = copy.deepcopy(x8)
    candidate["id"] = "r4-tailless-tractor-test"
    candidate["description"] = ("Synthetic research-only diagnostic: X8 aerodynamic/geometry values with a Stik-type legacy glow tractor and one central vertical wake piece. Retained inventory is a fixed-mass surrogate, not a measured motor installation.")
    candidate["capabilities"].update(propulsion_layout="single_tractor", energy="prescribed_fuel")
    candidate["propulsion"] = copy.deepcopy(stik["propulsion"])
    candidate["propulsion"]["id"] = "propulsion_main"
    candidate["propulsion"]["description"] = "Synthetic Stik-derived glow tractor on X8 numeric airframe; not a measured physical installation."
    prop = candidate["propulsion"]["propeller"]
    prop["thrust_angles"] = quantity([0.0, 0.0], "deg")
    prop["thrust_line_offset"] = quantity([-0.435, 0.0, -0.004255534], "m")
    prop["slipstream"] = {
        "hub": quantity([0.0, 0.0, 0.0], "m"),
        "wash_factor": quantity([0.8, 1.8], "1"),
        "swirl_factor": quantity(0.0, "1"),
        "vertical_drift": quantity(0.5, "1"),
        "pieces": [{"surface": "vertical", "area": quantity(0.020, "m2"),
                    "root": quantity([0.4851627273, 0.0, 0.0], "m"),
                    "span_dir": quantity([0.0, 0.0, 1.0], "1"),
                    "span": quantity(0.10, "m"), "chords": quantity([0.20, 0.20], "m")}],
    }
    for item in candidate["inventory"]:
        if item["id"] in ("motor_main", "propeller_main", "motor_mount", "esc_main", "battery_main"):
            item["name"] = "synthetic retained mass surrogate: " + item["id"]
            for value in item.values():
                if isinstance(value, dict) and {"value", "unit", "kind", "source"}.issubset(value):
                    value["kind"] = "estimated"
                    value["source"] = "Synthetic fixed-mass surrogate, numerically retained from stock X8; not a measured tractor installation"
    control = copy.deepcopy(candidate)
    del control["propulsion"]["propeller"]["slipstream"]
    control["id"] = "r4-tailless-tractor-control"
    electric = copy.deepcopy(x8)
    electric["id"] = "r4-tailless-electric-wake-control"
    electric["propulsion"]["propeller"]["slipstream"] = copy.deepcopy(prop["slipstream"])
    return [write_input(project, "r4_candidate.json", candidate),
            write_input(project, "r4_no_wake.json", control),
            write_input(project, "r4_electric_wake.json", electric)]
