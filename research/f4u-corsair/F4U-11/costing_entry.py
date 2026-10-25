#!/usr/bin/env python3
"""F4U-11: write the F4U Corsair's crash-economics costing entry into research/crash-economics/aircraft-costing.json.

The entry binds every physical inventory row of app/data/aircraft/f4u_corsair_250.json to a priced or explicitly
unpriced line, maps each hull and gear contact to the components a hit inspects, and pins the physics file's SHA-256
(`expected_source_sha256`), so a physics change forces a reviewed rebind. Prices reuse existing observations only
(two servo proxies): a new observation would move the price catalog's single observation date for every aircraft.
The CARF price of the Moki S250 is recorded in the notes as dated evidence instead.

    python research/f4u-corsair/F4U-11/costing_entry.py           # writes or rebinds the entry
    python research/f4u-corsair/F4U-11/costing_entry.py --check   # fails if the entry differs

Then run research/crash-economics/build_runtime.py to regenerate app/data/economy/catalog.json.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
COSTING = ROOT / "research/crash-economics/aircraft-costing.json"
SOURCE = ROOT / "app/data/aircraft/f4u_corsair_250.json"
ID = "f4u-corsair-250"


def line(line_id, inventory, notes, kind="estimated", observation=None, quantity=1):
    row = {"id": line_id, "quantity": quantity, "physical_inventory_ids": inventory, "evidence_kind": kind}
    if observation:
        row["price_observation"] = observation
    row["notes"] = notes
    return row


LINES = [
    line("engine_moki_s250", ["engine_main", "engine_mount_exhaust"],
         "Moki S250 five-cylinder radial with its cast radial mount and collector ring (the physics splits the 5.4 kg engine into two rows). CARF-Models lists the Moki S250 at 4,610.00 USD (carf-models.com/en/products/moki-s250, observed 2026-10-22); not entered as a price observation because the shared price catalog carries one observation date. Unpriced here."),
    line("ignition_module", ["ignition_module"], "Unpriced Moki ignition module, sensor lead and switch; supplied with the engine per the Moki manual, so a separate replacement price is not established."),
    line("propeller", ["propeller_main"], "Unpriced 30x18 three-blade wood propeller (SEP class, Moki S250 manual); no current USD quote verified."),
    line("spinner_main", ["spinner_main"], "Unpriced aluminium hub cap and propeller bolts."),
    line("engine_mount", ["engine_mount"], "Unpriced firewall bolts, blind nuts and thrust spacers."),
    line("cowl_main", ["cowl_main"], "Unpriced CARF composite cowl (about 335 mm); no separate CARF spare-part price verified."),
    line("fuel_tank", ["fuel_tank"], "Unpriced 1 l gasoline tank with lines."),
    line("fuel_flight", ["fuel_flight"], "Unpriced half-tank flight fuel; fill and fuel price not established."),
    line("ignition_battery", ["ignition_battery"], "Unpriced 2S LiPo ignition battery."),
    line("receiver_batteries", ["receiver_batteries"], "Unpriced two 2S LiFe receiver batteries."),
    line("receiver_radio", ["receiver_radio"], "Unpriced receiver, switches and power distribution; installed radio identity unknown."),
    line("retract_air", ["retract_air"], "Unpriced air tank, valves and lines for the Sierra retracts and Robart door cylinders."),
    *[line(component_id, [inventory_id],
           f"{description}. Separated by control installation for local crash inspection; the two flaps on each side remain one physical inventory group. Savox SA-1230SG+ at ServoCity ($103.39, observed 2026-10-15) remains a class value proxy, not the installed identity, a fit qualification or a verified current stock count. Cables, linkage and wiring remain unpriced.",
           kind="price_proxy", observation="savox-sa1230sgp", quantity=quantity)
      for component_id, inventory_id, quantity, description in [
          ("aileron_servo_left", "servo_aileron_left", 1, "Left aileron servo"),
          ("aileron_servo_right", "servo_aileron_right", 1, "Right aileron servo"),
          ("flap_servos_left", "servo_flap_left", 2, "Left inner and outer flap servos"),
          ("flap_servos_right", "servo_flap_right", 2, "Right inner and outer flap servos"),
          ("elevator_servos", "servo_elevator", 2, "Two elevator servos"),
          ("rudder_servo", "servo_rudder", 1, "Rudder servo"),
          ("tail_steering_servo", "servo_tail_steering", 1, "Tail-wheel steering servo"),
      ]],
    line("throttle_choke_servos", ["servo_throttle_choke"],
         "Two small throttle/choke servos; Hitec HS-311 ($16.99 each at Tower) is the ordinary-servo value proxy the P-51 uses. Linkage unpriced; no installed model claimed.",
         kind="price_proxy", observation="stik_servos_hitec_hs311_four", quantity=2),
    line("gear_main_left", ["gear_main_left"], "Unpriced Sierra Giant Scale rotating retract, strut, wheel and door (CARF kit equipment)."),
    line("gear_main_right", ["gear_main_right"], "Unpriced Sierra Giant Scale rotating retract, strut, wheel and door (CARF kit equipment)."),
    line("gear_tail", ["gear_tail"], "Unpriced retractable tail wheel with doors and steering."),
    line("wing_left", ["wing_left"], "Unpriced CARF composite left wing panel with flaps and aileron; no spare-part price verified."),
    line("wing_right", ["wing_right"], "Unpriced CARF composite right wing panel with flaps and aileron; no spare-part price verified."),
    line("wing_joiner", ["wing_joiner"], "Unpriced aluminium wing tubes and bolts."),
    line("fuselage_front", ["fuselage_front"], "Unpriced CARF composite forward fuselage."),
    line("fuselage_rear", ["fuselage_rear"], "Unpriced CARF composite rear fuselage and tail cone."),
    line("canopy_pilot", ["canopy_pilot"], "Unpriced canopy, frame and pilot figure."),
    line("horizontal_tail", ["horizontal_tail"], "Unpriced stabilizer and elevator."),
    line("vertical_tail", ["vertical_tail"], "Unpriced fin and rudder."),
    line("control_hardware", ["control_hardware"], "Unpriced pushrods, horns, cowl fasteners and hardware."),
    line("final_assembly_and_commissioning", [], "Unpriced Corsair-specific final assembly, balancing, commissioning and post-crash inspection labor. No transferable allowance assumed."),
]
CONTACTS = {
    "probe_wing_left_tip": ["wing_left"], "probe_wing_right_tip": ["wing_right"],
    "probe_gull_left_bottom": ["wing_left", "wing_joiner"],
    "probe_gull_right_bottom": ["wing_right", "wing_joiner"],
    "probe_tail_cone": ["fuselage_rear"], "probe_fuselage_rear_bottom": ["fuselage_rear"],
    "probe_stabilizer_left_aft": ["horizontal_tail"], "probe_stabilizer_right_aft": ["horizontal_tail"],
    "probe_fin_aft_upper": ["vertical_tail"],
    "propeller/propulsion_main": ["propeller"],
    "probe_wing_left_le": ["wing_left"], "probe_wing_left_te": ["wing_left"],
    "probe_wing_right_le": ["wing_right"], "probe_wing_right_te": ["wing_right"],
    "probe_spinner_tip": ["spinner_main", "engine_moki_s250", "engine_mount", "fuselage_front"],
    "probe_propeller_bottom": ["propeller"], "probe_propeller_lower_left": ["propeller"], "probe_propeller_lower_right": ["propeller"],
    "probe_rudder_bottom": ["vertical_tail"], "probe_fin_top": ["vertical_tail"],
    "probe_stabilizer_left_tip": ["horizontal_tail"], "probe_stabilizer_right_tip": ["horizontal_tail"],
    "probe_canopy_top": ["canopy_pilot", "fuselage_front"],
    "probe_cowl_bottom": ["cowl_main", "engine_moki_s250"],
    "contact_main_left": ["gear_main_left"], "contact_main_right": ["gear_main_right"], "contact_tail": ["gear_tail"],
}

# F4U-11-R2: advisory inspection follows local installation and load paths from
# the CARF manual, not C0-C4 presentation severity. It never asserts part failure.
for side in ("left", "right"):
    for suffix in ("tip", "le", "te"):
        CONTACTS[f"probe_wing_{side}_{suffix}"] += [f"aileron_servo_{side}", f"flap_servos_{side}", "wing_joiner"]
    CONTACTS[f"probe_gull_{side}_bottom"] += [f"flap_servos_{side}", f"gear_main_{side}", "retract_air"]
    CONTACTS[f"contact_main_{side}"] += [f"wing_{side}", "wing_joiner", "retract_air"]
    for suffix in ("tip", "aft"):
        CONTACTS[f"probe_stabilizer_{side}_{suffix}"] += ["elevator_servos", "fuselage_rear"]
for contact_id in ("probe_fin_top", "probe_fin_aft_upper", "probe_rudder_bottom"):
    CONTACTS[contact_id] += ["rudder_servo", "fuselage_rear"]
for contact_id in ("probe_tail_cone", "probe_fuselage_rear_bottom"):
    CONTACTS[contact_id] += ["horizontal_tail", "elevator_servos", "gear_tail", "tail_steering_servo"]
CONTACTS["contact_tail"] += ["fuselage_rear", "tail_steering_servo", "retract_air"]
CONTACTS["probe_cowl_bottom"] += ["engine_mount", "fuselage_front", "ignition_module", "throttle_choke_servos"]
CONTACTS["probe_spinner_tip"] += ["ignition_module", "throttle_choke_servos"]


def entry(source_sha):
    return {
        "aircraft_id": ID,
        "status": "independent_partial_inventory_costing",
        "price_observations": ["savox-sa1230sgp", "stik_servos_hitec_hs311_four"],
        "replacement_total_minor": None,
        "missing": [
            "No current CARF-Models F4U-1D 1:4.5 kit, spare-part or retract price was entered: the CARF product pages did not show a kit price when observed, and the 2011 Model Airplane News prices ($3,695 ARF with wing fold) are historical.",
            "The Moki S250 (CARF 4,610.00 USD, observed 2026-10-22) is recorded in the notes but not entered as a price observation, because the shared price catalog carries one observation date for every aircraft.",
            "Propeller, cowl, airframe parts, gear, batteries, radio, fuel system and labor remain unpriced; ten flight-control and two throttle/choke servo positions use class value proxies, not installed identities.",
        ],
        "notes": "Independent coverage of every physical inventory row of the 1/4.5 F4U Corsair (F4U-11). Known priced-part subtotal is $1,067.88: ten $103.39 SA-1230SG+ control-servo proxies and two $16.99 HS-311 throttle/choke-servo proxies. The Moki S250 alone lists at $4,610.00 (CARF, 2026-10-22, not entered). This is not a complete-build purchase amount.",
        "dossier": {
            "expected_source_sha256": source_sha,
            "lines": LINES,
            "contact_components": CONTACTS,
            "propeller_component_id": "propeller",
            "propeller_inspection_ids": ["engine_moki_s250", "spinner_main", "engine_mount", "cowl_main", "fuselage_front", "ignition_module", "throttle_choke_servos"],
        },
    }


def main():
    text = COSTING.read_text(encoding="utf-8")
    costing = json.loads(text)
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    inventory = {row["id"] for row in source["inventory"]} - {"ballast_reference"}
    bound = {item for row in LINES for item in row["physical_inventory_ids"]}
    assert bound == inventory, f"unbound {sorted(inventory - bound)}, unknown {sorted(bound - inventory)}"
    contacts = set(source["crash_hull_ids"]) | {c["id"] for c in source["landing_gear"]["contacts"]} | {"propeller/propulsion_main"}
    assert set(CONTACTS) == contacts, sorted(contacts ^ set(CONTACTS))
    new = entry(hashlib.sha256(SOURCE.read_bytes()).hexdigest())
    fleet = costing["fleet"]
    index = next((i for i, f in enumerate(fleet) if f["aircraft_id"] == ID), None)
    if index is None:
        index = next(i for i, f in enumerate(fleet) if f["aircraft_id"] == "p51d-mustang-120") + 1
        fleet.insert(index, new)
    else:
        fleet[index] = new
    rendered = json.dumps(costing, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        if rendered != text:
            sys.exit("aircraft-costing.json Corsair entry is stale: run research/f4u-corsair/F4U-11/costing_entry.py")
        print("Corsair costing entry current")
        return
    COSTING.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"wrote the {ID} costing entry ({len(LINES)} lines, {len(CONTACTS)} contact mappings)")


if __name__ == "__main__":
    main()
