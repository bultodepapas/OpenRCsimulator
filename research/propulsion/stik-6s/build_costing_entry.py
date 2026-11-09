#!/usr/bin/env python3
"""Bind an explicitly unpriced electric inventory dossier to the generated source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "app/data/aircraft/stik_electric_6s.json"
COSTING = ROOT / "research/crash-economics/aircraft-costing.json"
AIRCRAFT_ID = "stik-electric-6s"


def entry(source, source_bytes):
    items = source["inventory"]
    lines = [{"id": item["id"], "quantity": 1, "physical_inventory_ids": [item["id"]],
              "evidence_kind": "estimated", "notes": "Unpriced installed component: " + item["name"] +
              ". No matched current USD replacement offer is asserted."} for item in items]
    by_label = {
        "left_wing_tip": ["item_wing_airframe"], "right_wing_tip": ["item_wing_airframe"],
        "left_stab_tip": ["item_stabilizer_elevator"], "right_stab_tip": ["item_stabilizer_elevator"],
        "fin_top": ["item_fin_rudder"], "tail_end": ["item_fuselage_rear", "item_stabilizer_elevator", "item_fin_rudder"],
        "nose": ["item_fuselage_front", "item_motor_mount"],
        "engine": ["item_motor_main", "item_motor_mount", "item_fuselage_front"],
        "spinner": ["item_spinner_main", "item_prop_adapter", "item_motor_main"],
    }
    contacts = {identifier: by_label[label] for identifier, label in zip(source["crash_hull_ids"], source["crash_hull_components"])}
    contacts.update({"contact_main_left": ["item_main_gear_assembly", "item_fuselage_front"],
                     "contact_main_right": ["item_main_gear_assembly", "item_fuselage_front"],
                     "contact_nose": ["item_nose_gear_assembly", "item_fuselage_front"],
                     "propeller/propulsion_main": ["item_propeller_main"]})
    known = {item["id"] for item in items}
    if any(not set(targets) <= known for targets in contacts.values()):
        raise ValueError("contact references absent inventory")
    return {
        "aircraft_id": AIRCRAFT_ID, "status": "independent_partial_inventory_costing",
        "price_observations": [], "replacement_total_minor": None,
        "missing": ["No current matched USD replacement offers or complete conversion/assembly cost have been reviewed; every component remains unpriced.",
                    "The estimated motor, mounting, wiring and battery installation require physical build and fit verification."],
        "notes": "Independent unpriced electric inventory; no inherited glow engine, tank or fuel valuation. Contact maps identify inspection scope, not damage or replacement claims.",
        "dossier": {"expected_source_sha256": hashlib.sha256(source_bytes).hexdigest(), "lines": lines,
                    "contact_components": contacts, "propeller_component_id": "item_propeller_main",
                    "propeller_inspection_ids": ["item_motor_main", "item_motor_mount", "item_prop_adapter", "item_fuselage_front"]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source_bytes = SOURCE.read_bytes()
    source = json.loads(source_bytes)
    data = json.loads(COSTING.read_text(encoding="utf-8"))
    matches = [i for i, row in enumerate(data["fleet"]) if row["aircraft_id"] == AIRCRAFT_ID]
    if len(matches) > 1:
        raise SystemExit("duplicate electric costing entries")
    candidate = entry(source, source_bytes)
    if args.check:
        if not matches or data["fleet"][matches[0]] != candidate:
            raise SystemExit("stale electric costing entry")
        print("electric costing entry current")
        return
    if matches:
        data["fleet"][matches[0]] = candidate
    else:
        data["fleet"].append(candidate)
    COSTING.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print("electric costing entry generated")


if __name__ == "__main__":
    main()
