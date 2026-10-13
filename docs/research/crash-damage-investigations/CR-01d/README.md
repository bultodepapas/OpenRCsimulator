# CR-01d — Named crash-hull points

2026-10-13 · **Status:** implemented. **Serves:** [crash realism plan](../../../plans/crash-realism.md) §3.2, decision D1. Closes the CR-01 component-label gap; crossing-time kinematics remain open.

## What changed

- **Contract.** `aircraft-contract-v2.json` allows an optional top-level `crash_hull_components`: an array of at least four names from a closed vocabulary.

  `left_wing_tip`, `right_wing_tip`, `spinner`, `propeller`, `nose`, `tail_end`, `left_stab_tip`, `right_stab_tip`, `fin_top`, `canopy`, `belly`.

  [build_schema.py](../../../../research/aircraft-standardization/build_schema.py) types the field from that rule, and the [schema](../../../../app/data/schema/openrc-aircraft-v2.schema.json) is regenerated. The field is not a quantity (`{value, unit, kind, source}`); its source is the hull's own source. [AIRCRAFT_CONTRACT](../../../../AIRCRAFT_CONTRACT.md#physical-modules-and-parameter-effects) documents it.
- **Loader.** [aircraft_data.gd](../../../../app/physics/aircraft_data.gd) returns `model.crash_hull_components`. It is empty when the field is absent, and refused when the length differs from the hull or a name is unknown, on both the v2 and legacy paths. No force, detector or trim reads it.
- **Data.** Every aircraft names every point: 93 points over nine files, none unnamed ([table](../../../../research/crash-damage/cr-01d/labels.md)).
  - Extra, P-51, Avanti and Timber gain the list from their `derive_physics.py` generators.
  - The Stik and the four synthetic electric Stiks are canonical v2 sources (`migrate.py --check-known`), so the list was inserted with an order-preserving JSON rewrite.
- **Presentation.**
  - [director.gd](../../../../app/render/crash/director.gd) `component_for()` uses the struck point's name and reports `component_is_estimate = false`. Without names it keeps the marked geometric estimate. Gear overtravel stays `gear`.
  - The tank-rupture rule now tests the severity component group (fuselage, engine, propeller), so named `nose`, `belly` and `spinner` hits still count as central.
  - [wreck.gd](../../../../app/render/crash/wreck.gd) releases the propeller first for a `spinner` hit.

## Timber platform drift

The committed `turbo_lumber_evolution.json` was already stale on this Linux host before this step. `tt07/derive_physics.py --check` fails at HEAD under Python 3.12 and 3.13. Regenerating here changes four floats in their last digits (relative ≤ 9e-16):

- `balance.plan_cg[2]`
- `inventory[12].mass`
- `inventory[12].position[0]`
- `thrust_line_offset[2]`

To avoid a platform-only physics change, the committed values were kept. Only the generator's new `crash_hull_components` list was inserted at the generator's key position. A script asserted that this equals the regenerated output except those four leaves. **Owner action:** run `python research/timber/tt07/derive_physics.py --check` on the machine that produced the committed file; it should pass with the updated generator.

## Evidence

**Tests.** [test_crash_hull_labels.gd](../../../../app/tests/test_crash_hull_labels.gd): **112 checks**.

- The loader vocabulary equals the contract's.
- Every data file loads and names every point.
- Geometry is checked independently of any copied list:
  - left/right names sit on the matching side;
  - wing-tip names sit at |y| ≥ 0.45 × span, i.e. ≥ 90 % of the semi-span;
  - centreline names sit on the centreline;
  - tail names are aft of the CG and nose names forward of it;
  - the fin top is the highest hull point;
  - the canopy is above the CG and the belly below it.
- Rejections: short list, unknown name (contract and legacy path), non-string, non-array. Absent stays valid.
- `component_for()` cases are covered: named, scenery, gear, fallback, out of range and unknown.
- The severity group for every name is checked, and the wreck release matches for tip, spinner, stab and fin.

**Mutations.** [mutate.py](../../../../research/crash-damage/cr-01d/mutate.py), log in [mutations.log](../../../../research/crash-damage/cr-01d/mutations.log): **11/11 killed**.

- Data mutants: swapped left/right tips, swapped spinner/tail, swapped fin/canopy, a stab named as a tip, a belly named canopy.
- Loader mutants: no length check, no vocabulary check, vocabulary drift.
- Director mutants: labels ignored, an out-of-range index trusted.
- Wreck mutant: spinner rule removed.

The first run found four survivors; the test was strengthened until each was killed. The out-of-range mutant raises an engine error, which `app/test.sh` fails.

**Unchanged suites.** Crash, wreck, effects, audio, pose, snapshot, integration, aircraft data (87), aircraft contract (2,159), catalog, Timber data, scenery destruction and collision session all pass.

These pass too: `build_schema.py --check`, `parameter_register.py --check`, `migrate.py --check-known`, the structural preflight of all nine files, and the Extra, P-51 and Avanti `derive_physics.py --check`.

`research/aircraft-standardization/test_schema_v2.py` fails at HEAD as well. It expects exactly eight v2 files and predates the Timber file; it is not run by `app/test.sh`.

## Limits

- Hull points are sparse. A name says which hull vertex was nearest, not what broke.
- The P-51 lower propeller-quarter points sit off the centreline and are named `propeller`; they are excluded from the centreline check by design.
- The AS-05 authoring template predates the field. It remains valid because the field is optional.
