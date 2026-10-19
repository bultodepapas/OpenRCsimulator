# FUEL-01 — Byte-identical repairs and mass/balance baseline (2026-10-19)

Evidence for step FUEL-01 of the [fuel, mass and balance plan](../../../plans/fuel-mass-balance.md). No aircraft physics changed: the 20 fleet trajectory fingerprints are byte-identical before and after.

## Changes

| Part | Finding | Change | Files |
| --- | --- | --- | --- |
| a | F09: the glow generator edited records by array position (`inv[0]`, `inv[1]`, `inv[2]`, `inv[6]`, `inv[-1]`) | Records are selected by their stable ids (`item_engine_main`, `item_muffler_main`, `item_propeller_main`, `item_fuel_main`, `item_balance_mass_virtual`) | `research/glow-engines/build_installations.py`, new `test_build_installations.py` |
| b | F04: the HUD converted fuel mass with a fixed 0.8 g/mL | Glow telemetry publishes `fuel_density_kg_m3` (from the installed profile) and `fuel_volume_m3`; the HUD shows that volume | `app/physics/glow/flight.gd`, `app/main.gd`, `app/tests/test_aircraft_catalog.gd` |
| c | F06: the calibration mirror metered 2T premix on trapped air | Premix is metered on delivered air, as in `two_stroke.gd`; trapping limits only the burned charge. Reports regenerated; NITRO-61FX §5 corrected | `research/glow-engines/calibration_report.py`, `test_calibration_report.py`, `docs/research/glow-engines/NITRO-2T/` and `NITRO-4T/calibration_report.json`, `NITRO-61FX/README.md` |
| d | F09: the template's fuel item had no `energy_source` | Tagged `glow_fuel` | `research/aircraft-standardization/template/openrc-aircraft-v2.template.json` |
| e | Baseline | `mass_balance_report.py`, the neutral-point register and the stored report; the check runs in `app/test.sh` | `research/fuel-systems/` |

## Proof

**Byte identity:**
- `python3 -I research/glow-engines/build_installations.py --check` reports all 10 generated files (5 installations, 5 aircraft) current, so the output is byte-identical after (a).
- `fingerprint_vehicles.gd` (960 airplane ticks with cut variants, helicopter 1200 ticks and the ground vehicle; 20 trajectories) gives the same SHA-256 on both copies, `81c3e91c…`. Stored as [`fingerprints.json`](fingerprints.json).
- The comparison ran on two disposable copies of the same working tree. The baseline copy had the FUEL-01 files restored from `HEAD` `97136354`.

**Focused tests on the candidate** ([`checks.txt`](checks.txt)), all with 0 failures:

| Test | Checks |
| --- | ---: |
| `test_aircraft_catalog` (includes the new HUD volume checks) | 100 |
| `test_glow_session` | 140 |
| `test_glow_trace` | 282 |
| `test_glow_fuel_feed` | 28 |
| `test_glow_flight_physics` | 82 |
| `test_glow_installation` | 226 |

**Python checks:**
- `test_calibration_report.py`: 5 tests.
- `test_build_installations.py`: 1 test, 3 variants.
- `app/tests/test_ci_partitions.py`: 5 tests.
- Schema `check.py`: 14 aircraft pass.
- The template validates against the v2 schema (`jsonschema` 4.26.0, the pinned version).
- The production loader accepts the template: `AircraftData.load_file` returns `ok=true` with one `glow_fuel` item.

**Mutations** (each run on a disposable copy):

| Mutation | Detected by |
| --- | --- |
| HUD back to `fuel_kg / 0.0008` | 2 HUD checks fail (55AX and FS-64V) |
| Trapping restored in the mirror's delivered air | 6 subtests fail (2 profiles × 3 rpm) |
| Generator back to positional access (`HEAD` file) | Reordered-inventory test fails in all 3 variants |
| Stik neutral point moved to 0.125 m | The report gate fails 6 Stik files at the empty state |

**Report diff after (c):**
- 2T: only `delivered_premix_kg_s`, `delivered_premix_ml_min` and `unburned_premix_kg_s` changed. Burned fuel, torque and power were unchanged.
- 4T: no values changed beyond 6 floats at 1e-12 relative.
- Both reports also refreshed their recorded installation and aircraft SHA-256 values. Those were already stale against files changed by later commits.

**Corrected 61FX flows:** 38.8 / 46.0 / 58.1 ml/min at 10,976 / 12,550 / 16,000 rpm. These equal the [FUEL-00](../FUEL-00/README.md#4-glow-consumption-and-feed) runtime mirror.

**Baseline** (`research/fuel-systems/FUEL-01/mass_balance_baseline.json`, 14 aircraft):
- It reproduces FUEL-00's declared and empty CG and static margins exactly.
- Every registered margin is positive. The minimum is 0.3 % MAC (Stik FS-64V, empty), which is finding F01.
- Flags it raises: point-mass fuel on the base Stik, Extra and P-51; 20 inventory items without ids and fuel-named donor items on each synthetic electric Stik.

## Reproduce

```sh
python3 -I research/glow-engines/build_installations.py --check
python3 -I research/glow-engines/test_build_installations.py
python3 -I research/glow-engines/test_calibration_report.py
python3 -I research/glow-engines/calibration_report.py --write   # regenerates both dossier reports
python3 -I research/fuel-systems/mass_balance_report.py          # markdown table
python3 -I research/fuel-systems/mass_balance_report.py --check research/fuel-systems/FUEL-01/mass_balance_baseline.json
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_aircraft_catalog.gd
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/fingerprint_vehicles.gd -- --output=/tmp/fp.json
```

## Limits

- Software verification only. The neutral points in the register are repository estimates.
- The report has no full-tank state until capacities exist in the contract (FUEL-03).
- The HUD volume is exact for the profile's blend at its reference density; the blend density itself carries about ±2 % ([FUEL-00 §6.1](../FUEL-00/README.md#61-densities)).
