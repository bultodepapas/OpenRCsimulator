# Fuel qualification and extensions

The [fuel engineering standard](../FUEL-SYSTEM.md) is the authoritative operating and authoring guide. Runtime/data define implemented behavior. This plan owns only remaining qualification and extensions; the [original audit](../research/fuel-systems/FUEL-00-R1/README.md) and [completion evidence](../research/fuel-systems/FUEL-12/README.md) retain their dated results. Checked 2026-10-19.

## Implemented software scope

FUEL-00…08 provides registry/bindings, live fixed-datum mass, typed accepted samples, selected fill/reset, transactional native/JSON checkpoints, finite glow/gasoline/turbine adapters, residue and located exhaustion. FUEL-09 adds explicit glow pickup and separately identified pre-primed finite-line inventory with deterministic wet/dry, main/line and starvation transitions. FUEL-10 connects reserve warnings, accepted combustion state, traces and typed crash consumers. FUEL-11 separates supported Workshop tank capacity from dry mass and launch fill. FUEL-12 records matched command tapes and exact replay evidence. See the completion record for the checks actually run and their limits.

The implementation retains prescribed-fuel reference specimens and rejects unsupported consumption/delivery combinations. Software completion does not close physical calibration, future vehicle integration or every proposed Workshop feature.

## Remaining gates

| Owner and IDs | Required evidence or extension |
| --- | --- |
| Aircraft owners with FUEL-05 / VAL | Supply sourced CG ranges and neutral points where missing. The recursive report covers all catalog paths, while four synthetic electric fixtures deliberately lack qualified neutral points. `--qualify` must continue to expose missing evidence. Do not invent manufacturer limits or label estimates as measurements. |
| Physics / NITRO with FUEL-12 and G2 | Profile and reduce the same-stage feed/coupling cost, then qualify release headroom on an isolated target host. Current shared-host headless medians are about 4.1 ms/tick, close to the 4.167 ms budget at 240 Hz; some repeats exceed it. Functional/replay acceptance does not close this performance gate. |
| NITRO / AV / aircraft owners with FUEL-08/09 | Identify actual pickup and line dimensions, hopper liquid capacity/position and transfer/re-prime law before admitting those installations. Current Ventage consumes the main store directly; current glow aircraft retain line-free data. Synthetic line fixtures establish software conservation only. Slosh, foaming, thermal density and non-co-moving discharge require separate laws. |
| AE with FUEL-11 | Target-CG/ballast editing, installation-aware engine/airframe scaling and wider authoring controls retain the [Workshop plan](aircraft-editor.md) gates. Invalid or unsupported transforms cannot launch. |
| VAL with FUEL-13 | Empty/full weighing, CG and timed burn measurements for the identified installed build, calibrated instruments, uncertainty, held-out comparisons and pilot acceptance. Manufacturer capacity, estimated box geometry and borrowed engine curves do not satisfy this gate. |
| HELI / RCV with FUEL-14 | Adopt the shared inventory/sample contracts through each vehicle model with its own consumption, contacts, checkpoint/replay and backend gates. Fixed-wing completion does not imply rotorcraft or ground-vehicle integration. |
| SM / AS / AE with FUEL-08/09/11 | A physical smoke-fluid feature needs a separately typed fluid/store, installed hardware, density, capacity, fill, reserve and consumption law with mass/contact/exhaustion/replay tests. Current smoke presets remain visual; opacity and plume size are not ml or endurance. Empty show supply must not stop the engine. |

## Verification and maintenance

Run the owning schema, generator, module/descriptor, session and tooling checks in [TOOLS](../TOOLS.md). Inspect process status and engine errors. Keep source identities and declared layout/law versions with evidence. Exact baseline replay precedes any candidate comparison; report `solver_changed`, `complete`, initial-condition differences and unsupported migrations explicitly. Candidate/recovered outputs never establish exact equivalence or physical realism.

```sh
python3 research/fuel-systems/test_mass_balance_report.py
python3 research/fuel-systems/mass_balance_report.py --check research/fuel-systems/mass_balance_current.json --fail-on-drift
```

`--qualify` adds missing-neutral-point refusal; it is stricter than the reproducibility gate. Regenerate accepted reports/data only through source pipelines after reviewing intentional changes. Preserve valuable primary references under [FUEL-00](../research/fuel-systems/FUEL-00/README.md). Do not duplicate the current standard in dated evidence or other plans.
