# Fuel system audit standard and completion plan

**Updated 2026-10-19. Owner:** physics, subtrack `FUEL-00` through `FUEL-14`. **Status:** active; FUEL-00 through 04 delivered, 05 through 07 partially integrated, 08 through 14 open. This is the single completion plan for fuel, mass and balance. The [aircraft contract](../AIRCRAFT_CONTRACT.md) remains authoritative for accepted fields and frames. The [review evidence](../research/fuel-systems/FUEL-00-R1/README.md) identifies the audited commit, commands and reproduced defects. The Word document beside that evidence is a dated export of this Markdown, not another editable standard.

## 1 Conclusion and scope

The shared mass kernel and the finite glow installation provide a sound foundation. The system is not yet complete across the fleet: gasoline and kerosene still have prescribed mass, the glow adapter does not consume the new tank contract fully, and crash reporting and restored-session fill settings contain reproduced inconsistencies. Complete those seams before adding more fuel behaviour.

This plan covers glow two-stroke and four-stroke, gasoline premix, turbine kerosene, and the mass accounting of smoke liquid. It standardizes existing configurations and the admission of future aircraft. Battery electrochemistry stays with BAT; its pack mass remains constant. Helicopter and ground-vehicle adoption stays behind their own gates. Dynamic slosh, fuel temperature dynamics, foaming, vapor and fire simulation are outside this completion scope.

Use three separate acceptance labels: **software verified**, **evidence constrained**, and **physically validated**. Passing tests establishes only the first. Manufacturer capacities and borrowed engine data constrain estimates; they do not identify an installed aircraft. Physical validation requires measurements with uncertainty under FUEL-13.

## 2 Audit of the current tree

The fuel audit baseline is commit `903d0b444` on 2026-10-19, initially clean. Unrelated documentation and cleanup changes appeared during review and were preserved. The baseline includes recent FUEL, BAT and aircraft integration changes. Historical [FUEL-00](../research/fuel-systems/FUEL-00/README.md) numbers describe an earlier tree; they must not be presented as today's fleet. Source locations and complete reproductions are in [FUEL-00-R1](../research/fuel-systems/FUEL-00-R1/README.md).

### 2.1 What is implemented

The registry contains seven components and three blends, with GDScript and generator readers. The v2 loader accepts `fuel_system.tanks`, stable inventory references, capacity and unusable volumes, fuel-state balance and an optional CG range. `MassInventory.prepare_reference/evaluate_reference` and `FixedDatumBody.derivative` implement the shared fixed-datum law; `glow/fuel_mass.gd` is a compatibility adapter.

Five finite glow Stik configurations burn fuel and update stage-local mass, CG and inertia. Their tanks now start full: 350 ml for the 55AX and 61FX variants and 220 ml for the FS-64V. The session exposes `mass_properties()`, the HUD uses live mass, crash severity/effective mass use live properties, and `.orfl` records mass and CG. Home offers 25, 50, 75 and 100 percent; the session API accepts a fraction in `(0, 1]`, and reset uses the selection. These are implemented slices of FUEL-05, 06 and 07, not closure of all their original gates.

| Current configuration | Tank and authored fill | Runtime consumption | Remaining work |
| --- | --- | --- | --- |
| Five finite glow Stiks | 350 or 220 ml, full | Finite glow | ID-based installation binding, unusable residue and feed, full evidence |
| Base Stik | 350 ml, half | Prescribed | Keep reference role explicit; qualify a finite product replacement |
| Extra 300S | 355 ml, half | Prescribed | Install finite glow through NITRO |
| P-51D | 1 l, half | Prescribed gasoline | Qualified gasoline consumption adapter |
| Ventage Jet | 3.2 l, half | Flow telemetry; mass prescribed | AV depletion, hopper, balance and smoke-store accounting |
| Electric Stik specimens | Donor inventory | No liquid consumption | Neutral ballast IDs or real motor and pack inventory |
| Timber and optional finite pack | Battery inventory | BAT owns energy | Include nested pack configuration in fleet mass-report coverage |

Nine top-level aircraft files declare tanks. The mass report covers 14 top-level inventory-bearing files; the nested Timber pack configuration is omitted. Only the Extra declares a CG range. Tank declaration does not itself enable consumption. Current reported empty Stik static margin is 3.835 percent MAC, rather than the historical 0.3 to 0.7 percent; the neutral points remain estimates.

### 2.2 Open findings and disposition

P1 blocks consistent software behaviour or the common standard; P2 blocks qualification or complete integration. Historical findings F01 through F22 remain in FUEL-00 as dated evidence.

**A1 P1 Crash remaining fuel is inconsistent.** At a production glow crash with 25 percent remaining, `energy_sources.glow_fuel` is 0.0749805 kg, while `report.fuel_kg` and the kerosene scalar passed to crash effects are zero. The director initializes that scalar from kerosene only. The glow stain reads the correct source dictionary; this does not prove a missing stain. Close under FUEL-06-R1 with typed fuel reporting, consistent consumer inputs and a production-path regression.

**A2 P1 Restored fill preference and provenance are incomplete.** A half-fill checkpoint restores its actual fuel correctly into a fresh full-default session, but the destination retains `fuel_start_fill = 1`. Its trace omits the half-fill selection and reset loads 0.299922 kg instead of 0.149961 kg. This does not show a failure of exact state continuation. Close under FUEL-07-R1 by declaring and testing a restore/reset policy, serializing the launch selection or recording it as unknown; never infer it from remaining fuel.

**A3 P1 Tank validation and the glow installation use different identities.** The contract binds liquid and shell by ID, but the glow installation still finds `fuel_inventory` by exact display name and prepares capacity from the authored liquid mass. It does not apply normalized capacity, pickup or unusable mass. A renamed item can satisfy the tank contract while breaking the installation. Close ID/capacity binding in FUEL-05-R1; close delivered feed and residue in FUEL-09.

**A4 P1 The old plan confuses balance CG and solver datum.** D2 and older FUEL-04 prose promise a datum at `plan_cg`; the current contract, loader and installation retain the authored inventory CG. Empty-tank balancing does not move that reference. Section 3.2 and the [decision record](../DECISIONS.md) supersede that wording without rebasing runtime state.

**A5 P1 The proposed rotational feed formula had mixed signs.** Existing feed implements apparent gravity as minus non-gravitational force divided by mass and omits rotation. The old proposal added point-acceleration terms to that apparent gravity. Instead derive it from gravity minus the complete inertial acceleration at the liquid point. A rotating-point fixture must establish the signs before FUEL-09; this concerns the proposal, not an existing rotational implementation.

**A6 P2 Fleet migration and its evidence are incomplete.** FUEL-05 snapshots exist, but its linked README is absent. Synthetic electric donor IDs, declared-state CG ranges, Ventage hopper/smoke accounting and finite operation of the remaining combustion fleet stay open. Reconcile the Ventage shell/liquid centroid separation against an explicit physical interpretation. Its smoke tank is currently authored empty. Do not invent liquid to fill it or label estimated placements as measured.

**A7 P2 Mass-report coverage and drift enforcement are incomplete.** Its non-recursive glob omits the nested battery configuration. Registered static margins are gated, but printed `DRIFT` does not affect exit status. The informational `plan_cg_matches_inventory` compares wet inventory even for an empty-tank target, and the report does not expose the declared CG range. Close in FUEL-05-R1 with catalog-plus-supported-variant coverage, explicit declared-state results and a failing drift mode where required.

**A8 P2 Depletion event units leak from the battery helper.** Glow renames `battery_exhausted` to `fuel_exhausted` while retaining `charge_residual_c`. Normalize the fuel payload to a declared mass unit and test the complete schema under FUEL-08. Keep the reusable event locator.

**A9 P2 Registry/profile equality is tested but not enforced at loading.** Glow profiles still derive density from embedded component data. Current tests establish agreement with the registry; the runtime installation does not reject a divergent blend. Close this seam with AS/NITRO in FUEL-05-R1, including a mismatch refusal and source-identity test.

**A10 P2 Qualification evidence is not reproducible end to end.** Read-only generator checks flag stale Timber physics output; Ventage passes the UTF-8 check. FUEL-05 FT comparisons contain blank commit identities and an invalid 55AX trim result. Preserve these as findings, not accepted flight-feel proof. Resolve or classify each under its owner before FUEL-05/12 closure.

Fourteen focused native Windows tests passed with 4,626 checks and zero failures. Both A1 and A2 still reproduce. Ordinary CSV traces still lack live mass/CG although `.orfl` has them. No full-suite, target-GPU, pilot or physical-validation result is claimed by this audit.

## 3 Common standard

### 3.1 Data and ownership

Use `openrc-aircraft v2` quantities `{value, unit, kind, source}`. Every tank has a stable ID, registry blend ID, liquid and shell inventory IDs, capacity and unusable volume in `l`, pickup and feed. Preserve the contract's current enums. The liquid item carries the matching energy-source family, position and nonzero box dimensions; the shell is separate dry mass. The current schema has no authored `start_fill`, pickup-coordinate, line-volume or feed-priority field: add those only through a reviewed versioned extension when a consumer is ready.

Generate liquid mass once from selected authored volume and registry density. The loader derives normalized start fill as liquid mass divided by capacity mass. Never duplicate density in aircraft prose or select a liquid by name or array index. Mass, capacity and geometry must agree, with finite values and positive usable capacity. A zero unusable volume is an explicit estimate, not evidence that every drop can be delivered. Qualify shell geometry or disclose the point-mass approximation separately from liquid geometry.

The registry owns blend composition, reference density, temperature and provenance. NITRO owns glow consumption/feed/lifecycle; P51 owns its gasoline adapter; AV owns turbine ECU/pump/hopper. Aircraft generators own inventory/balance; AS owns schema and normalization; physics owns mass and state contracts. UI, HUD, AUD, CR, EM and AE consume those contracts within the [track boundaries](../README.md#tracks-plans-and-step-ids). No vehicle-specific branch enters `Simulation`.

### 3.2 Frames mass and balance

**The solver datum O is the CG of the authored reference inventory, fixed for that loaded model.** It does not change with burn, session fill or reset. The balance target `plan_cg` is a structural point checked at `balance.fuel_state`; it can differ from O. A full-tank reference inventory makes O a full-tank CG; a half-tank reference makes it that configuration's half-tank CG. Neither is automatically the dry CG. This supersedes D2's choice of `plan_cg` as the anchor while retaining its fixed-reference requirement.

Use the [contract's coordinate conversion](../AIRCRAFT_CONTRACT.md#coordinates-signs-and-units). Geometry, gear, hull, thrust and intake arms remain relative to O. Stages obtain total mass, live CG offset and the full tensor about the live CG from one prepared inventory and the stage's resource masses. Contacts use arms from that live CG. Rendering converts at the boundary; simulation retains float64 arrays.

Use the existing co-moving-efflux law and momentum/refinement fixtures. Do not add mass-derivative spin-up terms to it. Internal transfer conserves total mass while changing first moment and inertia. A future non-co-moving discharge must declare its momentum flux and validation; it cannot silently reuse the present assumption.

Check a manual CG range only at the declared balance state. The adopted propeller default is empty tanks; jet balance needs a full hopper and empty main tank, which current `empty_tanks` cannot express separately. Extend that state through AS/AV before claiming it is enforced. Report full, authored, session-start, reserve and empty CG and inertia. Require positive static margin against the disclosed neutral-point estimate throughout the permitted fill envelope; this screens an estimate, not physical handling. For one fixed-centroid tank and fixed neutral point, endpoints bound longitudinal CG. For independently varying tanks check envelope vertices or provide an equivalent bound. Never rebalance hardware per fill.

### 3.3 Flow feed and exhaustion

Integrate delivered outflow in kg/s. Glow retains its per-cycle laws. The first gasoline adapter uses sourced BSFC times nonnegative delivered shaft power plus a disclosed idle rule; define stopped, windmilling and negative-power behaviour. AV binds its existing turbine flow data to finite stores and ECU lifecycle. Smoke consumption needs a separate resource and an explicit registry/store extension; today's combustion tank contract has no smoke blend. An authored empty smoke tank requires no invented liquid mass.

Evidence distinguishes full-throttle flow, idle flow, BSFC and mixed-flight endurance. A manufacturer's mixed-flight duration cannot directly calibrate full-throttle flow. Review FS-64V consumption under NITRO before qualification. Do not tune source data merely to make endurance pass.

Derive apparent acceleration at each relevant point from gravity minus its inertial acceleration. For a rigidly fixed point relative to CG, point acceleration includes angular acceleration cross r and omega cross omega cross r; their apparent contributions have opposite signs. A fixed-datum calculation must also include the datum-to-CG acceleration correction. Test outward apparent acceleration in steady rotation, the angular-acceleration sign, level 1 g and free fall independently.

Feed uses absolute capacity, remaining usable mass, geometry and pickup/feed hardware. Unusable residue stays onboard and contributes mass after starvation. Near-empty starvation drains a declared line/hopper volume before the lifecycle stops the source; count that liquid once. Inverted flight follows pickup coverage and apparent acceleration, not bank angle. Main-tank exhaustion need not stop a full hopper. Feed reductions are continuous where the law permits; discrete changes are explicit located events.

All RK stage queries stay pure. Located events commit nonnegative resources, typed residuals with units, stable ordering and the correct stopped/restart state. Rejected stages roll back the whole transaction. The vehicle model supplies layout and evaluators through the existing kernel contract; the kernel stays vehicle independent.

### 3.4 Samples checkpoints and consumers

Publish a consistent accepted-state mass sample: tick/time, total mass, live CG relative to O, full inertia/inverse, per-store remaining/usable quantities, blend identity and law identity. This is a target extension: today's `mass_properties()` is a pure single-tank query with fewer fields, not a cached per-tick bus. Persistent caches require complete invalidation.

HUD load factor, CG marker, crash/contact effective mass, wreck mass, fuel exposure/pricing, trace and `.orfl` diagnostics use that accepted state or the corresponding impact-time sample. Swept contact kinematics and mass need consistent time; label any approximation explicitly.

Checkpoint/replay identity includes source bytes, registry/installation laws, store layout, complete continuous/discrete feed/lifecycle state and launch-fill policy. Exact continuation needs actual remaining mass; reset and provenance also need the selected launch setting. Specify compatible legacy reads and explicit rejection of unsupported versions. Rejected restore cannot partly change a session. Keep recording read-only and bounded; reuse the [flight logging workflow](../FLIGHT-LOGGING.md), CSV exporters and free plotting tools.

### 3.5 Admission of future aircraft

Before enabling a new combustion configuration, supply a reproducible generator; source-backed fuel family/capacity; stable shell/liquid bindings; geometry/datum; explicit balance state and sourced range or disclosed missing-range limitation; a supported finite propulsion/feed installation; and section 5 checks. A tank object alone is insufficient.

Publish the evidence kind for density, placement, unusable residue, consumption and reserve. Preserve free manufacturer references and their licences instead of fabricating replacement data or assets. Estimates remain estimates after reuse. Retain prescribed-fuel specimens as named references with explicit limitations, not evidence of finite operation. Existing product routes stay supported until reviewed replacements pass.

## 4 Work packages and execution order

Keep the original IDs and owners. Repair suffixes refine existing steps. Each package is independently reviewable and records tests and limitations beside its evidence.

| ID | Status | Next work and closure evidence |
| --- | --- | --- |
| FUEL-00 through 04 | Delivered foundation | Preserve [00](../research/fuel-systems/FUEL-00/README.md), [01](../research/fuel-systems/FUEL-01/README.md), [02](../research/fuel-systems/FUEL-02/README.md), [03](../research/fuel-systems/FUEL-03/README.md), [04](../research/fuel-systems/FUEL-04/README.md). R1 clarifies datum and completion scope |
| FUEL-05-R1 | Partial | AS/NITRO/aircraft: ID/capacity/blend binding, donor IDs, balance/ranges, nested-variant reporting, drift refusal; missing evidence index, generator checks and before/after proofs |
| FUEL-06-R1 | Partial | Physics/CR/FL/HUD: A1, crash/effects/economy consumers, impact-time sampling and versioned trace mass/CG; production tests with nonzero and exhausted fuel |
| FUEL-07-R1 | Partial | Session/UI/FL: A2; 0.1/0.5/1.0 ground and airborne starts, reset, JSON restore and exact replay; selected or unknown provenance |
| FUEL-08 | Open | NITRO/P51/AV: finite Extra, gasoline and turbine adapters; 4T flow review; A8 event units; exhaustion/restart and full/mixed/idle domains |
| FUEL-09 | Open | NITRO/EM/AV: rotation signs, capacity-based feed, pickup, residue, line/hopper transfer; schema with supported consumers, conservation and deterministic starvation |
| FUEL-10 | Open beyond glow ml display | HUD/AUD/CR/UI: ml/percent, authored reserve, low-fuel/lean-out cues and pricing; optional oz in UI |
| FUEL-11 | Open | AE: finite-store tank/fill transforms, dry-only multiplier, target CG/ballast; identities and replay; fuel never scales with dry weight |
| FUEL-12 | Open | FT/FL/aircraft: exact baseline replay and one candidate on the same tick/input tape; FT at full/low fill; identities, markers, CSV and report |
| FUEL-13 | Open physical gate | VAL: empty/full weighing/CG and timed burn with configuration and uncertainty; compare model to measurement |
| FUEL-14 | Vehicle-owned deferral | RCV/HELI: shared resource contracts with separate native/backend and vehicle qualification |

**First slice:** close the reproduced inconsistencies under FUEL-06-R1 and 07-R1, then complete FUEL-05-R1 contract/evidence. NITRO, gasoline and AV adapters can proceed separately under FUEL-08; FUEL-09 consumes the same stores. FUEL-10/11 follow stable interfaces. FUEL-12 qualifies each promoted configuration; FUEL-13 remains separately reported.

AV-10a/b/c and AV-05b/23/25/27/28 retain turbine ownership; NITRO retains laws/calibration. R05-B and VAL-AUD-R05/R07 handoffs require their own complete evidence, including remaining contact-event/remainder and free-rotor work. FUEL-06 alone cannot close them. AS-12/16 owns schema; AE-12/13/16/17 consumes FUEL-11; EM-15/16/21 consumes feed/mass; CR-35/37 consumes remaining stores. G4a/G4b and X-DATA-11 proposals are superseded here; per-tick rebasing is not the standard. BAT shares inventory semantics but owns battery energy. Drone fuel work is outside the present aircraft scope.

Adopted D1 and D3 through D8 remain: one FUEL subtrack, empty-tank prop balance/explicit jet hopper balance, full default for finite configurations, minimal gasoline BSFC scope, fixed liquid shape, neutral electric donor items or real hardware, and ml/percent display. Section 3.2 supersedes D2's anchor choice while retaining its fixed-reference requirement. FUEL-09 considers a quasi-static centroid only for a documented effect above 1 mm and with a consistent momentum law. Dynamic slosh stays deferred.

## 5 Acceptance gates and evidence

### 5.1 Software completion

1. Schema, loader and generators agree on tank validity, blend, IDs, quantities, capacity/geometry and balance state. Rename/reorder preserves bindings. Verify fresh-checkout generation and byte/EOL identities.
2. Independent mass/first-moment/full-tensor oracles cover empty, reserve, partial, full and asymmetric stores. Include physical tensors, co-moving momentum and convergence. Internal transfer cannot create mass.
3. Real sessions qualify full/low-fill starts, trim, ground contacts, burn, residue, event ordering, starvation, stop and restart. Query/render order cannot alter outcomes. A failed transaction retains the prior accepted state.
4. JSON checkpoint restore reproduces exact continuation and the declared reset/provenance policy. Changed identities are refused as specified. Incomplete/recovered logs cannot establish exact equivalence.
5. Production HUD, crash report/effects/wreck/economy and both diagnostic formats agree with remaining-store state. Test A1/A2 explicitly, not only helper results.
6. Run applicable generator/schema/offline and complete app checks per [TOOLS](../TOOLS.md). Keep deliberate defects on disposable copies. Qualify shared-kernel cost through paired target-machine runs; isolated tests prove neither a full suite nor performance.

### 5.2 Aircraft and physical qualification

Each promoted configuration retains source/configuration identity, generator diff, full/start/reserve/empty report, declared-state range check and neutral-point estimate. Re-record goldens only for explained physics changes. Unaffected vehicles and reference specimens preserve required trajectories; changed source identities need explanation even when values are equal.

Follow the [flight logging workflow](../FLIGHT-LOGGING.md): retain baseline `.orfl`, prove exact replay, then compare one candidate on the same tick/input tape. Check `solver_changed` and `complete`. Compare trim, pitch response, glide and stall changes with predictions and stated assumptions; square-root mass scaling applies only to a controlled same-CLmax/atmosphere comparison. Candidate replay and FT predictions do not establish measured realism.

Close physical validation only after actual empty/full weighing, CG and burn observations with calibration and uncertainty reach the VAL reducers. Software completion may ship with that gate explicitly pending. The track stays active until required aircraft software packages close and remaining physical/other-vehicle scope is recorded.

## 6 Sources and maintenance

[FUEL-00-R1](../research/fuel-systems/FUEL-00-R1/README.md) owns this audit's anchors, test logs and defect probes. The [FUEL-00 manifest](../research/fuel-systems/FUEL-00/sources.json) retains manuals, density tables, measurements and licence/access records. Historical values are not current calibration. FUEL-01 retains the 61FX mirror repair; FUEL-02/04 retain registry and momentum proofs.

[JSBSim's tank reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGTank.html), rechecked 2026-10-19, distinguishes capacity, contents, unusable volume, location/drain location and priority. These support the conceptual distinctions; OpenRC retains its own schema, units and validation. No solver code is copied.

Keep status in section 4, contract fields in AIRCRAFT_CONTRACT, commands in TOOLS and GLOW-ENGINES, decisions in DECISIONS, and dated evidence with its owner. Preserve historical measurements. On completion consolidate enduring rules into the canonical guide and retire this plan.
