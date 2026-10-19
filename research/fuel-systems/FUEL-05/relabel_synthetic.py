"""FUEL-05d (D7): give synthetic electric Stik fixtures stable physical identities.

The four fixtures keep the original Stik mass distribution on purpose ("original inventory mass
distribution"), but four display names claimed a glow engine, a tank and half a tank of fuel. This gives
those neutral donor masses stable semantic IDs and makes the names explicit. It also assigns the full
versioned identity module using authored, semantic IDs copied from the reviewed Stik source identity.
No mass, position, size or energy tag changes, so every numerical flight result is unchanged.

Usage: python3 -I research/fuel-systems/FUEL-05/relabel_synthetic.py [--check]
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FILES = ["synthetic_stik_electric_%s.json" % s for s in ("4s", "6s", "4s_battery", "6s_battery")]
DONOR = {
    "engine O.S. MAX-61FX": {
        "name": "donor mass at the glow engine station (no engine modeled)",
        "id": "donor_engine_station",
    },
    "muffler E-4010": {
        "name": "donor mass at the glow muffler station",
        "id": "donor_muffler_station",
    },
    "fuel tank (empty)": {
        "name": "donor mass at the fuel-tank station (no tank)",
        "id": "donor_tank_station",
    },
    "fuel (half tank)": {
        "name": "donor mass at the fuel station (no fuel)",
        "id": "donor_fuel_station",
    },
}
INVENTORY_IDS = {
    "donor mass at the glow engine station (no engine modeled)": "donor_engine_station",
    "donor mass at the glow muffler station": "donor_muffler_station",
    "propeller APC 12x6 Sport": "item_propeller_main",
    "spinner and prop nut": "item_spinner_main",
    "engine mount and bolts": "item_engine_mount",
    "donor mass at the fuel-tank station (no tank)": "donor_tank_station",
    "donor mass at the fuel station (no fuel)": "donor_fuel_station",
    "receiver battery 4.8 V 600 mAh": "item_receiver_battery",
    "receiver": "item_receiver_main",
    "fuselage servos (3)": "item_fuselage_servos",
    "aileron servo": "item_aileron_servo",
    "nose gear and 2.75 in wheel": "item_nose_gear_assembly",
    "main gear and 3 in wheels": "item_main_gear_assembly",
    "wing incl. ailerons": "item_wing_airframe",
    "fuselage front (firewall to F4)": "item_fuselage_front",
    "fuselage rear (F4 to tail)": "item_fuselage_rear",
    "stabilizer and elevator": "item_stabilizer_elevator",
    "fin and rudder": "item_fin_rudder",
    "pushrods, horns, hardware": "item_control_hardware",
    "virtual reference-build balancing mass": "item_balance_mass_virtual",
}
GEAR_IDS = {
    "main_left": "contact_main_left",
    "main_right": "contact_main_right",
    "nose": "contact_nose",
}
CRASH_HULL_IDS = [
    "probe_wing_left_tip",
    "probe_wing_right_tip",
    "probe_spinner_tip",
    "probe_tail_end",
    "probe_stabilizer_left_tip",
    "probe_stabilizer_right_tip",
    "probe_fin_top",
    "probe_belly_main",
]
SURFACE_IDS = {
    "aileron_left": "surface_aileron_left",
    "aileron_right": "surface_aileron_right",
    "elevator": "surface_elevator",
    "rudder": "surface_rudder",
}
NOTE = (" FUEL-05d: inventory items named 'donor mass' keep the glow Stik's mass distribution only;"
        " the fixture carries no engine, tank or fuel.")


def relabel(raw):
    found = {entry["id"]: 0 for entry in DONOR.values()}
    for item in raw["inventory"]:
        if item["name"] in DONOR:
            item["name"] = DONOR[item["name"]]["name"]
        item_id = INVENTORY_IDS.get(item["name"])
        if item_id is None:
            raise ValueError("unmapped synthetic fixture inventory item: " + item["name"])
        item["id"] = item_id
        if item_id in found:
            found[item_id] += 1
    if any(count != 1 for count in found.values()):
        raise ValueError("each synthetic fixture must contain each of the four donor masses exactly once")
    contacts = raw.get("landing_gear", {}).get("contacts", [])
    for contact in contacts:
        contact_id = GEAR_IDS.get(contact.get("name"))
        if contact_id is None:
            raise ValueError("unmapped synthetic fixture gear contact: " + str(contact.get("name")))
        contact["id"] = contact_id
    if len(contacts) != len(GEAR_IDS) or {contact["name"] for contact in contacts} != set(GEAR_IDS):
        raise ValueError("synthetic fixture gear contacts differ from the authored identity map")
    hull_points = raw.get("crash_hull", {}).get("value", [])
    if len(hull_points) != len(CRASH_HULL_IDS):
        raise ValueError("synthetic fixture hull points differ from the authored identity map")
    raw["crash_hull_ids"] = list(CRASH_HULL_IDS)
    raw["propulsion"]["id"] = "propulsion_main"
    raw["controls"]["surface_ids"] = dict(SURFACE_IDS)
    raw["physical_identity_version"] = 1
    if NOTE.strip() not in raw["description"]:
        raw["description"] += NOTE
    return raw


def render(raw):
    # The fixtures are stored with CRLF line endings and literal non-ASCII characters.
    return (json.dumps(raw, indent=2, ensure_ascii=False) + "\n").replace("\n", "\r\n").encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for name in FILES:
        path = ROOT / "app/data/aircraft" / name
        current = path.read_bytes()
        rendered = render(relabel(json.loads(current.decode("utf-8"))))
        if rendered != current:
            if args.check:
                stale.append(name)
            else:
                path.write_bytes(rendered)
    if stale:
        sys.exit("stale: " + ", ".join(stale))
    print("synthetic fixtures labelled" if not args.check else "synthetic fixtures current")


if __name__ == "__main__":
    main()
