# FUEL-03 — Fuel-system contract (2026-10-19)

Evidence for step FUEL-03 of the [fuel, mass and balance plan](../../../plans/fuel-mass-balance.md). The contract now carries tanks, the balance fuel state and a CG range; this addresses findings F03, F09 and F11. Everything is opt-in. No aircraft declares the block yet, so every trajectory is unchanged. The fleet migration is FUEL-05.

## Contract

- **`fuel_system.tanks[]`:** each tank has:
  - `id`;
  - `fuel`, a blend id from the [fuel registry](../FUEL-02/README.md);
  - `liquid_inventory_id` and `shell_inventory_id`;
  - `capacity` and `unusable` in litres;
  - `pickup`: `clunk`, `felt_clunk`, `fixed` or `hopper`;
  - `feed`: `suction_muffler`, `pumped_diaphragm` or `ecu_pump`.

  The binding by inventory id follows the battery track's `mount_inventory_id` (BAT-09).
- **`balance.fuel_state`:**
  - `as_inventory`, the default and today's rule: the plan CG equals the authored inventory CG.
  - `empty_tanks`: the plan CG equals the inventory CG without any tank liquid, which is the manuals' balance condition. The body datum stays the authored inventory CG (D2).
- **`balance.cg_range`** (`forward`, `aft`, m): the plan CG must lie inside it at the declared fuel state.
- **Loader rules** (`AircraftData._fuel_system`):
  - combustion energy only;
  - unique tank ids and a known blend;
  - feed consistent with the family (glow → suction, gasoline → pumped diaphragm, kerosene → ECU pump);
  - liquid and shell items exist, are distinct and are used once;
  - the liquid's `energy_source` matches the family, and the shell carries no energy;
  - 0 < capacity and unusable < capacity;
  - liquid mass ≤ capacity × density, and the liquid box holds the capacity;
  - no liquid-fuel item outside a tank;
  - `empty_tanks` needs tanks and a matching dry CG;
  - range forward < aft and containing the plan CG.
- **Model output:** `model.fuel_system`, format `openrc-fuel-system v1`. It carries the fuel state, the registry SHA-256, and per tank the family, density, capacity (m³ and kg), unusable kg, liquid mass, start fill, pickup and feed.

**Files:**
- `app/data/schema/aircraft-contract-v2.json` (rules and vocabularies);
- `research/aircraft-standardization/build_schema.py` and the regenerated `openrc-aircraft-v2.schema.json`;
- `parameter_register.py` and the regenerated AS-01 register (203 quantity paths);
- `app/physics/aircraft_data.gd` (additions only);
- [AIRCRAFT_CONTRACT](../../../../AIRCRAFT_CONTRACT.md) (three optional-input rows and the binding rules);
- the authoring template, which now carries a complete tank example;
- `research/fuel-systems/mass_balance_report.py`, which adds a full state from the declared capacity and compares only the physical content when it checks drift;
- tests `app/tests/test_fuel_system_contract.gd` and `research/fuel-systems/test_mass_balance_report.py`.

## Proof

- **[`test_fuel_system_contract.gd`](test_fuel_system_contract.log):** 27 checks, 0 failed.
  - The 15 current fixed-wing files load and declare no `fuel_system`.
  - A tank on the 61FX Stik loads. Capacity, unusable mass and start fill (0.6224) derive from litres × 856.92 kg/m³.
  - The block changes no mass, CG or inertia.
  - `empty_tanks` refuses the wet plan CG (off by 9.6 mm) and accepts the dry one.
  - The CG range applies at the declared state.
  - 19 refusals, each asserted by its own message.
- **Mutations** (disposable copy):

| Mutation | Result |
| --- | --- |
| Dry-CG check disabled | 1 check fails |
| Capacity check disabled | 1 check fails |

- **Fleet fingerprints:** [`fingerprints.json`](fingerprints.json). The SHA-256 of all 20 trajectories is identical with and without the FUEL-03 loader, contract and schema on the same tree.
- **Offline schema:** a fuel-system fixture validates against the generated JSON schema (`jsonschema` 4.26.0). An unknown pickup, a capacity in ml, an extra tank field, an empty tank list, an unknown fuel state, a range without `aft` and a zero capacity are each refused.
- **Generators:** `build_schema.py --check` and `parameter_register.py --check` are current.
- **Template:** valid against the schema, and the production loader accepts it with one tank (start fill 0.467). `test_physical_identity_sources.py` passes.
- **Regression** ([`regression.txt`](regression.txt)): 18 of 20 focused Godot programs pass, among them aircraft contract (2950 checks), aircraft data, catalog, physical identity, propulsion runtime, package proofs, battery data and session, the Workshop compiler, descriptor, integration and trial, and the glow and FUEL tests.
- **Known failures:**
  - `test_aircraft_modules` and `test_crash_energy` fail the same way without FUEL-03. The cause is the battery track's new `turbo_lumber_evolution_4s_pack.json` (BAT-13).
  - Of the Python schema suite, `test_contract.py` and `check_mutations.py` pass. `test_schema_v2.py` fails only on that same extra file.

## Limits

- **Single-state jet balance:** a jet's "full hopper, empty main tank" balance needs a per-tank state; it arrives with AV-10 when the Ventage Jet declares its tanks.
- **No consumer yet:**
  - The glow installation still uses its liquid item's mass as capacity.
  - The feed fill still counts against the initial fuel.
  - Start-fill selection, unusable residue and pickup use belong to FUEL-05, FUEL-07 and FUEL-09.
