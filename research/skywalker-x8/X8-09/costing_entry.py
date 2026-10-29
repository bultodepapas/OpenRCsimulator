#!/usr/bin/env python3
"""X8-09: write the Skywalker X8's crash-economics dossier and its dated price observations.

Independent build (no baseline inheritance). The entry binds every physical inventory row of
app/data/aircraft/moonrunner_x99.json to exactly one priced or explicitly unpriced line, maps each crash-hull probe and
the propeller strike to the economic groups a hit inspects, and pins the physics file's current SHA-256
(`expected_source_sha256`), so a physics change forces a reviewed rebind. The finite-pack variant
(battery/moonrunner_x99_6s_pack.json) is the same airframe: the runtime binds it as the catalog's registered variant
through the physical signature, as for the Turbo Lumber's 4S pack, so it needs no entry of its own.

The 2026-10-25 observations go into research/crash-economics/price-research-fleet.json (replaced by ID, appended
when new). They move the shared price-catalog snapshot date to 2026-10-25; older offers keep their own dates.

    python3 research/skywalker-x8/X8-09/costing_entry.py            # writes or rebinds the entry and offers
    python3 research/skywalker-x8/X8-09/costing_entry.py --check    # fails if either file differs
    python3 research/crash-economics/build_catalog.py               # then regenerate the price catalog
    python3 research/crash-economics/build_runtime.py               # and app/data/economy/catalog.json

Evidence: docs/research/skywalker-x8/X8-09/economy.md.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ECON = ROOT / "research/crash-economics"
COSTING = ECON / "aircraft-costing.json"
FLEET_PRICES = ECON / "price-research-fleet.json"
SOURCE = ROOT / "app/data/aircraft/moonrunner_x99.json"
PACK_SOURCE = ROOT / "app/data/aircraft/battery/moonrunner_x99_6s_pack.json"
ID = "moonrunner-x99"
LEGACY_ID = "skywalker-x8"
OBSERVED = "2026-10-25"


def offer(offer_id, brand, product, sku, category, amount_usd, price_kind, availability, quantity, url, quality, notes):
    return {"id": offer_id, "brand": brand, "product": product, "sku": sku, "category": category,
            "amount_usd": amount_usd, "price_kind": price_kind, "availability": availability, "quantity": quantity,
            "url": url, "evidence_quality": quality, "notes": f"Observed {OBSERVED}. {notes}", "observed_on": OBSERVED}


KIT = "x8_complete_kit_sonicmodell_robotshop_20261025"
MOTOR = "x8_motor_sunnysky_x3530_520kv_readymaderc_20261025"
PROP = "x8_propeller_apc_lp12060ep_readymaderc_20261025"
ESC = "x8_esc_hobbywing_skywalker_v2_60a_racedayquads_20261025"
BATTERY = "x8_battery_spektrum_spmx56s30_horizon_20261025"
SERVO = "x8_servo_emax_es3054_alofthobbies_20261025"
FC = "x8_flight_controller_matek_h743_wing_v3_racedayquads_20261025"
GPS = "x8_gps_holybro_m10_holybro_20261025"
RX = "x8_receiver_radiomaster_rp1_v2_radiomaster_20261025"
TELEMETRY = "x8_telemetry_holybro_sik_v3_915_holybro_20261025"
FPV = "x8_fpv_dji_o4_air_unit_racedayquads_20261025"
CHUTE = "x8_parachute_fruity_chutes_fwrb_7lb_20261025"
LEAD = "x8_nose_weight_hangar9_han3626_horizon_20261025"

OFFERS = [
    offer(KIT, "SonicModell", "Skywalker X8 2122 Flying Wing Drone FPV Complete Kit", "RB-Son-11", "aircraft", 507.41,
          "complete_kit_package_price", "Available on backorder at RobotShop US",
          "1 complete kit; the listing says it includes a motor, an airframe, ESC, servos, etc. and itemizes nothing else",
          "https://www.robotshop.com/products/sonicmodell-skywalker-x8-2122-flying-wing-drone-fpv-complete-kit",
          "Direct US retailer product page opened 2026-10-25; it carried a price-data timestamp of 2026-10-14. No motor, ESC, servo, propeller, carbon-tube or hardware model is named.",
          "Whole-aircraft package alternative, not attached to a line: its unitemized contents overlap the separately priced motor, ESC and servos and cannot be split into the wing and body groups. Battery and Tx/Rx are required and not included. The airframe-only Skywalker X8 Kit at Unmanned Tech Shop UK (SKU Z98.0001) listed GBP 259.49, sold out and awaiting stock, the same day; it is outside the USD runtime and lists only the EPO airframe kit with modular wing sections, fuselage and control surfaces, without stating servos, carbon tubes or motor mount."),
    offer(MOTOR, "SunnySky", "X Series V3 X3530 V3 Brushless Motor 520KV", "SS-XV3-X3530-520", "motor", 74.99,
          "motor_unit_price", "In Stock", "1 motor, 1 X mount bracket with screws, 1 propeller collet adapter",
          "https://www.readymaderc.com/products/details/sunny-sky-x-series-v3-x3520-brushless-motor-520kv",
          "Direct US retailer product page opened 2026-10-25; model, price, stock and included items are explicit. The URL slug says X3520, and the text gives a 30 mm stator height while the attribute table says 20.",
          "219 g, 520 Kv, 35 mm stator; the retailer recommends 6S and APC 12x6 to 14x7 propellers. Price proxy for the simulated 190 g 520 Kv 3530/4250-class outrunner, not the Skywalker PNP motor, whose USD price was not verified."),
    offer(PROP, "APC Propellers", "12x6EP thin electric pusher propeller", "LP12060EP", "propeller", 4.87,
          "propeller_unit_price", "Only 8 left", "1 propeller with one set of adapter rings",
          "https://www.readymaderc.com/products/details/apc-12x6ep-pusher-prop",
          "Direct US retailer product page opened 2026-10-25; APC part number, GTIN 686661120372, price and low-stock message are explicit. apcprop.com returned HTTP 403 and was not used.",
          "12x6, two blades, pusher (CW), 1/4 in bore, 26.9 g. Matches the simulated APC 12x6E pusher."),
    offer(ESC, "Hobbywing", "Skywalker V2 3-7S Wing 60A ESC", "HOBW-029400000207", "esc", 41.99,
          "esc_unit_price", "In stock", "1 ESC; a customer review says motor and XT60 connectors are not included",
          "https://www.racedayquads.com/products/hobbywing-skywalker-60a-2-6s-ubec-wing-esc",
          "Direct US retailer product page opened 2026-10-25; 3-7S input, 5 V/7 A BEC, price and stock are explicit. The SKU is the retailer's.",
          "Price proxy for the simulated 60 A ESC; the PNP ESC identity is not established."),
    offer(BATTERY, "Spektrum", "22.2V 5000mAh 6S 30C Smart G2 LiPo Battery: IC5", "SPMX56S30", "battery", 139.99,
          "battery_unit_price", "Backorder; expected January 2027", "1 battery pack",
          "https://www.horizonhobby.com/product/22.2v-5000mah-6s-30c-smart-g2-lipo-battery-ic5/SPMX56S30.html",
          "Direct official US retailer page opened 2026-10-25; capacity, cells, C rating, IC5 connector, price and backorder date are explicit. Weight was not in the retrieved content.",
          "Class match for the simulated 6S 5000 mAh 30C-class pack; a Smart G2 IC5 product, not a verified installed pack."),
    offer(SERVO, "EMAX", "ES3054 17 g metal-gear digital servo", "ES3054", "servo", 11.50,
          "servo_unit_price", "In stock, ready to ship",
          "1 servo with cross arm, six-arm horn, output disc, output screw and mounting screws with grommets",
          "https://alofthobbies.com/products/emax-es3054-servo-3-5kg-48-6-oz-in-13-sec-17-grams",
          "Direct US retailer product page opened 2026-10-25; price, stock and accessories are explicit (retailer SKU emax-es3054).",
          "3.5 kg cm at 6 V, 0.13 s/60 deg, 28.45 x 13 x 31.1 mm. The r4 delivery names one Emax ES3054 per wing half; the price is per servo."),
    offer(FC, "Matek", "H743-Wing V3 Flight Controller", "H743-WING-V3", "flight_controller", 130.99,
          "flight_controller_unit_price", "Sold out", "1 flight controller; no cables, PDB or GPS listed",
          "https://www.racedayquads.com/products/matek-h743-wing-v3-flight-controller",
          "Direct US retailer product page opened 2026-10-25; price and sold-out state are explicit (retailer SKU 22655).",
          "30 g, 54 x 36 x 13 mm, built-in current sensor. Price proxy for the simulated 30 g autopilot; the installed product is unknown and firmware support was not checked."),
    offer(GPS, "Holybro", "M10 GPS, IST8310 compass, standard 10-pin", "12040", "gps_compass", 43.99,
          "gps_unit_price", "Available (store variant data)", "1 M10 GPS module, 1 fixed carbon-fibre GPS mount",
          "https://holybro.com/products/m10-gps",
          "Direct manufacturer store page opened 2026-10-25; variant SKU, price and availability are explicit.",
          "32 g per the specification table. Price proxy for the simulated 30 g GPS and compass."),
    offer(RX, "RadioMaster", "RP1 V2 ExpressLRS 2.4 GHz Nano Receiver (FCC)", "HP0157.RX-RP1-V2", "receiver", 18.99,
          "receiver_unit_price", "Available (store variant data)",
          "1 receiver, 1 65 mm UFL T antenna, 1 user manual, 1 CRSF wire",
          "https://radiomasterrc.com/products/rp1-expresslrs-2-4ghz-nano-receiver",
          "Direct manufacturer store page opened 2026-10-25; variant SKU, price and availability are explicit.",
          "2.2 g serial receiver for a flight-controller build. Proxy only; the transmitter is excluded."),
    offer(TELEMETRY, "Holybro", "SiK Telemetry Radio V3, 100 mW, 915 MHz", "17013", "telemetry_radio", 58.99,
          "telemetry_set_price", "Available (store variant data)",
          "1 set: 2 interchangeable radio modules with antennas (air and ground), USB and JST-GH/DF13 cables",
          "https://holybro.com/products/sik-telemetry-radio-v3",
          "Direct manufacturer store page opened 2026-10-25; variant SKU, price, availability and two-module contents are explicit.",
          "Sold only as an air-and-ground pair; no single-module price was listed. One module is onboard; the other is ground equipment. Proxy only."),
    offer(FPV, "DJI", "O4 Air Unit", "O4-AIR-UNIT", "fpv_camera_vtx", 139.99,
          "fpv_system_unit_price", "In stock",
          "1 transmission module, 1 camera module, 1 3-in-1 cable, 1 antenna",
          "https://www.racedayquads.com/products/dji-o4-air-unit",
          "Direct US retailer product page opened 2026-10-25; retailer SKU 22794, price, stock and contents are explicit.",
          "About 8.2 g with camera plus a 0.75 g antenna; 3.7-13.2 V input, so 6S needs a regulated supply. Goggles are ground equipment. Price proxy for the simulated 30 g FPV camera and VTX; mass and product differ. The 26.6 g Walksnail Avatar HD Kit V2 (dual antenna) was sold out at Caddx ($159.00, discontinued) and RaceDayQuads ($191.99) the same day."),
    offer(CHUTE, "Fruity Chutes", "Fixed Wing Recovery Bundle - 7lb (3.2kg) @ 15fps", "FWRB-48-S-2P-YB", "recovery_parachute",
          402.27, "recovery_bundle_price", "2 items left; the page also offers a back-in-stock notice",
          "1 bundle: IFC-48-S Iris Ultra Compact parachute, CDB-4 deployment bag, TARC-15 pilot parachute, 3/8 in Y harness, 3 yd shock cord, 1.5 yd paraline, quick links and ties",
          "https://shop.fruitychutes.com/products/fixed-wing-recovery-bundle-7lbs-3-2kg-15fps",
          "Direct manufacturer store page opened 2026-10-25; SKU, price, contents and 270 g system weight are explicit; per-variant stock is not shown.",
          "Rated 3.2 kg at 15 ft/s; the simulated inventory totals about 3.13 kg. No ejection spring, latch servo or bay hardware is included, and the 270 g system is heavier than the 150 g simulated pack. Price proxy only."),
    offer(LEAD, "Hangar 9", "Self Stick Weight, 6 oz", "HAN3626", "ballast_weight", 9.99,
          "ballast_package_price", "Backorder; December 2026", "1 package, 6 oz total; segment count and material not stated",
          "https://www.horizonhobby.com/product/self-stick-weight-6-oz/HAN3626.html",
          "Direct official US retailer page opened 2026-10-25; price and backorder month are explicit.",
          "One 170 g package covers the 69 g simulated nose lead; the surplus is not credited."),
]


def line(line_id, inventory, notes, kind="estimated", observation=None, quantity=1, constituents=None):
    row = {"id": line_id, "quantity": quantity, "physical_inventory_ids": inventory, "evidence_kind": kind}
    if observation:
        row["price_observation"] = observation
    if constituents:
        row["price_constituents"] = [{"offer_id": o, "quantity": n} for o, n in constituents]
    row["notes"] = notes
    return row


AIRFRAME = ("No USD airframe-only kit or X8 spare part was verified on 2026-10-25: the RobotShop complete kit "
            "($507.41, backorder) does not itemize its contents and the UK airframe kit is priced in GBP and sold out.")
LINES = [
    line("wing_left", ["wing_left"], f"Unpriced left EPO wing panel with winglet and elevon. {AIRFRAME}"),
    line("wing_right", ["wing_right"], f"Unpriced right EPO wing panel with winglet and elevon. {AIRFRAME}"),
    line("body_main", ["body_main"], f"Unpriced painted EPO centre body, hatch and root ribs. {AIRFRAME}"),
    line("spars_main", ["spars_main"], "Unpriced carbon wing spars and joiners. Kit inclusion and tube dimensions were not verified; the physics estimates two tubes of about 1.3 m."),
    line("motor_main", ["motor_main"], "SunnySky X3530 V3 520KV at ReadyMadeRC ($74.99, in stock) is a price proxy for the simulated 520 Kv outrunner, not its installed identity. The package includes an X mount and the propeller collet adapter.",
         kind="price_proxy", observation=MOTOR),
    line("propeller_main", ["propeller_main"], "APC LP12060EP 12x6 pusher ($4.87 at ReadyMadeRC, 8 left) matches the simulated propeller. This line prices the blade only; the adapter in the physical row comes with the motor package and is not billed twice. A propeller strike replaces this line only.",
         kind="exact_product_price", observation=PROP),
    line("motor_mount", ["motor_mount"], "Unpriced plywood/plastic pusher mount plate; no separate X8 mount price was verified. The motor's X bracket is a different part."),
    line("esc_main", ["esc_main"], "Hobbywing Skywalker V2 3-7S 60A ($41.99 at RaceDayQuads, in stock) is a price proxy for the simulated 60 A ESC.",
         kind="price_proxy", observation=ESC),
    line("flight_controller", ["flight_controller"], "Matek H743-Wing V3 ($130.99 at RaceDayQuads, sold out) is a price proxy for the simulated 30 g autopilot; the installed product is unknown.",
         kind="price_proxy", observation=FC),
    line("receiver_telemetry", ["receiver_telemetry"], "Composite estimate for the combined receiver and telemetry radio row: one RadioMaster RP1 V2 ELRS receiver plus one Holybro SiK V3 915 MHz set. Holybro sells the radio only as an air-and-ground pair, so replacing the onboard module costs the set; the ground module is not onboard and earns no salvage credit. Proxies, not installed identities.",
         constituents=[(RX, 1), (TELEMETRY, 1)]),
    line("gps_compass", ["gps_compass"], "Holybro M10 GPS with IST8310 compass and carbon mount ($43.99, 32 g) is a price proxy for the simulated 30 g GPS and compass.",
         kind="price_proxy", observation=GPS),
    line("fpv_camera", ["fpv_camera"], "DJI O4 Air Unit ($139.99 at RaceDayQuads, in stock) is a price proxy for the simulated 30 g FPV camera and VTX; its 9 g mass and 3.7-13.2 V input differ from the modeled unit. Goggles are excluded.",
         kind="price_proxy", observation=FPV),
    line("mapping_camera", ["mapping_camera"], "Unpriced mapping camera. The r4 ledger box (102 x 58 x 41 mm, 240 g) matches the published size and mass of the first-generation Sony RX100, an inference rather than an identification. No current new-condition USD offer was verified (B&H and Sony returned 403 or blocked fetching; listings found were used or open-box). Launch price about $650 in 2012 (historical)."),
    line("parachute_pack", ["parachute_pack"], "Fruity Chutes 7 lb (3.2 kg) fixed-wing recovery bundle ($402.27, 2 left) is a price proxy for the simulated 150 g pack; the 270 g bundle excludes the ejection spring and latch hardware.",
         kind="price_proxy", observation=CHUTE),
    *[line(f"servo_elevon_{side}", [f"servo_elevon_{side}"],
           f"{side.capitalize()} elevon servo. The r4 delivery names an Emax ES3054; Aloft Hobbies lists it at $11.50, in stock. Linkage and horn are unpriced.",
           kind="exact_product_price", observation=SERVO) for side in ("left", "right")],
    line("wiring_main", ["wiring_main"], "Unpriced wiring, connectors and hatch magnets; contents are not itemized."),
    line("nose_ballast", ["nose_ballast"], "Real lead ballast, not virtual balance: one Hangar 9 6 oz self-stick weight package ($9.99, backorder) covers the 69 g. It is usually recovered after a crash; the package surplus is not credited.",
         kind="price_proxy", observation=LEAD),
    line("battery_main", ["battery_main"], "Spektrum SPMX56S30 6S 5000 mAh 30C Smart G2 ($139.99 at Horizon, backorder January 2027) is a class price proxy for the simulated pack.",
         kind="price_proxy", observation=BATTERY),
    line("final_assembly_and_commissioning", [], "Unpriced X8-specific assembly, autopilot setup, balancing, commissioning and post-crash inspection labor. No transferable allowance assumed; not salvageable."),
]

# Each hull probe inspects the structural group it lies on and installed equipment along its load path: nose and
# forward-belly hits reach the FPV camera, nose lead and pack; the hatch and belly reach the bay; root hits the spars;
# tip and trailing-edge hits the elevon servo and spars. Advisory inspection only; it never asserts part failure.
FORWARD = ["body_main", "fpv_camera", "nose_ballast", "battery_main"]
BAY = ["body_main", "battery_main", "parachute_pack", "receiver_telemetry", "wiring_main"]
CONTACTS = {
    **{f"probe_nose{suffix}": FORWARD for suffix in ("", "_left", "_right", "_left_low", "_right_low")},
    "probe_canopy_front": FORWARD, "probe_belly_front": FORWARD,
    "probe_canopy": BAY, "probe_belly": BAY + ["flight_controller"],
    "probe_engine": ["motor_main", "motor_mount", "propeller_main", "body_main", "esc_main"],
    "propeller/propulsion_main": ["propeller_main"],
}
for side in ("left", "right"):
    CONTACTS[f"probe_wing_{side}_root_le"] = [f"wing_{side}", "body_main", "spars_main"]
    CONTACTS[f"probe_wing_{side}_bottom"] = [f"wing_{side}", "body_main", "spars_main"]
    CONTACTS[f"probe_elevon_{side}_te"] = [f"wing_{side}", f"servo_elevon_{side}"]
    for probe in ("tip_le", "tip_te", "fill_2"):
        CONTACTS[f"probe_wing_{side}_{probe}"] = [f"wing_{side}", f"servo_elevon_{side}", "spars_main"]
    for probe in ("top", "outer", "fill_1"):
        CONTACTS[f"probe_winglet_{side}_{probe}"] = [f"wing_{side}"]
CONTACTS = {key: list(value) for key, value in CONTACTS.items()}
PROPELLER_INSPECTION = ["motor_main", "motor_mount", "body_main"]


def priced_subtotal_minor():
    cents = {row["id"]: round(row["amount_usd"] * 100) for row in OFFERS}
    total = 0
    for row in LINES:
        if "price_observation" in row:
            total += row["quantity"] * cents[row["price_observation"]]
        for part in row.get("price_constituents", []):
            total += row["quantity"] * part["quantity"] * cents[part["offer_id"]]
    return total


def entry(source_sha):
    subtotal = priced_subtotal_minor()
    priced = sum(1 for row in LINES if row["physical_inventory_ids"] and ("price_observation" in row or "price_constituents" in row))
    bound = sum(1 for row in LINES if row["physical_inventory_ids"])
    return {
        "aircraft_id": ID,
        "status": "independent_partial_inventory_costing",
        "price_observations": [row["id"] for row in OFFERS],
        "replacement_total_minor": None,
        "missing": [
            "No USD airframe-only X8 kit or spare-part price was verified: wings, centre body, spars, motor mount and wiring remain unpriced. The RobotShop complete kit ($507.41, backorder, unitemized) is a package alternative and must not be added to the component lines.",
            "The mapping camera is unpriced: its ledger size and mass match a first-generation Sony RX100 (inference), and no new-condition USD offer was verified.",
            "Priced lines are 2026-10-25 commercial proxies or class matches, not verified installed hardware. The battery and nose weight were on backorder and the flight controller was sold out when observed.",
            "Assembly, autopilot setup and commissioning labor has no verified basis; no foam repair recipe applies to this aircraft yet.",
        ],
        "notes": f"Independent partial inventory costing of the X8 UAV build (X8-09), reviewed {OBSERVED}. Known priced subtotal ${subtotal / 100:,.2f} across {priced} of {bound} physical lines (incl. the $402.27 parachute bundle). This is not a complete-build or replacement amount. The finite-pack variant binds to this dossier through the physical signature.",
        "dossier": {
            "expected_source_sha256": source_sha,
            "lines": LINES,
            "contact_components": CONTACTS,
            "propeller_component_id": "propeller_main",
            "propeller_inspection_ids": PROPELLER_INSPECTION,
        },
    }


def _render(document):
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def _validate(source):
    inventory = [row["id"] for row in source["inventory"]]
    bound = [item for row in LINES for item in row["physical_inventory_ids"]]
    assert len(bound) == len(set(bound)), "an inventory row is bound twice"
    assert set(bound) == set(inventory), f"unbound {sorted(set(inventory) - set(bound))}, unknown {sorted(set(bound) - set(inventory))}"
    assert not any("virtual" in item for item in inventory), "virtual balance must be excluded, not priced"
    propulsion = source["propulsion"]
    contacts = set(source["crash_hull_ids"]) | {c["id"] for c in source.get("landing_gear", {}).get("contacts", [])}
    if isinstance(propulsion.get("propeller"), dict):
        contacts.add(f"propeller/{propulsion['id']}")
    assert set(CONTACTS) == contacts, sorted(contacts ^ set(CONTACTS))
    components = {row["id"] for row in LINES}
    for contact_id, targets in CONTACTS.items():
        assert targets and len(targets) == len(set(targets)) and set(targets) <= components, contact_id
    assert set(PROPELLER_INSPECTION) <= components
    offer_ids = {row["id"] for row in OFFERS}
    assert len(offer_ids) == len(OFFERS)
    for row in LINES:
        refs = [row.get("price_observation")] if "price_observation" in row else [p["offer_id"] for p in row.get("price_constituents", [])]
        assert set(refs) <= offer_ids, row["id"]
    # The pack variant must carry the same priced physical facts (BAT-13 registered-variant binding).
    sys.path.insert(0, str(ECON))
    import build_runtime
    pack = json.loads(PACK_SOURCE.read_text(encoding="utf-8"))
    assert build_runtime._physical_signature(pack, ID) == build_runtime._physical_signature(source, ID), \
        "the 6S pack variant changes priced physical facts; review it before relying on the registered-variant binding"


def main():
    source_bytes = SOURCE.read_bytes()
    _validate(json.loads(source_bytes.decode("utf-8")))

    prices_text = FLEET_PRICES.read_text(encoding="utf-8")
    prices = json.loads(prices_text)
    by_id = {row["id"]: index for index, row in enumerate(prices)}
    for row in OFFERS:
        if row["id"] in by_id:
            prices[by_id[row["id"]]] = row
        else:
            prices.append(row)

    costing_text = COSTING.read_text(encoding="utf-8")
    costing = json.loads(costing_text)
    costing["observed_on"] = max(costing["observed_on"], OBSERVED)
    new = entry(hashlib.sha256(source_bytes).hexdigest())
    fleet = costing["fleet"]
    current = [i for i, f in enumerate(fleet) if f["aircraft_id"] == ID]
    legacy = [i for i, f in enumerate(fleet) if f["aircraft_id"] == LEGACY_ID]
    if len(current) > 1 or len(legacy) > 1 or (current and legacy):
        sys.exit("ambiguous MoonRunner costing entries; resolve the duplicate without discarding records")
    if current or legacy:
        fleet[(current or legacy)[0]] = new
    else:
        index = next(i for i, f in enumerate(fleet) if f["aircraft_id"] == "turbo-lumber-evolution") + 1
        fleet.insert(index, new)

    outputs = {FLEET_PRICES: (prices_text, _render(prices)), COSTING: (costing_text, _render(costing))}
    if "--check" in sys.argv:
        stale = [path.name for path, (old, rendered) in outputs.items() if old != rendered]
        if stale:
            sys.exit(f"X8 costing entry is stale in {', '.join(stale)}: run research/skywalker-x8/X8-09/costing_entry.py")
        print("X8 costing entry and price observations current")
        return
    for path, (_, rendered) in outputs.items():
        path.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"wrote the {ID} costing entry ({len(LINES)} lines, {len(CONTACTS)} contact mappings, "
          f"{len(OFFERS)} offers, known subtotal {priced_subtotal_minor()} cents)")


if __name__ == "__main__":
    main()
