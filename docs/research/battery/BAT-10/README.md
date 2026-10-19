# BAT-06…13 — `pack_ecm` runtime, aircraft contract, session integration, ESC cutoff and the Timber pack

2026-10-19 · **Status:** software verified. Physical validation (BAT-27/28) and Gate P (BAT-29) remain open. The class pack values are estimates (see limits). Plan: [battery realism](../../../plans/battery-realism.md). Normative text: [BAT-04 specification](../BAT-04/specification.md). Data: [BAT-05](../BAT-05/README.md). Presentation: [BAT-15](../BAT-15/README.md).

## Delivered

| Step | Files | What it does |
| --- | --- | --- |
| BAT-04 | `app/physics/battery/battery_data.gd` | Strict loader for `openrc-battery v1` packs and `openrc-cell-template v1` templates: SHA-256 pins, closed keys, quantity form, monotone OCV, capacity normalization |
| BAT-06/07 | `app/physics/battery/pack_ecm.gd` | The law of spec §4: average cell plus one weakest cell, K RC branches, bilinear (SOC, T) tables, EL2a's closed-form motor/bus solve, lumped temperature with still-air and √v forced convection, ESC voltage filter; compact stage path |
| BAT-11 | `app/physics/battery/esc_supervisor.gd` | Spec §6: cell detection at connection, soft/hard/off cutoff with debounce and ramp, `throttle_reset` or `latched` recovery |
| BAT-09 | `app/physics/aircraft_data.gd`, `aircraft-contract-v2.json`, `aircraft-modules-v1.json`, `build_schema.py` (regenerated v2 schema), `parameter_register.py` (regenerated AS-01 register), `docs/AIRCRAFT_CONTRACT.md` | Battery kind `pack_ecm`, `capabilities.energy: pack_ecm`, required `propulsion.esc.low_voltage_cutoff`, mount check on authored v2 inventory, v1 refusal |
| BAT-10 | `app/sim/flight_session.gd`, `app/sim/trace.gd`, `app/physics/propulsion.gd`, `app/failures/catalog.gd` | Continuous block of spec §5, stage-local ambient temperature and bay airflow, accepted-endpoint supervisor, checkpoint v6 with `electric_law` `electric-pack-ecm-coupled-events-v1`, trace `openrc-trace v13` pack columns, launch stiffness guard |
| BAT-13 | `research/timber/tt07/derive_physics.py` → `app/data/aircraft/battery/turbo_lumber_evolution_4s_pack.json`; `aircraft_catalog.gd` (`battery_data`, battery modes); `main.gd` (`--battery=ideal|pack`); `app_root.gd`, `ui/home.gd` (flight-details choice) | The same Timber airframe, inventory and id with the 4S 3200 LiPo class pack and an estimated Avian-class soft cutoff |

## Proof

| Check | Result |
| --- | --- |
| `test_battery_pack_ecm.gd`: parity with EL2a at K = 0 (1e-12), analytic RC charge-up under RK4, energy closure with two branches, thermal steady state, bilinear clamping, weakest cell, ESC limit, exhaustion and left limit, refusals | 84 checks, 0 failed |
| `test_battery_esc_supervisor.gd`: validation mutations, detection (incl. a 4S misdetected as 3S at 3.2 V/cell), debounce at sample 120 of 1/240 s, ramp to 50 % at 3 s, hard cut, recoveries, off | 36 checks, 0 failed |
| `test_battery_data.gd`: all 8 shipped packs load with their pinned templates; path traversal, stale hash, missing and malformed pins refused; Timber pack aircraft passes contract and modules; 9 aircraft mutations refused; LVC refused on a fixed bus | 52 checks, 0 failed |
| `test_battery_session.gd`: catalog modes, identical mass/inertia/id to the ideal Timber, layout before wheel speeds, 4 cells detected, sag and recovery, heating, charge budget, exact replay on a fresh owner, wrong law refused, reset, trace v13, soft cut ramps to 50 %, located exhaustion exactly once with LVC off, stiffness and filter guards, aged weak cell | 43 checks, 0 failed |
| `test_ui_battery_mode.gd` and `test_overlay_battery_flight.gd` (product route `--aircraft=turbo-lumber-evolution --battery=pack`) | 9 and 10 checks, 0 failed |
| BAT-06 independent oracle: `research/battery/bat-06/law_probe.gd` (1 200 seeded states on three shipped packs) against `research/battery/ecm_reference.py` | max relative error 2.7e-15 (rates), 7.7e-16 (currents), 1.9e-16 (bus voltage); 0 refusal mismatches |
| Unchanged behaviour: `test_electric_supply` 95, `test_electric_battery_data` 67, `test_electric_battery_session` 103, `test_electric_session` 86, `test_electric_battery_step` 63, `test_electric_propulsion` 20, `test_electric_runway` 177, `test_aircraft_contract` 2 946, `test_aircraft_modules` 69, `test_trace` 37, `test_aircraft_catalog` 100 checks | 0 failed in each |
| Home and modal UI: `test_ui_home`, `test_ui_home_layout`, `test_ui_home_start_layout` (44), `test_ui_aircraft`, `test_home_presentation`, `test_ui_home_legend` (23), `test_ui_modal_responsive` (560 cases), `test_ui_pause`, `test_ui_help`, `test_ui_settings_integration` | all pass |
| Generators: `build_batteries.py --check` (127/127 input hashes), `derive_physics.py --check` (the ideal Timber file is byte-identical, sha256 `0fa617d8…`), `build_schema.py --check`, `parameter_register.py --check`; `check_transcendentals.py` | current; pass |

`app/test.sh` now runs the generator check, the reference tests and the oracle comparison (`== BAT-05/06` block); the GDScript tests run in its unit loop.

## Session numbers (software, Timber pack, ISA, no pilot)

From `research/battery/bat-13/pack_probe.gd`, airborne trimmed start:

| Moment | Pack V (OCV) | Current | Cell avg | T | Used | ESC |
| --- | --- | --- | --- | --- | --- | --- |
| Start, trimmed throttle | 16.54 V (16.62) | 2.9 A | 4.14 V | 288.15 K | 0 mAh | normal |
| Full throttle 2 s | 15.43 V (16.59) | 41.9 A | 3.88 V | 288.44 K | 25.5 mAh | normal |
| Idle 4 s later | 16.55 V (16.59) | 0.3 A | 4.14 V | 288.44 K | 25.8 mAh | normal |
| 15 % pack, full throttle, 41.5 s | 12.80 V (13.76) | 28.5 A | 3.21 V | 290.25 K | 308 mAh | debounce |
| Soft cut reaches 50 % at 45.0 s | 13.42 V (13.71) | 2.8 A | 3.36 V | 290.34 K | 323 mAh | soft_cut |

The full-throttle current of about 42 A agrees with TT-07's 38 A static estimate. The sag then recovers within seconds through the 37 s RC branch. These numbers show the mechanisms work. They are not a Timber measurement.

## Cost

The VM was shared (load average 24 on 12 logical CPUs), so whole-session wall times were not usable: `research/battery/bat-10/bench.gd` measured 5.0–6.5 ms per tick for every case.

The interleaved law-only measurement (`research/battery/bat-10/law_cost.gd`) is less sensitive to load:

| Law path | Median per call |
| --- | --- |
| EL2a `ElectricSupply.evaluate_dynamics` | 50.9 µs |
| `PackEcm.evaluate` (compact) | 58.7 µs |

That is ×1.15, about +31 µs per four-stage tick. The session adds one atmosphere lookup per stage for the ambient temperature. Gate P was already open on the battery route (EL2a-P1: 558–562 µs). BAT-29 must still measure the whole session on an idle target host. The owner made `pack` the default before that measurement (see the last section).

## Defects found and fixed during integration

- **Mount check.** The v2 → internal conversion (`legacy_v1_input`) drops inventory ids. The mount check was therefore moved onto the authored v2 data, and `pack_ecm` is refused in historical v1 files.
- **Stiffness guard order.** The launch stiffness guard read `capacity_ah` because `has_dynamic_battery` now includes `pack_ecm`. The `pack_ecm` branch is now tested first.
- **Comparator index.** The first oracle comparison read the ESC phase as the limit (index `size + 1`). With the index fixed, the agreement is at rounding level.
- **Timer rounding.** The supervisor's debounce fired one sample late, because 120 × (1/240) s < 0.5 s in float64. A 1 ns timer tolerance is now part of the spec.
- **Home layout.** A Home flight-card button overflowed the collapsed Timber page by 76 px (`test_ui_home`). The battery choice moved into the flight details disclosure.
- **Located events.** `sim.last_events` holds only the last tick's events. The session test now listens to `events_located`.

## Limits

- **ESC profile.** The Avian-class cutoff (3.2 V/cell, 0.5 s debounce, 0.1 s filter, auto detection at 4.30 V/cell, throttle reset) is estimated. Only the 50 %/3 s soft ramp comes from the manual.
- **LiPo class.** The cell shape comes from a 1.1 Ah consumer pouch cell at 25 °C. The temperature dependence is borrowed from the HG2 NMC Arrhenius fit. Resistance is anchored at an estimated 5 mΩ per cell for 3.2 Ah. The template data floor is 3.00 V loaded (3.18 V rested), so deeper discharge is not modelled and exhaustion disconnects there.
- **Constant auxiliary current.** It is 0.3 A, estimated: no BEC rail, servo load or brownout (BAT-12).
- **Not yet implemented.** One-quadrant ESC only (no regeneration, BAT-08); no pack hangar, stress or damage (BAT-20/21); no pre-flight pack choice beyond ideal/pack (BAT-18/19).
- **Not logged.** The HUD's radio-style sensor values are not in traces (BAT-15 limits).

## 2026-10-19 — the finite pack becomes the default (owner decision)

The owner asked for the finite pack as the default ("deja el default con batería finita"). `Catalog.default_battery_mode()` returns `pack` wherever an entry has `battery_data` and `ideal` otherwise; `main.gd` uses it when `--battery` is absent, Home starts from a `pack` preference that falls back to ideal on aircraft without pack data, and Natural Random/direct routes follow the same default. `--battery=ideal` and Home's choice keep the constant-voltage aircraft.

| Check | Result |
| --- | --- |
| Default Timber trace through `main` (v13) | `check_trimmed_flight.py` passes. It now reads pack traces: connected ESC-normal samples, `min(command, limit)`, charge budget, V × I, and an RPM-drift allowance of Kv·duty·ΔV_bus (1.22 rpm observed over 3 s against 1.64 rpm explained by a 5.6 mV sag) |
| `test_trace_acceptance.py` | Timber default asserts the pack law and v13; a `--battery=ideal` case keeps the fixed-bus checks; new pack-corruption test. 7 Timber and earlier-failing tests OK after a concurrent import-cache rebuild had broken a full run |
| Frame-rate invariance (`run_fixed_step.gd`, TT-08) | identical checkpoint hash at 30 and 144 fps with the default pack |
| `test_e2e_input`, `test_e2e_radio` | expectations updated to the pack law; pass |
| `test_atmosphere_column_cli.py` | its fixed-bus electric family now passes `--battery=ideal`; 4 tests OK |
| `test_ui_battery_mode` (12), `test_overlay_battery_flight` (12), `test_aircraft_catalog` (100), `test_ui_home`, `test_ui_runway`, `test_start_choice` (36), `test_pilot_trim` (110), `test_rates` (41), `test_engine_sound` (12), `test_natural_random_flight` (576), `test_crash_wreck` (277), `test_failure_shutdown` (206), and the render/shadow/smoke/economy tests that fly the Timber | pass |

Limit: `check_atmosphere_trace.py` reads v11 standard-column traces only. A pack flight in a vertical atmosphere is a v13 trace, so that reader does not cover it yet.
