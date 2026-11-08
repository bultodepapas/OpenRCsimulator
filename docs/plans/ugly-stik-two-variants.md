# Ugly Stik: two production variants and one test reference

2026-11-08 · **Status: proposed; research complete enough to select an initial electric candidate. No runtime migration implemented.**

Owner: fixed-wing physics and aircraft data, coordinating NITRO, EL/BAT, AS, AE, AFC, UI, US presentation and native-backend owners. Step IDs: **EL1e-STIK-00…08**, under the existing EL1e aircraft-integration work; this is not a new kernel or vehicle track. [Ownership registry](../README.md#tracks-plans-and-step-ids).

## Intended result

Keep exactly **two selectable, supported production Ugly Stik configurations** on the existing Jensen 60-inch airframe:

| Configuration | Canonical ID | Powertrain | Role |
| --- | --- | --- | --- |
| **Ugly Stick · MAX-61FX** | Preserve `stik-glow-61fx-2t` | O.S. MAX-61FX 2T, APC 12x6, finite glow fuel | Application default and canonical reference for all general fixed-wing regression, smoke, tooling and benchmark defaults. |
| **Ugly Stick · Electric 6S** | Proposed `stik-electric-6s` | Scorpion SII-4020-540KV, APC 13x8E, 6S 4000 mAh LiPo, finite `pack_ecm` energy | Powerful electric counterpart and reference for electric/battery integration tests. |

Retire the separate prescribed-fuel base, MAX-55AX and FS-64V from the production selector and supported ordinary launch routes. Historical records and specialized regression fixtures remain explicitly outside the product catalog. There must be no hidden third production Stik under a compatibility alias or developer-demo name.

“Reference for all tests” means every general airplane test/tool with an implicit Stik default uses the canonical 61FX fixture. It does not replace motor, battery, four-stroke, other-aircraft, helicopter or ground-vehicle tests with an incompatible specimen. Both production configurations keep their applicable contract, lifecycle and flight coverage.

Being the default does not promote an estimated engine to physically validated status. The 61FX currently uses a profile scaled from 55AX; retain that qualification and the existing Stik yaw/pull-up acceptance limits. [Glow guide](../GLOW-ENGINES.md), [pull-up investigation](ugly-stik-pullup.md).

## Electric installation decision

Adopt the Scorpion combination above as the implementation candidate. Use an airplane ESC rated for 6S and at least 80 A, with its exact revision and BEC pinned during installation authoring. The battery SKU, mass and fit remain open; 4000 mAh is the chosen initial capacity, not a measured pack model.

The [dated manufacturer-source comparison](../research/propulsion/ugly-stik-6s-selection-2026-11-08.md) records the motor choice, bench points, alternatives and missing measurements. It favors a 13-inch propeller with documented performance over immediately fitting a larger propeller. Preserve the common wing, tail, hinges and basic tricycle arrangement; change mounting or gear only if a documented fit study requires it.

Proposed screening targets, to be evaluated before integration:

- Recompute the complete ready-to-fly inventory; initially aim for 3.0–3.4 kg without inventing balancing mass to force a target CG.
- At the declared nominal bench condition, target at least 350 W/kg **electrical input** and 1.2 static thrust/weight. These are project goals for a powerful sport model, not achieved flight performance.
- Check loaded operation from fully charged 25.2 V through depletion, including voltage sag, cutoff and motor/ESC current limits. Do not treat nominal 22.2 V as a constant bus or motor ratings as implemented current limiting.
- Verify positive propeller clearance throughout the declared normal taxi/takeoff/landing envelope, including suspension compression and pitch. Record the minimum clearance and assumptions; do not infer fit from diameter alone.
- Check physical battery-bay fit, restraint, cooling, wiring, adapter, CG and inertia before freezing data. If a gate fails, revise the one electric installation and rerun its gates; do not add another catalog entry.

## Migration rules

### Preserve the donor and historical identities

The current [glow installation generator](../../research/glow-engines/build_installations.py) reads `jensen_ugly_stik_60.json` as a donor. The 61FX profile also depends on the 55AX source, and the Extra uses the shared glow pipeline. Removing a catalog entry must not delete those dependencies or silently change the Extra.

First preserve the donor source and generated identities. Then separate shared airframe inputs from installation inputs through their owning generators. Keep old prescribed-fuel data as an explicit regression/research fixture until all consumers are classified and migrated. Moving it out of production packaging is a separate, verified step: search old paths repository-wide, update live references, preserve historical records and check a fresh checkout/export. Never hand-edit generated JSON.

Freeze the old executable/source/data snapshot and existing goldens. Old `.orfl` recordings, checkpoints, Workshop packages and published evidence retain their original bytes, hashes and interpretation; they must never resolve to new physics just because an ID looks familiar.

The retired base ID also names the shared **visual family**. Keep `jensen-das-ugly-stik-60` as that family identity in bindings, manifests and paint compatibility. Audit the render adapter's default/no-argument construction and other consumers that currently resolve the family name through the catalog; route them through the explicit canonical configuration without requiring a third catalog entry.

### Define compatibility at each entry point

| Consumer | Planned behavior |
| --- | --- |
| Fresh profile / default launch | Select canonical `stik-glow-61fx-2t`, with an explicit documented fuel fill and start state. |
| Saved catalog preference for old base, 55AX or FS64V | Versioned preference migration selects the canonical 61FX, records the migration and provides a concise explanation. It does not migrate physical customizations. |
| Explicit CLI request for a retired production ID | Reject with a clear replacement suggestion; do not silently fly a different engine. Preserve the existing 61FX ID. |
| Old Workshop save/package | Preserve bytes; detect the retired or mismatched base. Offer an explicit conversion only for supported fields, otherwise report incompatibility and retain the original. |
| Old replay/checkpoint | Require original source/configuration/solver identity; retain a reproducible historical path or reject clearly. Never alias to the new default. |
| Synthetic `--electric-demo` routes | Decouple from the application default and retain only as named development/test fixtures. The real electric aircraft must use its own sourced inventory and `pack_ecm` installation. |

### Migrate tests by meaning

Create one shared canonical Stik test-selection helper/configuration and migrate implicit defaults plus hardcoded old-base loads. Fix seed, controls, atmosphere, fuel fill, engine state, tick rate and backend per case. Reset to the defined initial condition between independent cases; finite fuel must not be disabled just to reproduce old results.

The current [golden-flight helper](../../app/tests/golden_flights.gd) refuses coupled-shaft sessions. Both the target 61FX and electric routes use `coupled-rk4`. Before switching the test default, supply coupled-session regression coverage using the existing flight-log/checkpoint infrastructure or a deliberately versioned golden format. Cover shaft and energy state as well as rigid-body trajectories; reject incomplete or incompatible records. Do not bypass the refusal or merely re-record old-format goldens.

Keep analytic, fixed-voltage, 2T/4T and legacy-solver fixtures when they isolate a law. Label every remaining old-base reference as historical evidence, generator donor or specialized fixture. General tests must not silently remain on the retired base. Preserve numerical checks independently of the reference aircraft.

AI companion profiles pin the old aircraft ID, data path and hash. Regenerate and requalify the 61FX profile and maneuver assumptions; changing the hash alone is insufficient. The electric aircraft must advertise companion support only after its own qualification. Review failure-mode, Natural Random, weather and contact coverage for the new capability combinations.

## Owned paths and integration boundaries

| Area | Planned scope and boundary |
| --- | --- |
| Catalog/defaults/compatibility | `app/app_state/aircraft_catalog.gd`, preferences, direct launch and relevant tools/tests; no per-aircraft branch in the simulation kernel. |
| Physical authoring | Existing Stik field owners; `research/glow-engines/`, electric generators under `research/propulsion/`, BAT generation under `research/battery/`; generated `app/data/aircraft/` and pack records. |
| Contracts and presentation | `assets/aircraft/model-bindings.json`, generated model manifests, shared adapters and `app/aircraft/ugly_stik_*`; retain `airplane`, `propeller`, `*_hinge`. |
| Workshop and dependent data | Generated `app/data/workshop/`, customization compatibility, AI profiles, audio, smoke, damage/economy and package dependencies; respective owners approve technical interfaces through ordinary review. |
| Regression and performance | Existing `app/tests/`, flight logging, flight-test cards and `research/native-kernel/` consumers; measure the actual selected backend and preserve specialized fixtures. |
| Documentation | This plan owns migration status; the dated selection note owns motor research. Update current aircraft/glow/electric/Workshop guides and indexes at implementation; preserve published release descriptions. |

The electric presentation must remove or hide the combustion engine, exhaust, tank and fuel lines, and show the electric motor, mount, ESC and battery appropriately. Reuse legally suitable downloadable geometry/data before creating substitutes. Maintain accurate propeller diameter, pivot and strike envelope, distinct sound and energy HUD, and correct damage/economy inventory. The shared airframe appearance is not evidence of identical mass or handling.

Workshop currently permits base-aircraft transformations that finite-fuel aircraft do not support. Inventory the affected controls and saves; support them correctly under the existing contract or disable unsupported controls with an explanation. Do not silently transfer old size/power edits into a new engine model. No arbitrary scaling of a named motor or battery is part of this plan.

Reuse `VehicleModel`, float64 state, existing shaft/propulsion/pack laws and shared capability admission. The electric power stage currently lacks electric propwash, motor/ESC temperatures and current limiting. Keep the aircraft experimental within that scope; any expansion belongs to its existing EL/AS owner with separate evidence, not to an aircraft-ID exception. [Electric contract](../ELECTRIC-PROPULSION-PLAN.md), [battery contract](battery-realism.md), [aircraft contract](../AIRCRAFT_CONTRACT.md).

## Execution steps

| ID | Work | Proof / status |
| --- | --- | --- |
| EL1e-STIK-00 | Inventory current variants and select a 6S motor from primary sources. | **Complete as research only:** [selection note](../research/propulsion/ugly-stik-6s-selection-2026-11-08.md); no runtime or physical validation. |
| EL1e-STIK-01 | Freeze actual baseline including relevant dirty inputs; map ID/path/hash consumers, donor graph, test defaults, Workshop and AFC behavior. Define compatibility cases. | Pending: dependency map and reproducible baseline `.orfl` with exact replay; current generated identities retained. |
| EL1e-STIK-02 | Introduce canonical test selection and coupled-session regression support while preserving existing behavior. Classify remaining legacy fixtures. | Pending: old reference cases still pass, coupled 61FX cases complete, refusal/identity checks remain strict; migration coverage list has no unexplained consumers. |
| EL1e-STIK-03 | Qualify the existing finite-fuel 61FX as the new common reference; preserve donor generation and shared 55AX/FS64V/Extra behavior. | Pending: starts, trim, fuel/mass evolution, stop/restart, depletion, checkpoint/replay and flight-card evidence. Check candidate-replay compatibility first. If the changed state/integrator is refused, run independent baseline/candidate flights with shared tick/input tapes and declared initial conditions; document differing trim/state. Do not bypass identity checks or claim exact equivalence between different physics. |
| EL1e-STIK-04 | Author one sourced electric installation and pack, complete fit/current study and generate all dependent physical data. | Pending: valid v2 admission, reproducible generators, mass/CG/inertia report, prop clearance, sourced `Ct/Cp`, pack mass match, voltage/current envelope and held-out powertrain checks. |
| EL1e-STIK-05 | Integrate electrical visuals, audio/HUD, Workshop, companions where supported, failures, smoke and damage/economy contracts. | Pending: both product flows verified; electric has no residual glow equipment/effects; inspect first at 1920×1080, higher resolutions next, 720p last. |
| EL1e-STIK-06 | Atomically switch the application/common-test default to 61FX, offer Electric 6S and retire the three redundant catalog entries. Apply compatibility policy. | Pending: exactly two production Stik entries; preference/CLI/Workshop/replay cases verified; unaffected fleet preserved; no accidental developer-demo promotion. |
| EL1e-STIK-07 | Complete cross-cutting regression, backend qualification and export checks on a stable candidate. | Pending: required CI, justified full integration gate, fresh-checkout/package resources, native/reference parity or explicit supported fallback, 1080p product-flow evidence. |
| EL1e-STIK-08 | Consolidate guides, measured limits and evidence; remove obsolete live paths only after all consumers are resolved. | Pending: no unexplained retired-ID references in active defaults; dated history intact; ongoing physical/pilot gates transferred to their canonical owners before closing this plan. |

Each step should be independently reviewable. Complete electric admission and coupled regression support before the final catalog switch, so a partial transition is not shipped as the two-aircraft result.

## Verification and completion criteria

Use existing tools from the [tool index](../tools/README.md), [physics verification guide](../tools/physics.md), [flight-test cards](../../research/flight-test/README.md), [flight logging](../FLIGHT-LOGGING.md), [BAT tools](../../research/battery/README.md) and [native-backend contract](../../research/native-kernel/README.md). Do not create duplicate probe frameworks.

During implementation, run the smallest relevant parser/generator/admission/lifecycle checks. At the stable default/catalog migration, run broader integration and required CI because this change affects shared fixtures, startup, saved identities and packaging. An unchanged-fleet comparison applies only to unaffected cases; document expected Stik changes explicitly rather than forcing all old trajectories to match.

Before performance runs, freeze the target hardware, engine/build, backend, observer workload, resolution, warm-up, sample duration, metrics and current Gate P thresholds from the [performance contract](../../research/performance/README.md). The move from prescribed RPM to coupled shaft/fuel is a performance change. Report paired baseline/candidate tick and whole-frame distributions, including tail latency and events; the electric guide's open 500 microsecond tick target stays open until measured under its required conditions. Record the backend actually executed: reference fallback does not prove native parity, and a 1080p screenshot does not qualify 1080p performance.

Required evidence includes:

- The common 61FX reference covers runway and airborne starts, throttle steps, cut/restart, empty fuel, CG evolution, trim, stall/recovery, takeoff/landing, prop strike and ground rest.
- Electric coverage includes fresh/partly discharged/weak packs, sag, cutoff/recovery, depleted startup, reset/checkpoint/exact replay, coupled timestep behavior, shaft torque and prop strike. Validate current/thrust under the EL policy; keep endurance validation separate from a chosen capacity.
- Separate fitting, provisional checks against published sample data and independent physical validation. Never use the same 13x8E bench point to fit and validate the model. Reserve comparable cases before fitting; if no suitable independent sample exists, record that physical gate as open rather than counting a reproduced point as validation.
- Every recorded run declares aircraft/source/config/solver identities, actual backend, conditions and completion. Candidate comparisons never establish exact replay; retain `complete` and `solver_changed` diagnostics.
- Existing 55AX and FS64V engine-law tests, Extra installation, unrelated aircraft and non-airplane activities retain their applicable coverage. New goldens have a documented physics reason and reviewed comparison.
- Both catalog flows and exports work with the two intended names. No silent conversion of saved physics, no third selectable Stik, no missing pinned resources and no old default leaking into general test tools.

Software integration can finish with explicit experimental status. Physical realism and pilot acceptance require the matched measurements and review already owned by NITRO/EL/BAT and main-line gates; software pass counts alone do not close them.
