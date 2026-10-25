#!/usr/bin/env python3
"""F4U-11: write the F4U Corsair's crash-economics costing entry into research/crash-economics/aircraft-costing.json.

The entry binds every physical inventory row of app/data/aircraft/f4u_corsair_250.json to a priced or explicitly
unpriced line, maps each hull and gear contact to the components a hit inspects, and pins the physics file's SHA-256
(`expected_source_sha256`), so a physics change forces a reviewed rebind. Dated offers retain their individual
observation dates. F4U-11-R3 rechecks engine/pneumatic package scope and servo proxies;
kit and unmatched package prices remain candidates. EUR propeller evidence is not converted to USD.

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


def offer(sku):
    return f"f4u_carf_{sku}_20261025"


def surface_group(line_id, inventory, skus, notes):
    row = line(line_id, inventory, notes + " Parts-only composite estimate from CARF single-color spares, observed 2026-10-25; not a sold assembly. Paint surcharge, installed hinges/linkages/hardware, inspection, assembly labor, tax and freight remain unresolved. These costs do not follow automatically from contact or C0-C4 severity.")
    row["price_constituents"] = [{"offer_id": offer(sku), "quantity": 1} for sku in skus]
    return row


LINES = [
    line("engine_moki_s250", ["engine_main", "engine_mount_exhaust"],
         "CARF 953250 whole-engine purchase proxy, $4,610 observed 2026-10-25. MOKI S250 manual confirms cast radial mount and ignition; manufacturer listing confirms mounted ring muffler. Applying those standard package contents to CARF's same-model offer is an inference, not seller-confirmed box contents. Included ignition must not be charged again; module-only price, external switch and battery remain unresolved/separate. Firewall bolts and spacers are excluded. Engine contact opens inspection, not automatic replacement; this is no internal repair or labor quote.",
         kind="price_proxy", observation=offer("953250")),
    line("ignition_module", ["ignition_module"], "Unpriced module-only replacement, sensor lead and external switch. Module/sensor are included in the whole-engine package; never add another module charge to it. The external switch is NOT included per MOKI's installation instructions; its installed identity remains unknown."),
    line("propeller", ["propeller_main"], "30x18 three-blade wood propeller (SEP class). Heilemann SEP 250 3-B observed 2026-10-25: EUR 157.35 base (29x18) + EUR 15.59 size option = EUR 172.94 for 30x18, undrilled bolt pattern; bored option adds EUR 15 (EUR 187.94). Listed without VAT; shipping/import charges unresolved. USD remains unpriced: no exchange rate or exact USD quote. Aeroscale's $112 family listing has no 30x18 variant; CARF's $692 carbon set is a different propeller."),
    line("spinner_main", ["spinner_main"], "Unpriced aluminium hub cap and propeller bolts."),
    line("engine_mount", ["engine_mount"], "Unpriced firewall bolts, blind nuts and thrust spacers."),
    line("cowl_main", ["cowl_main"], "CARF 791102 silver single-color cowl, $262 base reference observed 2026-10-25. Price proxy for the installed painted cowl, not an exact livery quote. CARF adds 5% per additional color and requests the original item/scheme; finish matching, hardware and labor remain unpriced.", kind="price_proxy", observation=offer("791102")),
    line("fuel_tank", ["fuel_tank"], "Unpriced 1 l gasoline tank with lines."),
    line("fuel_flight", ["fuel_flight"], "Unpriced half-tank flight fuel; fill and fuel price not established."),
    line("ignition_battery", ["ignition_battery"], "Unpriced 2S LiPo ignition battery."),
    line("receiver_batteries", ["receiver_batteries"], "Unpriced two 2S LiFe receiver batteries."),
    line("receiver_radio", ["receiver_radio"], "Unpriced receiver, switches and power distribution; installed radio identity unknown."),
    line("retract_air", ["retract_air"], "CARF 790650 complete pneumatic-system purchase proxy, $479 observed 2026-10-25: air tank, lines, Festo fittings, electronic valves and quick disconnects. Set-level replacement of the authored air installation, not a single damaged valve/line; installed part identities and labor remain unresolved. Does not include retract legs or wheels. Contact only requests inspection.",
         kind="price_proxy", observation=offer("790650")),
    *[line(component_id, [inventory_id],
           f"{description}. Separated by control installation for local crash inspection; the two flaps on each side remain one physical inventory group. Savox SA-1230SG+ at ServoCity ($103.39, rechecked 2026-10-25) remains a class value proxy, not the installed identity, a fit qualification or a verified current stock count. Cables, linkage and wiring remain unpriced.",
           kind="price_proxy", observation="f4u_savox_sa1230sgp_servocity_20261025", quantity=quantity)
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
         "Two small throttle/choke servos; Hitec HS-311 ($16.99 each at Horizon, rechecked 2026-10-25) is an ordinary-servo value proxy. Linkage unpriced; no installed model or fit claimed.",
         kind="price_proxy", observation="f4u_hitec_hs311_horizon_20261025", quantity=2),
    line("gear_main_left", ["gear_main_left"], "Unpriced Sierra Giant Scale rotating retract, strut, wheel and door (CARF kit equipment)."),
    line("gear_main_right", ["gear_main_right"], "Unpriced Sierra Giant Scale rotating retract, strut, wheel and door (CARF kit equipment)."),
    line("gear_tail", ["gear_tail"], "Unpriced retractable tail wheel with doors and steering."),
    line("wing_left", ["wing_left"], "Unpriced installed left wing group. CARF 791216 folding-wing spare is $754 single-color; control-surface, hardware and paint coverage remains unresolved."),
    line("wing_right", ["wing_right"], "Unpriced installed right wing group. CARF 791215 folding-wing spare is $754 single-color; control-surface, hardware and paint coverage remains unresolved."),
    line("wing_joiner", ["wing_joiner"], "Unpriced aluminium wing tubes and bolts."),
    line("fuselage_front", ["fuselage_front"], "Unpriced CARF composite forward fuselage."),
    line("fuselage_rear", ["fuselage_rear"], "Unpriced CARF composite rear fuselage and tail cone."),
    line("canopy_pilot", ["canopy_pilot"], "Unpriced canopy, frame and pilot figure."),
    surface_group("horizontal_tail", ["horizontal_tail"], ["791301", "791302", "791303", "791304"],
                  "Two stabilizer sides plus right and left elevators: $111 + $111 + $111 + $121 = $454. Both sides are priced only when an explicit inspection selects replacement of this grouped physical inventory item; a tip contact merely requests inspection."),
    surface_group("vertical_tail", ["vertical_tail"], ["791305", "791306"],
                  "Vertical fin plus rudder: $130 + $111 = $241. Grouped physical inventory replacement reference; a fin or rudder contact does not prove both parts are lost."),
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
    researched = ["953250", "790500", "790550", "790600", "790650", "790199", "930170", "791100",
                  "791102", "791101", "790105", "790104", "790810", "790805", "791103", "791212",
                  "791215", "791216", "791220", "791301", "791302", "791303", "791304", "791305",
                  "791306", "790700", "790750", "790751", "790752", "795000"]
    return {
        "aircraft_id": ID,
        "status": "independent_partial_inventory_costing",
        "price_observations": ["f4u_savox_sa1230sgp_servocity_20261025", "f4u_hitec_hs311_horizon_20261025"] + [offer(sku) for sku in researched],
        "replacement_total_minor": None,
        "missing": [
            "The exact Navy Blue folding-wing ARF 795000 has a $5,170 USD purchase reference, not a complete-build price; keep it unattached to avoid kit-plus-spares double counting. Single-color spare prices exclude the scheme-specific quote (CARF adds 5% per additional color), inspection, hardware, labor, tax and freight.",
            "Moki S250 $4,610 whole-engine proxy uses manufacturer-documented standard mount, ring muffler and ignition contents; CARF-specific box confirmation, module-only repair, external switch, post-strike inspection and labor remain unresolved. Never add another ignition charge to the package. Pneumatic $479 proxy is a complete-system purchase, not a single valve repair.",
            "Main retract and wheel prices are set/pair offers, not per-leg prices; tail gear/door contents and steering linkage remain unresolved. Folding-wing control-surface inclusion, full-fuselage overlap, and canopy/pilot scope prevent automatic attachment of their prices.",
            "Exact SEP-class 30x18 price verified in EUR only: 172.94 undrilled or 187.94 bored, before shipping/import charges. USD price remains null without a sourced conversion. The priced 32-inch CARF carbon set cannot replace its identity. Batteries, radio, fuel system and other unresolved parts remain unpriced; all twelve servo positions retain class value proxies.",
        ],
        "notes": "F4U-11-R3 double price pass: parts-only reference subtotal $7,113.88 = twelve servo proxies $1,067.88 + cowl $262 + horizontal surfaces $454 + vertical surfaces $241 + whole-engine package proxy $4,610 + pneumatic-system proxy $479. Kit and unmatched offers remain unattached candidates. Partial purchase references are neither a complete-build amount nor an accident repair bill; no automatic engine/air-system loss or calibrated failure probability is claimed.",
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
