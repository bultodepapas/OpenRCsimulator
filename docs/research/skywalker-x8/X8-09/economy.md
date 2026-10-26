# X8-09: repair economics of the X8 flying wing

Built 2026-10-25 for the [X8 plan](../../../X8-PLAN.md) under the [damage and cost dossier contract](../../../AIRCRAFT_CONTRACT.md#damage-and-cost-authoring-dossier). These are commercial price estimates for a fictional build. They do not qualify hardware, fit or crash strength.

## What is generated

[costing_entry.py](../../../../research/skywalker-x8/X8-09/costing_entry.py) writes the `skywalker-x8` independent dossier into `research/crash-economics/aircraft-costing.json`. It also writes 13 dated offers into `research/crash-economics/price-research-fleet.json`. It pins the SHA-256 of the current physics bytes, and it checks four things: every inventory row is bound exactly once, every hull probe and the propeller strike is mapped, all offer references resolve, and the 6S pack variant has the same priced physical signature.

- 20 lines: 19 physical rows plus unpriced assembly labor. There is no virtual balance. `nose_ballast` is real lead and is priced as hardware.
- The pack variant `battery/skywalker_x8_6s_pack.json` gets no entry of its own. As with the Turbo Lumber 4S pack, the runtime binds it as the catalog's `registered_variant` through the physical signature.
- 29 contact mappings cover 28 hull probes plus `propeller/propulsion_main`. The X8 has no gear contacts. A probe opens inspection of:
  - the structural group it lies on;
  - equipment along its load path:
    - nose and forward belly or canopy: FPV camera, nose lead and pack;
    - hatch and belly: pack, parachute, receiver, wiring and, for the belly, the flight controller;
    - wing roots: body and spars;
    - elevon trailing edges and tips: that side's servo, plus the spars for tips;
    - winglets: the wing only;
    - `probe_engine`: motor, mount, propeller, aft body and ESC.
- Propeller strike: `propeller_main` (blade only) is replaced. Motor, motor mount and body are inspected.
- The mapping is advisory inspection only. It does not infer damage.

## Prices observed 2026-10-25 (USD, before tax and shipping)

| Line | Offer | Unit USD | Stock | Evidence kind and limits |
| --- | --- | ---: | --- | --- |
| `motor_main` | [SunnySky X3530 V3 520KV](https://www.readymaderc.com/products/details/sunny-sky-x-series-v3-x3520-brushless-motor-520kv), ReadyMadeRC | 74.99 | In stock | Proxy. 219 g vs 190 g modeled. Includes X mount and prop collet adapter. The page's URL slug and stator height disagree with its title. |
| `propeller_main` | [APC LP12060EP 12x6 pusher](https://www.readymaderc.com/products/details/apc-12x6ep-pusher-prop), ReadyMadeRC | 4.87 | 8 left | Exact match for the simulated prop. Blade only; the adapter comes with the motor. apcprop.com returned 403. |
| `esc_main` | [Hobbywing Skywalker V2 3-7S 60A](https://www.racedayquads.com/products/hobbywing-skywalker-60a-2-6s-ubec-wing-esc), RaceDayQuads | 41.99 | In stock | Proxy |
| `flight_controller` | [Matek H743-Wing V3](https://www.racedayquads.com/products/matek-h743-wing-v3-flight-controller), RaceDayQuads | 130.99 | Sold out | Proxy. 30 g, matching the modeled mass. |
| `receiver_telemetry` | [RadioMaster RP1 V2](https://radiomasterrc.com/products/rp1-expresslrs-2-4ghz-nano-receiver) $18.99 + [Holybro SiK V3 915 MHz set](https://holybro.com/products/sik-telemetry-radio-v3) $58.99 | 77.98 | Available | Composite estimate. The radio is sold only as an air-and-ground pair, and the ground module is not onboard. |
| `gps_compass` | [Holybro M10 GPS](https://holybro.com/products/m10-gps), IST8310 | 43.99 | Available | Proxy. 32 g with carbon mount. |
| `fpv_camera` | [DJI O4 Air Unit](https://www.racedayquads.com/products/dji-o4-air-unit), RaceDayQuads | 139.99 | In stock | Proxy. About 9 g vs 30 g modeled, with 3.7–13.2 V input. Walksnail Avatar HD Kit V2 was sold out ($159.00 Caddx, discontinued; $191.99 RaceDayQuads). |
| `parachute_pack` | [Fruity Chutes fixed-wing bundle 7 lb (3.2 kg)](https://shop.fruitychutes.com/products/fixed-wing-recovery-bundle-7lbs-3-2kg-15fps) | 402.27 | 2 left | Proxy. 270 g vs 150 g modeled. No ejection spring or latch. Rated mass covers the about 3.13 kg inventory. |
| `servo_elevon_left`, `servo_elevon_right` | [EMAX ES3054](https://alofthobbies.com/products/emax-es3054-servo-3-5kg-48-6-oz-in-13-sec-17-grams), Aloft Hobbies | 11.50 each | In stock | Exact: the r4 delivery names the ES3054. |
| `nose_ballast` | [Hangar 9 self-stick weight 6 oz](https://www.horizonhobby.com/product/self-stick-weight-6-oz/HAN3626.html), Horizon | 9.99 | Backorder, Dec 2026 | Proxy. One 170 g package covers 69 g; material not stated. |
| `battery_main` | [Spektrum SPMX56S30 6S 5000 30C Smart G2](https://www.horizonhobby.com/product/22.2v-5000mah-6s-30c-smart-g2-lipo-battery-ic5/SPMX56S30.html), Horizon | 139.99 | Backorder, Jan 2027 | Class proxy |

Known priced subtotal: **$1,090.05** across 12 of 19 physical lines. This is not a build, replacement or total-loss amount.

### Unattached candidate

The [SonicModell Skywalker X8 2122 complete kit](https://www.robotshop.com/products/sonicmodell-skywalker-x8-2122-flying-wing-drone-fpv-complete-kit) is listed at RobotShop US for $507.41, available on backorder; the page showed a price-data stamp of 2026-10-14. It says it "includes a motor, an airframe, ESC, servos, etc." but itemizes nothing else. It is recorded as a package alternative and attached to no line, so the generator lists it as an unreconciled candidate.

## Unpriced, with reasons

| Line | Reason |
| --- | --- |
| `wing_left`, `wing_right`, `body_main` | No USD airframe-only kit or X8 spare part was verified. The [Unmanned Tech Shop kit](https://www.unmannedtechshop.co.uk/products/skywalker-x8-kit-2120mm-epo-fpv-wing) (Z98.0001) is GBP 259.49, sold out, and lists only the airframe, wing sections, fuselage and control surfaces. The RobotShop kit is unitemized. rcdrone.top returned 403. |
| `spars_main` | Kit inclusion and tube sizes were not verified. |
| `motor_mount`, `wiring_main` | No separate part or itemized contents. |
| `mapping_camera` | The r4 ledger box (102 × 58 × 41 mm, 240 g) matches the published size and mass of the first-generation Sony RX100. That match is an inference, not an identification. No new-condition USD offer was found: Sony and B&H blocked fetching, and the listings found were used or open-box. The 2012 launch price of about $650 is historical only. |
| `final_assembly_and_commissioning` | No labor basis. |

## Side effect: catalog snapshot date

The price catalog's snapshot date is the newest observation date, so the shared `observed_on` and the runtime `price_date` move from 2026-10-20 to 2026-10-25. Older offers keep their own dates; the [CR-38a audit](../../crash-damage-investigations/CR-38a/README.md) still ages them individually. The only test expectations that pinned the old snapshot date changed: two in `test_runtime_data.py` and one in `test_audit_prices.py`.

## Verification (2026-10-25)

| Command | Result |
| --- | --- |
| `python3 research/skywalker-x8/X8-09/costing_entry.py` then `--check` | Wrote 20 lines, 29 contact mappings, 13 offers and a subtotal of 109005 cents; the check passes |
| `python3 research/crash-economics/build_catalog.py` then `--check` | CR-28 OK |
| `python3 research/crash-economics/build_runtime.py` then `--check` | Sidecar current (11 aircraft routes) |
| `python3 research/crash-economics/test_runtime_data.py` | 30 tests OK (X8 added to the fleet sets) |
| `test_audit_prices.py`, `test_compare_prices.py`, `test_service_references.py` | 12, 13 and 7 tests OK |
| `audit_prices.py --as-of 2026-10-25` | 111 observations within the review window. X8: 12 of 20 rows priced, known 109005 cents, coverage incomplete |
| `app/tests/test_economy_catalog.gd` | 94 of 96 pass, including route load for `skywalker-x8`. The two failures are hard-coded fleet counts (10 → 11 routes, 6 → 7 incomplete), which are outside this step's writable paths. |
| Disposable Godot probe | The pack loads with `binding = registered_variant`, the same components and contacts as ideal mode, and the flown pack hash. A Timber route cannot borrow the X8 pack hash. |

## Refresh after a physics regeneration

```sh
python3 research/skywalker-x8/X8-09/costing_entry.py
python3 research/crash-economics/build_catalog.py
python3 research/crash-economics/build_runtime.py
python3 research/crash-economics/build_runtime.py --check
```

The script re-pins the SHA-256 of the current bytes, including CRLF bytes. It fails if inventory IDs, hull IDs or the pack's priced physical facts drift. When it fails, review the BOM before changing the script.
