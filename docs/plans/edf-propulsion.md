# Electric ducted fan propulsion and the Vantage Jet EDF experiment

**Owner:** propulsion/energy lead, with AS, BAT, AV, M5, SF, NK, FL, GP, input, AUD and UI owners.
**Step prefix:** `EDF-00…15`. **Research date:** 2026-11-21.
**Audited baseline:** `main` at `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
**Delivery branch:** `research/edf-propulsion-2026-11-21`.

**Status:** EDF-00 delivers research, a source audit, reproducible planning
arithmetic and this implementation plan. No EDF runtime, generated aircraft,
physical calibration or flight qualification is delivered by this branch.
Steps EDF-01…15 remain pending. The [research index](../research/edf-propulsion/README.md)
owns actual verification results; [physics and sources](../research/edf-propulsion/physics-and-sources.md),
[repository audit](../research/edf-propulsion/repository-audit.md) and
[validation matrix](../research/edf-propulsion/validation-matrix.md) supply the
engineering handoff.
**External audit revision:** EDF-00-R1 challenges the original candidate
`719c3cc6b8e3ac32d2f62e08b6df9b646925361f`; its
[finding/disposition record](../research/edf-propulsion/external-audit-2026-11-21.md)
explains the corrected contracts and remaining evidence gates.
**Native research revision:** EDF-00-R2 adds [twenty investigations](../research/edf-propulsion/native-research-2026-11-21.md)
and a [native execution and product design](../research/edf-propulsion/native-runtime-design.md).
The user's native-code requirement applies to all new EDF runtime behavior and
the complete numerical path. This supersedes R1's permission for a selectable
reference EDF product flight; a reference oracle remains an explicit verification
tool. The existing stage-only backend does not yet satisfy this requirement.

## 1. Goal and first playable slice

Add a reusable **electric ducted fan** propulsion family, then make a separate
experimental EDF variant of the current **Vantage Jet / SebArt Avanti S A200**.
Retain the existing `sebart-avanti-s-a200-p100rx` turbine sibling and its identity.
The experiment keeps the same airframe scale, wing, tail, retracts and control
layout, with explicitly authored EDF installation and mass changes. It is not
the smaller Avanti XS or a Freewing foam Avanti.

Use a **128 mm Schübeler DS-98 / DSM6036-600 class** as the first identified
reference. Study **152 mm DS-130** and **195 mm DS-215** configurations through the
same architecture. These actual sizes, published power ranges, source
disagreements and unproven fit are documented in the
[candidate comparison](../research/edf-propulsion/physics-and-sources.md#2-large-fan-candidates).
The 195 mm case is the deliberate oversized experiment; start it on a propulsion
stand, then admit an A200 installation only after its explicit geometry and mass
assumptions pass the corresponding software checks. Physical fit remains a
separate measurement gate.

**First playable research slice:** one forward-facing internal fan, one electrical
bus/pack, fixed blade pitch, fixed duct geometry, one declared rotation sense,
coupled rotor/body RK4, finite battery, bounded throttle-off/windmill behavior,
runway and airborne starts, gear/flaps, HUD, explicit audio routing and exact
checkpoint/replay. Its estimated quantities and unsupported regimes remain
visible. Every admitted EDF flight requires the qualified native path, including
input conditioning, sampled weather, integration, events and state-affecting
world/session policies. Missing capabilities disable that launch with a reason.
Physically unmeasured parameters do not prevent a clearly labeled
simulation experiment, but cannot support a realism or manufacturer-equivalence
claim. A validated numeric model is required even for experimental admission.

Multiple fans, differential throttle, thrust vectoring, general compressor
surge/rotating stall, active braking/regeneration, blade structural failure and
automatic conversion of imported EDF aircraft are separate later extensions.
Do not expand the first slice into a general power-distribution framework.

## 2. Architectural decisions

### 2.1 Add a distinct family, reuse the existing contracts

Proposed `propulsion.kind = "electric_ducted_fan"` makes the difference visible
to admission and consumers. Final spelling/module version is frozen in EDF-01.
Keep `electric_prop` semantics and identities intact. Prefer retaining the
geometric `single_centerline_jet` layout while explicitly extending its currently
turbine-only family/energy admission, and add an internal-fan contact capability.
The layout name does not itself mean fuel-burning. EDF-01 must document a real
semantic need before adding another layout enum; never disguise EDF as
`single_tractor` or infer exposed blades from its diameter.

Reuse the stateless electrical conventions, battery law, simultaneous rotor/body
solver and existing session transaction. The fan/duct law belongs in a model
adapter and pure evaluation helpers. **Simulation must not branch on EDF.**
Implement the laws in native C++ from the start, with an independently justified
verification oracle. Extend the shared kernel with a **vehicle-generic complete
native numerical tick**, coordinated with SF/NK; do not create an EDF-specific
integrator, second clock or competing accepted-state owner. Current NK-3 only
replaces stage callbacks, so this is a proposed kernel capability, not an existing
feature. Preserve the shared Simulation/session facade and transaction semantics.

EDF product admission is explicitly stricter than the current general fallback
policy: a missing, stale, unsupported or refused native capability prevents EDF
launch. No EDF numerical callback may fall back to GDScript, including controls,
weather/RNG, event and contact policies. A test-only reference route must be
explicitly selected and cannot qualify product flight. Existing non-EDF routes
retain their current policy. New EDF runtime logic, views and audio use C++ or
Godot-native facilities; the existing shell may capture raw device events,
dispatch commands and present detached accepted results. See the
[capability closure](../research/edf-propulsion/native-runtime-design.md#2-capability-closure-before-flight).

The main data flow is:

```mermaid
flowchart TD
    A[Accepted throttle and source modes] --> B[ESC command and limits]
    C[Pack state and temperature] --> D[Coupled bus and motor solve]
    B --> D
    E[Stage rotor speed and local air] --> F[Fan and installation map]
    D --> G[Rotor and body balance]
    F -->|Shaft load| G
    F -->|Installation force and moment| G
    D --> H[Energy and thermal rates]
    G --> I[Qualified native tick transaction]
    H --> I
    I --> J[Accepted state and read-only observers]
```

This is a dependency diagram, not a new update loop. Every stage evaluates its
own detached state, atmosphere and operating point; observers consume only
accepted results. No stage updates modes, RNG, telemetry history or presentation.

### 2.2 Separate shaft load from installation force and moment

The current propeller path uses rotor aerodynamic torque both as a shaft load
and as an external body roll moment. A ducted fan's stators can recover much of
that external torque. The EDF stage must return both:

| Output | Consumer / meaning |
| --- | --- |
| `fan_shaft_load_nm` | Rotor equation; load opposing the selected positive spin convention, with separately defined windmill signs. |
| `installation_wrench_body` | Six body-frame force/moment values about authored datum O, including the chosen inlet/nozzle/stator boundary exactly once; the adapter transfers the combined moment to the live CG once. |
| Electrical quantities | Motor and pack current, terminal voltage, DC power, shaft power and explicit losses, with units and conventions. |
| Domain/quality state | Output-specific evidence and joint support, estimated physical continuation, numerical locator-probe class, source/map identity and declared observer coverage. |

The existing `RotorCoupling` solver supplies relative-spin reaction and the
rigid-body derivative supplies gyro terms. Do not add them again. Keep thrust
axis and spin axis distinct. See the
[equation contract](../research/edf-propulsion/physics-and-sources.md#5-shaft-torque-stators-and-the-rigid-body)
and EDF-A03 for exact source integration points.

### 2.3 Choose one force representation per law

The first coupled model uses a calibrated or explicitly estimated map returning
rotor shaft load and installed wrench. Map metadata declares whether the force
is isolated net thrust or installed net thrust, its reference planes, support
tare, duct/nozzle geometry and external-airframe exclusions. Measured DC power
is not measured shaft power; loss-based inference must retain provenance.

A pressure-rise/flow/nozzle solver is an alternative when sufficient data exists,
not a required CFD project and not an additional force applied beside the map.
Do not add ram drag, pressure thrust, a shroud multiplier or stator torque already
included in a measured net force/moment. Airframe/installation drag ownership
must be explicit before flight tuning.

### 2.4 Do not hide missing identification with a turbine governor

The preferred law solves motor torque, fan torque, voltage sag and rotor inertia.
An independently fitted black-box RPM/thrust/DC-power response is useful as a
stand comparison when motor parameters are not identifiable. Such a model needs
its own law identity and energy treatment; it cannot masquerade as a measured
shaft model or be inserted inside that model as a second RPM governor. The first
flight slice uses the coupled law with clearly labeled parameter estimates until
matched measurements improve them.

### 2.5 Support the experiment without changing its sibling

Proposed catalog ID: `sebart-avanti-s-a200-edf128-experimental`, display name
**Vantage Jet · EDF 128 (Experimental)**. EDF-01 must confirm uniqueness and the
project's naming rules before adoption. Larger candidates get separate IDs and
installation manifests if promoted; a stand configuration is not automatically
a catalog aircraft.

Share immutable airframe sources and suitable visual assets. New component
inventory, fan maps, pack bytes, installation geometry and generator output are
independent. Recompute mass, CG, inertia, trim and ground-support consequences.
State of charge does not deplete battery mass. Preserve stock turbine data,
goldens and recordings on their matching law/backend identities.

Use the existing catalog's **dual-path contract** for the first entry: a declared
ideal-bus laboratory configuration in `data`, a separately identified finite-pack
configuration in `battery_data`, and the existing pack default for a fresh
preference. Preserve an existing supported ideal/pack preference. Both paths
must be generated and tested. Never place a finite-only file into `data` and let
the catalog label it ideal. A later finite-only entry needs an explicit catalog
capability change, not two misleading aliases for the same pack file.

## 3. Ownership and proposed file boundaries

Existing files below are integration points, not permission to rewrite all their
consumers at once. Proposed paths are deliberately shown as code until created.

| Owner | Existing boundary | Proposed focused additions |
| --- | --- | --- |
| EDF/physics | `app/physics/propulsion.gd`, `dynamics.gd`, `rotor_coupling.gd` | Pure `nk_edf*.hpp` fan/installation/operating-point kernels under the native source owner; explicit units and moments, independent verification oracle. |
| M5/EDF | `app/physics/wind_aircraft_flow.gd`, `propulsion.gd`, stage-air receipts | Register the intake station; native sampling, RNG progression and local-flow evaluation retain spatial-weather identity and checkpoint semantics. Refuse unsupported EDF weather modes. |
| EL/BAT | `electric_motor.gd`, `electric_supply.gd`, `battery/pack_ecm.gd`, `battery/esc_supervisor.gd` | Native equivalents of the reused circuit and bounded motoring controller; measured controller config under owning data sources. |
| AS/data | `aircraft_modules.gd`, `aircraft_data.gd`, `app/data/schema/`, `research/aircraft-standardization/build_schema.py` and schema tools under `research/aircraft-data/schema/` | Explicit EDF branch, conditional modules, quantity/unit/domain and failure-path coverage. |
| SF/Session/FL/GP | `simulation.gd`, `flight_session.gd`, `aircraft_propulsion_runtime.gd`, electric step, contact policies and recorder identity | Generic native tick, initialization, events, mutable world/session effects and checkpoint/restore; one transaction behind the existing facade. |
| NK/input | `app/sim/native_stage.gd`, `research/native-kernel/src/`, radio/keyboard conditioning and qualification tools | Prepared map/layout/workspace, native command conditioning and complete capability guards with actual native-call receipts. |
| AV/data | `research/avanti-s/av06/`, `assets/aircraft/avanti-s-a200/` | `research/edf-propulsion/avanti128/` input/derivation pipeline and separate generated aircraft output. |
| Catalog/model/UI | `app/app_state/aircraft_catalog.gd`, `app/aircraft/model_registry.gd`, aircraft adapter, Home and HUD | Separate variant; new native Godot stand/installation/debrief views using accepted snapshots; preserve stable control/hinge names. |
| GP/CR/AUD | Hull/prop contact, crash metadata, `app/audio/` | Native internal-fan contact semantics, correct LiPo source, native EDF observers and a labeled sound fallback. |
| SM/AUD/UI | `app/render/smoke/stock_profile.gd`, `app/render/aircraft_customization.gd`, `app/main.gd`, catalog/Home | EDF-safe stock presentation, legacy-audio handling and honest ideal/pack selection; visual-family reuse does not establish source compatibility. |
| AE/scenarios | Workshop descriptors, failures, Natural Random, Creator imports | Support with owning tests or explicitly exclude; no silent migration. |

The [source audit](../research/edf-propulsion/repository-audit.md) includes exact
symbols and current assumptions. Consult scoped `AGENTS.md` before each future
edit. Materialize required sources/imports in the implementation checkout; a
sparse checkout is sufficient for this research, not for claiming runtime tests.

## 4. Data contract to freeze before coding the flight path

EDF-01/02 must define a closed versioned schema, with quantities following
`{value, unit, kind, source}`. A conceptual grouping is:

| Group | Required information / checks |
| --- | --- |
| Identity | Family and law versions, map/installation hashes, exact hardware and firmware context, source format and generator receipt. |
| Native capability | Complete numerical route, model/world/control features, engine/API/ABI/toolchain/library identity, workspace limits and admission refusal reason. A loaded stage library is insufficient. |
| Geometry | Actual rotor tip/hub/casing dimensions, FSA convention, blade/stator count, clearance, fan/intake/nozzle reference positions, thrust/spin axes and duct identity. |
| Motor/ESC | Kv and resistance convention, loss context, inertia, valid voltage/RPM/current limits, command mapping, ramp/current supervisor, averaging bandwidth and cutoff/source-off circuit mode. Aerodynamic freewheel does not define electrical topology. |
| Pack | Existing generated pack/template identity, series/parallel wiring, mass-matched inventory mount, initial charge/temperature and LVC. |
| Map | Joint sampled support/cells and holes per output, interpolation/endpoint policy, power and force boundary, uncertainty type, acquisition/run IDs and installed geometry identity. A static sweep is not an N-dimensional support box. |
| Continuation | Bounded accepted physical domain, which may be entirely estimated; separately identified locator-only moving-side continuation through zero RPM/charge; unsupported accepted reverse-spin/brake/regeneration modes. |
| Numerical budget | Per-observable absolute/relative scales, norms, time horizons, independent oracles and event-time/work limits frozen before results; 240 Hz must pass these in addition to refinement. |
| Initialization | Instantaneous or conditioned quasi-steady launch, source-off stopped/freewheel branch, resource/controller state, sample phase and expected first-tick drift. |
| Accepted transaction | Raw-input sampling/consumption protocol, native conditioner state, weather RNG, mutable collision/damage effects, clock/epoch and complete checkpoint identity; precommit refusal versus postcommit observer fault. |
| Presentation/contact | Internal fan rather than exposed propeller, installed component metadata, observer/audio capabilities and source-loss behavior. |

Admission must reject mismatched energy kinds, missing maps, invalid axes,
nonphysical inertia, impossible annulus areas, unit mismatches, nonmonotone axes,
NaN/Inf, duplicate or missing identity fields, unsafe time constants and
unsupported mode combinations. Reference and native must agree on refusal.
Bounds must cover the chosen experiment without blanket relaxation of existing
aircraft limits. Update offline validation and runtime normalization together.

## 5. Step register

The order below defines reviewable changes. A step is complete only when its
specific proof exists; producing source or a document is not a passed flight gate.

| Step | Work | Required proof / status |
| --- | --- | --- |
| EDF-00 | Research, repository audit, candidates and plan | Delivered in this branch; actual check record in research index. |
| EDF-01 | Freeze model/data/interface and experiment specification | Pending; reviewed force/torque/energy ownership and compatibility decisions. |
| EDF-02 | Prepare synthetic data now; acquire/identify physical data in parallel | Pending; EDF-02a synthetic provenance/domain, EDF-02b source-to-map receipt and independent observations. |
| EDF-03 | Implement pure native fan and installation law | Pending; independent analytic/reference checks of limits, units, signed loads and interpolation interiors. |
| EDF-04 | Electrical limits, thermal admission and coupled operating point | Pending; energy/current closure, startup limits and stable integration. |
| EDF-05 | Integrate the generic native numerical tick and session transaction | Pending; native input/weather/world closure, atomic lifecycle, refinement and exact replay. |
| EDF-06 | Qualify the complete native path and EDF admission | Pending; prescribed parity, guards, allocation/boundary evidence, actual call coverage and package scope. Develop alongside EDF-03/05, not as a later port. |
| EDF-07 | Generate A200 EDF sibling and mass/geometry | Pending; generator freshness, identity, balance and turbine preservation. |
| EDF-08 | Catalog, controls, HUD, sound and contact behavior | Pending; actual product flow and internal-fan contact checks. |
| EDF-09 | Reproduce stand data and calibrate within domain | Pending; matched held-out physical data, separate from numerical checks. |
| EDF-10 | Qualify experimental flight, then compare actual aircraft separately | Pending; EDF-10a controlled software cards/replay; EDF-10b independent aircraft/pilot evidence. |
| EDF-11 | Run 152 mm and 195 mm scale experiments | Pending; each installation independently specified and admitted. |
| EDF-12 | Cross-platform/package/performance gates | Pending; target OS/backend identities and production workload evidence. |
| EDF-13 | Optional Workshop/failure/scenario integration | Pending; explicit consumer gates, no silent import/seed migrations. |
| EDF-14 | Physical promotion and documentation closeout | Pending; physical claims match evidence, reproducible delivered sources. |
| EDF-15 | Bounded inherited turbine repair | Pending; AV-owned low-speed defect reproduced and separately reviewed. |

### Dependencies and evidence tracks

Step numbering is an ownership register, not a requirement to wait for hardware
measurements before developing a synthetic model.

| Outcome | Prerequisites / exit |
| --- | --- |
| Runnable synthetic native stand | EDF-01 contract and numeric budget + EDF-02a assumed fixture → C++ EDF-03/04 analytic and circuit checks. No measured fan data are required for this software claim. |
| Experimental playable A200 | Qualified stand → EDF-05/06 complete native capability, including admitted controls/weather/contact/world → EDF-07/08 generated sibling/product → EDF-10a software flight. No reference product fallback; unmeasured outputs remain labeled estimated. |
| Measured installation claim | EDF-02b acquisition with independent runs → EDF-09 held-out physical cards → EDF-10b aircraft/pilot evidence → EDF-14 scoped promotion. Missing data leave this track inconclusive. |
| Larger fan studies | EDF-11 may begin on the qualified stand; each flight installation repeats the applicable software and physical gates independently. |
| Distribution | EDF-12 applies to the actual package/backend being distributed; it does not turn synthetic data into physical evidence. |
| Other work | EDF-13 is explicit optional scope. EDF-15's inherited turbine repair is not a dependency of a synthetic EDF law. |

### EDF-01 — Freeze the experiment and contracts

1. Record turbine baseline source/config/model/backend identities and the exact
   preservation surface. Confirm the new sibling's catalog/display IDs.
2. Specify reference planes, thrust/spin axes, map power basis, external wrench
   and shaft-load ownership. Review the ideal-stator and windmill counterexamples.
   Transform a measured moment to authored O once, then let the adapter apply
   `M_CG = M_O - r_CG_from_O cross F` once before the body/rotor solve.
3. Select one pack, controller mode and rotation sense for the first slice;
   distinguish provisional estimates from measured values.
4. Freeze schema/module versions, state blocks, observer fields and unsupported
   consumer choices. Give native and reference the same inputs and error contract.
   Include current `WindFlow` station/receipt semantics, catalog ideal/pack paths,
   smoke/legacy-audio behavior and initialization branches.
5. Prototype domain-diagnostic transport before promising all-stage coverage.
   Current `VehicleModel` stage context reaches the k1 substep selector, not a
   general accepted-stage reducer. Qualify a generic accepted-path receipt
   extension or compatible owner-controlled step policy that retains only final
   accepted stages/substeps, preserving event bisection and rollback. Keep EDF
   dispatch outside Simulation. An endpoint-only first version is permissible
   only with an explicit limitation: it cannot certify intermediate-stage support.
6. Define physical-domain versus event-locator trial continuation and its bound
   over admitted dt/states. If the existing stop/exhaustion locator cannot use
   the law, prototype a compatible guarded owner policy before session coding.
7. Freeze the per-observable numerical software accuracy budget.
   Specify units, norm, absolute floor, relative scale, duration, event timing,
   energy residual and oracle. No post-result choice of a passing tolerance.
   Freeze each applicable physical-card protocol after identifying its hardware
   and instruments, before acquiring or inspecting final held-out observations.
   Exploratory/fit data may inform that protocol but cannot also validate it.
   Unavailable physical acquisitions do not block the synthetic software track.
8. Have the Good Enemy review physical consistency and the smallest viable
   architecture. Resolve concrete findings before runtime coding.
9. Prototype the generic native boundary with SF/NK, using the
   [native design](../research/edf-propulsion/native-runtime-design.md). Inventory
   every state-affecting path, including initialization, raw-input conditioning,
   turbulence RNG, ground/crash/damage effects and checkpoint/restore. Specify
   command capture, consumption and rejection timing, pause/rearm behavior and
   precommit versus postcommit faults before moving ownership. A post-conditioned
   `.orfl` tape cannot prove this raw-device boundary.
   Freeze the proposed opt-in publication order: complete body/session/world
   commit → event notifications → step notifications. Current ordinary ticks
   emit events before the session's stepped damage commit; their reset/restore
   observer guard is not a universal tick guard. Define detectable observer
   violations, allowed pause/read access, transition reentry, notification
   continuation and recording completeness. Preserve legacy non-EDF semantics.
10. Freeze native Godot stand/preview/flight/debrief scope and capability refusal
    across every entry route. Set bounded map/workspace sizes and compiler/ABI
    identity. Optional JSBSim/OpenVSP comparisons are offline cross-checks with
    matching assumptions and provenance, not replacement solvers or new runtime
    dependencies.

**Proof:** signed-off specification and T01–T07/T10/T11/T15 test designs with independent
expected results. EDF-A11 identifies a concrete transport limitation; prove the
smallest compatible design before extending a kernel protocol. T30/T31/T34
must expose a deliberately hidden GDScript numerical callback, stale mutable
world state and wrong raw-input sampling before full native flight is admitted.

### EDF-02 — Build an auditable data package

**EDF-02a — synthetic software fixture, first critical path:** define a compact,
finite map and electrical/installation parameters with units, named assumptions,
output-specific evidence flags, joint support and reproducible generator/hash.
No acquired static curve is required. Verify the analytic energy, signed-load,
event and interpolation cases before fitting hardware parameters. Keep estimated
parameter ranges as sensitivity bounds, not measured confidence intervals.

**EDF-02b — physical identification, parallel and conditional on acquisition:**

1. Record manufacturer part/revision, rotor/stator and controller setup; resolve
   DS-215 motor-name and old/new cell-range disagreements.
2. Preserve source URL, date, page/figure, exact acquired-file hash and allowed
   reuse. Digitize plots with uncertainty; retain source points and conversion.
3. Obtain or bound rotor inertia, equivalent motor resistance/no-load loss,
   shaft load and installation residual moment. Do not derive all from static
   thrust alone or call DC input a measured mechanical load.
4. Survey inlet/outlet open areas, duct bends, mounting and battery envelopes.
   Start with a labeled virtual installation if physical measurements are absent.
5. Split by independently acquired run/condition and hardware identity, not by
   arbitrarily withholding positions on the same plotted curve. Record each
   dataset's origin, calibration/validation role, units, timing/filtering/tare,
   source URL/date/hash and acquisition/redistribution rights.
6. Preserve the joint sampled locus/cells rather than the Cartesian product of
   scalar extrema. Identify what each output actually measures; estimated torque
   and moments cannot inherit a measured-thrust label. Use independent wind-on
   and transient observations to discriminate otherwise indistinguishable fits.
   Report regression rank/conditioning and parameter ambiguity, not only fit
   error. Retain support/tare interaction and output-specific uncertainty. Use
   actual rotor diameter/chord, hub ratio, Reynolds number, helical Mach, blade/
   stator geometry and clearance in each scaling manifest; casing diameter is
   not rotor diameter and no dimensionless similarity is assumed without evidence.
7. If acquisition is unavailable, continue EDF-02a software work and mark EDF-09
   physical cards inconclusive. Do not fabricate missing measurements or a full
   measured support envelope from nominal manufacturer ranges.

**Proof:** EDF-02a supplies the reproducible synthetic fixture needed by the stand.
EDF-02b additionally supplies acquisition and independent-run manifests before
physical calibration; absent quantities block only their corresponding claims.

### EDF-03 — Implement pure fan/duct mechanics

1. Add pure native scalar-double map evaluation with explicit units and
   deterministic interpolation; use packed-float64 only at the outer boundary.
   Evaluate thrust, shaft load and installation wrench together. Prepare axes,
   supported cells/holes, knot ownership and bounded search once. No live CFD or
   dynamically allocated per-stage tables; a lookup hint must not change results
   when event trials or RK stages query out of order.
2. Add finite stopped/freewheel and windmill behavior without dividing by zero RPM;
   retain physical negative net thrust and distinguish reverse inflow.
3. Compute local stage inflow at declared stations and transform force/moment to
   the required datum. Register the EDF station in existing WindFlow and consume
   its already-local velocity once. Test uniform/gradient wind with nonzero body
   rate and moved datum. Bound the finite-disc/body-rate approximation near stop.
   Do not add measured ram/duct effects twice.
4. Feed shaft load and complete external wrench separately to the existing
   body/rotor balance. Validate carrier inertia and rotation convention.
5. Establish limits, characterize continuity and derivative discontinuities at
   map knots, and prove finite outputs, passivity/energy behavior by regime and
   diagnostic domain flags before session integration. Use the exact coupled
   rotational-energy identity, including its cross term, and the scoped complete
   installation aerodynamic passivity inequality from the physics study.
6. Test admitted cell interiors independently: passing vertices and monotone
   scalar interpolation do not prove a coupled power inequality. At one fixed
   physical input, common convex weights on complete load tuples preserve an
   affine passivity inequality; independent thrust/torque blends do not. Keep
   those two claims distinct. Defer cubic smoothing unless its error, domain and
   passivity behavior justify it (R2-01/09, T32).

**Proof:** T02–T06, including nonzero shaft power and nonzero opposing rotor/stator
fluid moments with zero net axial angular-momentum flux at both flow boundaries,
zero net external axial torque, correct spin-axis conventions, mirrored-fixture
reflection symmetry, and signed-flow/passivity counterexamples.

### EDF-04 — Integrate electrical behavior and numerical admission

1. Reuse the single-bus pack/motor solve, respecting duty-dependent motor versus
   battery current. Check terminal/DC power, losses, coupled body/rotor energy
   and fixed-parameter RC storage separately. Do not equate terminal-energy
   telemetry with chemical depletion or omit variable-parameter storage residuals.
2. Add the selected current/ramp behavior with explicit state/sample convention;
   current limiting must affect torque/effective duty and voltage consistently.
   Freeze the averaging/sensor bandwidth; phase switching peaks and cycle-level
   protection remain unmodeled by an algebraic 240 Hz motor/ESC approximation.
   Specify ideal isolation as the initial source-off circuit assumption, separate
   from aerodynamic windmilling, winding freewheel, braking and regeneration.
   For the declared simple ideal averaged circuit, evaluate the bounded direct
   current-limit root in R2-05 against an independent circuit oracle; qualify its
   feasibility, zero-resistance/current and saturated branches. It is not a
   universal hardware ESC model. Do not add a fast winding-current state to RK4
   without its own stability/accuracy contract (T33).
3. Repair the battery thermal admission omission under BAT ownership. Bound
   mechanical, fan-load, RC, electrical/thermal feedback and controller rates.
4. Keep the ideal prescribed-bus mode a separately identified lab mode. Qualify
   finite-pack launch, weak-cell cutoff and low-SOC infeasible operating points.
5. Add motor/ESC thermal states only with an explicit estimated or measured model;
   otherwise report their temperatures/derating as unmodeled and restrict claims.
   Identify pack RC behavior with pulse/rest and held-out mission observations.
   The existing lumped heat law omits reversible entropy heat and spatial hot
   spots; voltage agreement cannot qualify temperature or the hottest cell.
6. Begin spool response with coupled shaft inertia, motor and fan torque. Add a
   controller lag only when separately identified; defer extra dynamic-inflow
   states until their physical storage/work and independent observations exist.

**Proof:** T04/T07–T10, including the frozen 240 Hz accuracy limits as well as
refinement. No hidden power/current clipping, no post-step temperature
clamp used to conceal stiffness, and no presumed manufacturer current capability.

### EDF-05 — Own state, events and replay transactionally

1. Add explicit continuous/sampled blocks to the fixed-wing adapter; pin state
   layout and law identity. Store every new dynamic state in checkpointed data.
   Implement the vehicle-generic native tick behind the existing facade. Port
   all required sampled controls/weather, RK stages, substep/event policies,
   endpoint projections and validation together; wrapping native RK4 around
   GDScript numerical callbacks is not sufficient.
2. Extend airborne initialization and runway spin-up. Solve source-off freewheel
   equilibrium when it exists; the current glide helper's hard-coded zero RPM
   is not a windmilling equilibrium. Distinguish static hold, stable rotating root,
   no admissible root and a deliberately transient stopped launch.
   An instantaneous trim freezes specified SOC/T and actual RC/filter/controller
   state while solving body/shaft/bus residuals; a conditioned trim additionally
   solves declared feasible RC/filter/controller steady conditions at fixed SOC/T.
   Neither is equilibrium of a discharging full pack: retain real charge, energy,
   thermal and transient controller derivatives. Pin held output/sample phase and
   verify expected first-tick drift without silently replacing rested pack state.
3. Compose stop/exhaustion/source-loss/current/LVC events with existing contact
   subdivisions. Sample discrete supervisors at their declared boundary only.
   Preserve the locator's finite moving-side negative trial RPM/charge extension,
   including nonzero zero-speed fan load and complete wrench. It is numerical
   continuation, never an accepted reverse-spin/negative-SOC mode. Prove its probe
   bounds, or qualify the guarded composition selected in EDF-01.
   A one-sided rotor must refuse unsupported reverse breakaway atomically rather
   than invent a holding reaction. Qualify forward breakaway and static hold.
4. Verify reset, pause, rejected reload, fault, rollback and restore preserve the
   whole accepted frame and source identities. Include RNG, pending damage,
   active collision proxies, crash/restart decisions and effects that influence
   the next tick. Immutable geometry alone cannot represent broken scenery.
   Restore the checkpoint's world version: a pre-break checkpoint restores intact
   proxies, while a post-break checkpoint retains the recorded damage.
   Native preparation qualifies each admitted world; an airborne no-contact
   fixture does not qualify runway starts or landing.
   Publish observer state once. A precommit failure retains the preceding
   accepted frame. Under the proposed native publication guard, detected
   protected-state mutation, forbidden synchronous transition reentry or explicit
   observer failure after commit keeps the new accepted frame and pauses/faults.
   Qualify this ordinary-tick extension separately from existing reset/restore
   guards; arbitrary engine/process failure is not implied to be recoverable.
5. Extend trace and `.orfl` metadata with map/installation/controller identity;
   reject mismatched playback rather than substituting a sibling/backend.
   Implement the diagnostic scope frozen in EDF-01. An all-stage claim needs the
   qualified accepted-path transport; rejected trials publish nothing. Test a
   k2-only excursion, rejected subdivisions and rollback. An endpoint-only mode
   must disclose its narrower scope. Physical evaluations enforce the admitted
   envelope; locator-only continuations follow their separate contract. Neither
   can turn arbitrary malformed input into a recoverable boundary crossing.
6. Preserve one simulation owner and detached previous/current snapshots with
   explicit lifetime. Rendering never feeds interpolation back into physics.
   Qualify raw-device capture → native conditioner separately from `.orfl`
   post-conditioning replay, including arming, rates/expo, keyboard slew, yaw
   filtering, turbulence sampling, rejection and pause/reset. Defer live-tick
   worker parallelism; independent offline cases may use the admitted pool.
   Compare render cadences with identical timestamped event/tick assignments or
   accepted tick samples; measure live input delivery/arming latency separately.

**Proof:** T11–T15 plus the 240 Hz accuracy budget and 240/480/960 Hz refinement.
Include an analytic within-tick stop, momentum-preserving projection, simultaneous
exhaustion/cutoff, near-coincident contact, wrong-map refusal and source-off trim.
T30/T31/T34 additionally cover native capability closure, hit/second-pass effects,
both pre-break and post-break restores, rejected hits, raw input and RNG progression. Define
supported grazing behavior; a sign-changing bracket is not a universal detector.

### EDF-06 — Qualify the native implementation from the same specification

1. Prepare immutable EDF map/geometry/electrical data and explicit layout checks.
   Pre-size private stage/candidate/event workspace at admission and reject
   oversized declarations. Keep a single outer Godot publication boundary;
   measure allocations and copies rather than claiming current NK-3 is zero-copy
   or allocation-free. Avoid repeated steady-state searches for a direct map/bus.
2. Preserve qualified scalar arithmetic order, discontinuity policy, FP flags,
   contraction, math-library and FP-environment behavior. Keep the pinned Godot
   ABI precision separate from double simulation values. Defer SIMD, fast math,
   GPU physics and worker changes until independently qualified and measured.
3. Extend source/configuration/live-context guards and backend identity. Verify
   complete native selection, prepare refusal and live tick refusal. Missing
   EDF capability disables the product launch; there is no automatic reference
   fallback. Map bytes that disagree with declared integrity/source identity
   fail both the native route and explicit verification oracle. Use traps for
   GDScript numerical callbacks and mutation controls proving actual native work.
4. Run the existing native policy: at least 10,000 states, required byte parity
   on matching engine/toolchain, exact kernel trajectories, invalid-input,
   fault/restore and actual native-call coverage. Extend comparison to complete
   eventful ticks, native input/weather/world effects and restored continuation;
   stage parity alone cannot qualify the full path.
5. Bind platform engine/library/source/data/toolchain receipts. A fallback pass
   does not count as native coverage; do not claim cross-platform byte identity
   from a same-platform comparison.
6. Add bounded native map/checkpoint fuzz targets, independent analytic/property
   tests and separate ASan/UBSan builds; TSan is relevant if concurrency is
   introduced. Record instrumentation limits and deliberate positive controls.
   UBSan's default undefined group excludes floating divide-by-zero. Diagnostic
   builds do not supply release performance measurements (R2-13).

**Proof:** T16/T17/T30–T34, the [native guide](../../research/native-kernel/README.md)
and the proposed [full-path contract](../research/edf-propulsion/native-runtime-design.md).
Reference-only execution remains an explicit verification tool, outside the
native EDF product entry. All generic-kernel changes need owning SF/NK review.

### EDF-07 — Generate the A200 EDF installation

1. Create a dedicated EDF source/generator path that reuses airframe inputs,
   preserves existing node names and cannot overwrite turbine outputs by default.
   Generate distinct ideal-lab and finite-pack sources for the selected catalog
   mapping; preserve source/state-layout identities when switching modes.
2. Remove the documented turbine/fuel-only components, resolve bundled avionics,
   add fan, motor, controller, packs, ducts, wiring and mounts, and regenerate
   mass/CG/inertia. Do not inherit automatic fuel-specific ballast or balance.
3. Check internal and external envelopes, duct-area ratios, cooling paths and
   thrust line. Record any virtual inlet/outlet modification on the same airframe.
4. Regenerate contact/gear support and affected physical/model descriptors; run
   fresh-loader consumers, not only generator freshness.
5. Preserve turbine generator `--check`, source bytes, catalog IDs and matching
   baseline recordings; independently trim the EDF at its own mass/power.
6. Generate a presentation-only installation preview from the same authored
   fan/duct/pack/CG data. Independently check simple component mass tensors and
   signed battery-mount changes, optionally with a versioned OpenVSP calculation.
   A consistent virtual mesh and mass report do not establish measured fit.

**Proof:** T18/T19 and a mass/geometry report showing unknowns. The current
72 mm surrogate exit is a fit investigation input, not a ready EDF nozzle.

### EDF-08 — Make the experimental variant usable

1. Add a distinct catalog/model entry, Home description and direct-flight route;
   use the same logical radio commands, gear and flap controls. Verify the actual
   loaded law against the `data`/`battery_data` ideal/pack label in Home, direct
   launch, saved preferences and restart; finite pack is the fresh-preference
   default, without overriding a previously saved supported ideal selection.
2. Show pack charge, volts, battery amps, power and fan RPM from accepted state;
   distinguish ideal-bus mode, estimated maps and unmodeled thermal quantities.
   Add native Godot stand → installation preview → flight → debrief views. The
   stand uses ordinary commands and its own declared force boundary, with the
   same kernel family/data as the aircraft, not a misleading installed-thrust
   claim. Give labels text/symbols, keyboard/controller focus and explicit
   unavailable quantities; show current limiting only from an accepted result.
3. Add explicit EDF audio selection. Rotor blade-pass frequency can inform sound
   design, but sound must never feed back into physics; preserve licensing and
   use a safe labeled fallback until a matched recording is available.
   Explicitly support or disable the legacy soundscape route, whose current
   dispatch excludes only `electric_prop` and reads combustion-style `max_rpm`.
   Feed new native audio code a detached accepted epoch/tick/RPM/load/source
   snapshot; bound queues and handle stale epochs, pause and reset. Band-limit
   procedural harmonics using actual output sample rate. At 14 blades and
   45,000 RPM the third harmonic is 31.5 kHz, above a 48 kHz stream's 24 kHz
   Nyquist frequency. Real-driver PCM/listening and identical audio-on/off
   checkpoints are distinct gates; Dummy-driver routing is not acoustic evidence.
4. Exclude the internal rotor from exposed-prop strike inference and update
   crash energy metadata. Retain hull collisions and honest failure scope.
   Select an EDF-safe stock smoke profile (initially no show smoke): shared Avanti
   visuals currently select a turbine-bound `show_tailpipe` profile by family.
   Check both default and explicitly requested show/legacy presentation without
   invalid source bindings; preserve the turbine sibling's effects.
5. Verify actual Home → stand → preview → runway/airborne → debrief → Home → restart
   flows, controller arming and source-off behavior. Preserve saved selection.
6. Exercise an in-flight out-of-domain fault. Publish one visible paused/fault
   state with reason and retained accepted frame, prevent endless retries/false
   elapsed flight, preserve recorder completeness semantics, and allow reset/Home
   without a silent propulsion-law/backend switch. Verify ordinary starts and
   the declared maneuver envelope do not immediately trigger this path.
7. Enforce full native capability on Home, direct launch, restart, restore and
   any subsequently admitted Workshop route. Describe the unavailable feature
   plainly to the user; detailed ABI diagnostics belong in the developer receipt.

**Proof:** T20–T23/T35, real rendered 1080p review under the shared display policy,
audio listening when available, and explicit evidence gaps otherwise.

### EDF-09 — Calibrate and independently validate the stand

1. Match fan/motor/controller, intake/nozzle, voltage measurement point, firmware,
   cooling and atmosphere to the source dataset.
2. Fit only the calibration subset. Report thrust, DC power/current, RPM, residual
   moment, transient timing and temperature with uncertainty and domain limits.
   Withheld samples from a single digitized curve remain interpolation checks;
   physical validation requires independently acquired runs/conditions and declared
   bandwidth, uncertainty coverage/correlation and campaign decision rules.
3. Test independent voltage/SOC, wind-on and incidence points, not just static
   full throttle. Keep rotor shaft torque measurements separate from balance torque.
4. Apply the matrix's predeclared pass/fail/inconclusive rule. Promote only when
   error plus uncertainty meets the limit; distinguish demonstrated failure from
   an inconclusive interval instead of treating every non-pass as failure.
5. Test parameter identifiability, tare effects and sensor/ramp bandwidth before
   adding model order. Battery pulse/rest calibration, independently acquired
   mission temperature and fan transients qualify different claims. Extra thermal
   or inflow states need evidence beyond improvement of one fitted trace.

**Proof:** V01–V05 for available matched data; missing observations remain
inconclusive and do not prevent EDF-10a synthetic flight. A plot fit and native
parity do not close physical validation.

### EDF-10 — Fly controlled experiment cards

**EDF-10a** is software flight acceptance for the declared estimated/identified
law; it requires the applicable EDF-03…08 gates, not completion of physical
EDF-09. **EDF-10b** adds independently measured aircraft outcomes and pilot
assessment for the corresponding physical claim.

1. Preserve baseline recordings separately for turbine and EDF; exact replay is
   checked within each matching model/law/backend.
2. Run runway takeoff, trim, partial/full throttle acceleration, climb, go-around,
   throttle-off descent, windmill restart, approach with flaps and landing.
3. Test high incidence, gusts, hot/high density, low-SOC cutoff and repeated
   flight/reset. Record T/W, power, mass, duration, ground roll and domain flags.
4. Compare sibling flights with controlled conditions and separately trimmed
   starts. A single post-conditioned input tape does not retrim the aircraft or
   model pilot adaptation; do not force an incompatible turbine replay into EDF.
5. Obtain pilot acceptance separately from software and physical parameter gates.

**Proof:** T24 with complete recordings, identities and numerical limits for
EDF-10a; V06 and applicable EDF-09 evidence for EDF-10b. Report their status separately.

### EDF-11 — Expand to 152 mm and the oversized 195 mm experiment

1. Define and run each size's separately identified synthetic stand configuration
   with its own map and power budget, labeling assumptions. Compare an exact
   matched manufacturer setup only where sufficient acquired data exist. Do not
   scale the 128 mm coefficients by diameter alone.
2. Build a separate virtual installation manifest: casing/mount envelope, inlet,
   nozzle, cooling, actual or bounded pack mass, CG and full inertia.
   Include actual rotor diameter/chord, tip/hub ratio, clearance, helical Mach,
   Reynolds context and controller/motor identity for each size. Similar nominal
   diameter or static thrust does not establish similarity of installed behavior.
3. Apply the same schema, energy, event and numeric gates. Sweeps may vary pack
   mass, impedance and installation losses, but must label assumptions.
4. Admit an A200 flight only with an internally consistent explicitly modeled
   installation. If it requires a larger airframe, create a separately named
   vehicle concept rather than alter the reference A200's scale.
5. Run a small predeclared synthetic campaign: eight low/high combinations of
   pack resistance, battery mount mass and a physically coherent installation-loss
   assumption, plus a center case. Regenerate mass/CG and complete force/torque
   laws consistently; a thrust-only multiplier is not a sufficient loss model.
   Record source, map, generator, engine/native binary, card version, conditions,
   seed and outcome hashes for every case, including refusals. Report interactions
   as consequences of assumptions, not measured confidence intervals (R2-18/T36).

**Proof:** a per-size feasibility matrix: supported simulation experiment,
unresolved physical fit, or different-airframe requirement. Physical promotion
always requires the actual installation's evidence.

### EDF-12 — Qualify packages and performance

1. Run required CI unchanged, inspect actual tested commit/merge SHA and capture
   engine diagnostics as well as process exit codes.
2. Verify EDF native preparation, recording, restore, cold start, restart and
   clean shutdown in each advertised Windows/Linux/macOS package/architecture.
   Match the actual engine, extension API, bindings, precision ABI, compiler,
   library and dependencies. Missing/incompatible native support disables EDF;
   existing non-EDF fallback remains unchanged. Do not assume editor loading or
   upstream master compatibility proves exported behavior; preserve
   `reloadable=false` and fresh-process lifecycle qualification.
3. Measure four scopes separately: pure law, Godot bridge, complete numerical
   tick and full live callback including observers. Record raw p50/p95/p99,
   event-tail/max observations, counts/warmup, allocation/copy costs and frame
   pacing. Current smoothed `step_usec` ends before observers and is not the
   full callback. Apply the existing 500 µs gate with its owning statistic and
   workload; 240 Hz gives a 4,166.7 µs period, not permission to consume it all.
   Use matched uninstrumented release runs for the gate and scoped profiling
   for attribution; no speedup is assumed from native code alone.
4. Keep renderer/display/hardware identity and the shared 1080p/Retina policy.
   Headless, software-rendered or emulated results do not qualify hardware feel.
5. Reuse the [tool index](../tools/README.md), openrc-tools/debug, native, audio
   and flight-test workflows. The Blender-oriented physics-sim skill is not an
   RC solver guide. Pin any later external tool/action/asset with provenance,
   version, license and retained evidence; no new skill/plugin is required by
   this research. Serialize competing performance runs under existing admission.

**Proof:** T25–T27/T36, unchanged sibling regressions, required CI and package receipts.

### EDF-13 — Extend optional consumers deliberately

1. For Workshop, regenerate descriptors and qualify new fan/intake/nozzle offset
   rebasing under mass edits, finite-pack trial policy, save/export/load and restart.
2. For failures, explicitly implement/test source-loss semantics or keep EDF out
   of that catalog; no turbine flameout substitution.
3. For Natural Random, retain old v1 ordering and seed results; a new EDF-aware
   policy is versioned. Audit companion/trim assumptions before admission.
4. Keep Creator's imported-EDF-as-turbine approximation labeled. Automatic
   conversion needs its own hardware/data and migration plan.

**Proof:** T28 and the owning AE/EM/NR/AC acceptance gates. Exclusion is a valid
first-slice decision when clearly communicated and enforced. An admitted optional
EDF route must satisfy the same native closure; inclusion cannot reintroduce a
GDScript numerical or failure-policy fallback.

### EDF-14 — Promote only what the evidence establishes

1. Review the complete evidence chain from source and generator to package and
   flight. Record supported operating domains and remaining estimates.
2. Keep the variant experimental until physical and pilot gates pass. A research
   aircraft may remain useful indefinitely without a manufacturer-validation claim.
3. Consolidate completed implementation instructions into the owning guides;
   retain valuable sources, maps, assumptions, receipts and open work.

**Proof:** a scoped promotion record, not a blanket “all tests passed” statement.

### EDF-15 — Repair the inherited turbine boundary separately

1. Reproduce EDF-A02 in the pure reference/native laws with accepted A200 rows.
2. Establish actual source-on/off/start reachability and the intended low-RPM
   domain, then choose a finite continuation or explicit rejection.
3. Verify stopped/idle/full endpoints, finite fuel, native parity and matching
   turbine replay. Review this AV repair independently from the EDF conversion.

**Proof:** T29. No repair, new golden or broadened turbine realism claim is
implied by discovering the issue in this research.

## 6. Acceptance boundaries and stop conditions

| Gate | What can be claimed | What still cannot be claimed |
| --- | --- | --- |
| Research delivery | Sources, equations, audit and implementable sequence reviewed | EDF implemented or flyable. |
| Pure numerical stand | Defined equations, signs, domains and conservation verified | Correct hardware parameters or installed performance. |
| Experimental playable sibling | Coherent generated data, complete qualified native numerical path, lifecycle, controls and ordinary flight work | Measured A200 fit, endurance or pilot realism without the separate evidence. |
| Physically qualified installation | Stated measured outputs satisfy predefined uncertainty-aware limits within a named domain | Universal EDF accuracy, arbitrary scaling, untested controller modes or other aircraft. |
| Package/target qualification | The measured platform/backend/renderer route passes its gates | All hardware, fallback paths or other OS architectures. |

Stop promotion when the energy ledger cannot close, maps require unsupported
extrapolation without a declared continuation, new dynamics exceed qualified
integration bounds, admission silently routes to another family, or evidence is
missing for the claim being made. Preserve the current accepted state and explain
the concrete reason. This does not require asking again for permission to carry
out already authorized branch work.

## 7. Immediate next implementation change

Start with **EDF-01's generic native-boundary prototype plus the C++ analytic
stand portion of EDF-03**: freeze a minimal map/interface, implement the separate
shaft-load/installation-wrench outputs and prove zero-swirl, spool, windmill,
zero-speed and interpolation-interior cases. In parallel prepare EDF-02's
synthetic data, BAT thermal-admission regression and raw-input/world capability
inventory. Extend through a qualified native transaction before admitting the
A200 product flight. Aircraft generation follows those contracts.
