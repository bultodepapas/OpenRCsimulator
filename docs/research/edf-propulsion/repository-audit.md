# Repository audit for EDF propulsion

**EDF-00 · 2026-11-21 · Baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`.**
This is a source audit and implementation handoff. No runtime repair or EDF flight
is delivered by this research branch. Line references below apply to that pinned
revision; the linked symbols remain the useful lookup points after code moves.
The [plan](../../plans/edf-propulsion.md) owns work order and the
[validation matrix](validation-matrix.md) owns proposed proof.
EDF-00-R1 independently rechecked the original research candidate and added
EDF-A12…14 plus concrete catalog/presentation paths. The
[external audit](external-audit-2026-11-21.md) owns the proposal corrections and
the inherited CI blocker; source line references still target the baseline above.
EDF-00-R2 rechecks the unchanged runtime tree at `9d17c29ed2463cdb3a67d3bd573c0137587edb9d`
and adds EDF-A15: the existing native stage is insufficient for the owner's
complete-native EDF requirement. This is an extension prerequisite, not a newly
discovered failure of the current stage-only contract.

The lead read root `AGENTS.md`, `docs/SUBAGENTS.md`, relevant scoped rules,
architecture, track ownership, aircraft/propulsion/battery guides and CI tooling.
Three bounded source-read-only specialists supplied primary-source research,
electric/turbine analysis and Good Enemy review. Source and arithmetic were
checked by the lead before integration. Requested helper routing was
`gpt-6.1-terra` / `max`, as allowed by the repository; effective runtime routing
is not independently observable. No helper staged, committed or pushed files.

## 1. What already exists

| Boundary | Existing implementation and meaning | EDF work |
| --- | --- | --- |
| Kernel | [Simulation](../../../app/sim/simulation.gd), [VehicleModel](../../../app/sim/vehicle_model.gd): fixed 240 Hz, float64, RK4, events, atomic publish, checkpoints and rollback | Preserve one shared transaction and model-owned laws; propose a generic complete native tick, without an EDF branch or second solver. |
| Flight orchestration | [FlightSession](../../../app/sim/flight_session.gd), [propulsion runtime](../../../app/sim/aircraft_propulsion_runtime.gd) | Extend explicit family/capability dispatch, layout, trim, reset and telemetry. |
| Source and shaft | [electric_motor.gd](../../../app/physics/electric_motor.gd), [propulsion.gd](../../../app/physics/propulsion.gd), [rotor_coupling.gd](../../../app/physics/rotor_coupling.gd) | Reuse electrical conventions and simultaneous rotor/body balance; separate fan shaft load from installation wrench. |
| Supply | [electric_supply.gd](../../../app/physics/electric_supply.gd), [pack_ecm.gd](../../../app/physics/battery/pack_ecm.gd) | Reuse stage bus solve and pack state; add identified ESC current/ramp behavior and new numerical bounds. |
| Events | [electric_battery_step.gd](../../../app/physics/electric_battery_step.gd), FlightSession battery endpoints | Preserve one transactional owner for contact subdivisions, source loss, exhaustion, stop and LVC sampling. |
| Spatial air | [wind_aircraft_flow.gd](../../../app/physics/wind_aircraft_flow.gd), [dynamics.gd](../../../app/physics/dynamics.gd) | Register an EDF intake station; consume the stage's local inflow once, preserving gradient, datum and receipt identity. |
| Initialization | [trim.gd](../../../app/physics/trim.gd), FlightSession launch preparation | Add stopped/freewheel source-off branches and explicit finite-pack snapshot semantics. |
| Turbine sibling | [turbine.gd](../../../app/physics/turbine.gd), [liquid_fuel_flight.gd](../../../app/sim/liquid_fuel_flight.gd) | Retain turbine law and finite fuel; EDF must not inherit fuel burn, turbine spool or ECU claims. |
| Aircraft admission | [aircraft_modules.gd](../../../app/physics/aircraft_modules.gd), [aircraft_data.gd](../../../app/physics/aircraft_data.gd), [v2 contract](../../../app/data/schema/aircraft-contract-v2.json) | New family, conditional fields, units, quantities, capability/energy combinations and invalid-data refusal. |
| Data sources | [AV-06 generator](../../../research/avanti-s/av06/derive_physics.py), [AV-06 inputs](../../../research/avanti-s/av06/inputs.json), [battery generator](../../../research/battery/bat-05/build_batteries.py) | Separate reproducible EDF inputs/output and pack identity; generated JSON is not an editing surface. |
| Native backend | [native_stage.gd](../../../app/sim/native_stage.gd), [native kernel source](../../../research/native-kernel/src/), [admission guide](../../../research/native-kernel/README.md) | Current stage boundary needs generic native tick/control/weather/world closure; prepared data/workspace, exact verification, strict EDF product admission and measured boundary cost. |
| Product | [catalog](../../../app/app_state/aircraft_catalog.gd), [model registry](../../../app/aircraft/model_registry.gd), audio, HUD, Workshop, failure/scenario consumers | Register a separate experimental sibling, support each route or explicitly exclude it. |

The aircraft contract explicitly excludes EDF duct/fan momentum from the current
v2 model. `electric_prop` currently means an exposed-propeller law with its own
assumptions. Existing electric and turbine modules are substantial; replacing
them wholesale or presenting their existing features as missing would be wrong.

## 2. Findings and evidence classification

**P1** means a prerequisite to admitting the proposed EDF behavior; **P2** means
a bounded repair or extension gate. These are planning priorities, not claims of
observed crashes. A source-confirmed defect, a disclosed approximation and a
conditional regression trap are different findings.

| ID | Priority | Classification | Finding / disposition |
| --- | --- | --- | --- |
| EDF-A01 | P1 for new thermal data | Confirmed source omission + analytic counterexample; integrated reachability untested | Pack thermal cooling stiffness is absent from numerical admission. Resolve under BAT/EDF-04. |
| EDF-A02 | P2, separate AV repair | Confirmed direct-law defect; normal-flight reachability unproven | Low-RPM turbine flow extrapolation can be negative and gross thrust singular. Reproduce and choose a low-speed policy before changing runtime. |
| EDF-A03 | P1 | Conditional EDF regression | Open-propeller torque is also used as external roll torque; add stator/duct-aware wrench separation. |
| EDF-A04 | P1 | Disclosed model limit | Sub-1-RPM non-glow propeller loads are zero; define finite EDF stopped/windmill behavior. |
| EDF-A05 | P1 | Contract gap | New propulsion enum alone does not update battery, carrier, module, native or trace admission. |
| EDF-A06 | P1 | Conditional EDF regression | An internal fan can be inferred as an exposed propeller collision disc. |
| EDF-A07 | P1 | Data/identity constraint | Turbine generator includes fuel-specific mass and virtual balancing; author the EDF sibling from owning sources. |
| EDF-A08 | P1 | Numerical/lifecycle gap | New RPM/ESC/fan states affect layout, event ordering, checkpoints and native guards. |
| EDF-A09 | P2 before product integration | Consumer gap | Unknown propulsion families can fall into propeller/combustion audio and telemetry paths. |
| EDF-A10 | P2, explicit exclusion allowed | Compatibility constraint | Workshop, failure modes, seeded scenarios and imported jets need separate admission decisions. |
| EDF-A11 | P1 before all-stage quality claims | Existing protocol limitation | Current stage context does not provide accepted-path receipts from every RK stage; prototype transport or disclose endpoint-only diagnostics. |
| EDF-A12 | P1 | Missed existing integration contract | Spatial weather already samples local propulsion flow and rejects unregistered families; extend its station definition and consume its receipt once. |
| EDF-A13 | P1 | Plan/event-contract conflict | Existing stop/exhaustion locators need beyond-boundary numerical trial continuation; blanket negative-RPM/charge refusal prevents localization. |
| EDF-A14 | P1 before source-off starts | Initialization gap | Glide trim hard-codes zero RPM; a windmilling fan may need a nonzero equilibrium, while a finite discharging pack cannot be fully steady. |
| EDF-A15 | P1 for native EDF flight | New requirement / shared architecture prerequisite | NK-3 is stage-native; input conditioning, integration/events and state-affecting session/world behavior still need a generic qualified native capability. No EDF product reference fallback. |

### EDF-A01: Battery thermal stiffness is absent from the admission bound

**Evidence.** `FlightSession._electric_step_supported` and `_pack_step_ratio`
(`flight_session.gd:467–511`) sum mechanical, charge, RC and filter rates. The
comment assumes thermal time constants are minutes, but does not enforce that.
`PackEcm.evaluate` (`pack_ecm.gd:187–195`) integrates
`Tdot=(heat-h*(T-Tambient))/Cthermal`, with forced cooling added to `h`.
`BatteryData` (`battery_data.gd:84–100,164–168`) independently permits small mass,
low specific heat and high heat transfer.

**Counterexample.** Choose mass 0.01 kg, specific heat 100 J/(kg K), still-air
transfer 720 W/K and no electrical heating. These scalar values satisfy their
individual bounds and give `Cthermal=1 J/K`. At 240 Hz, `lambda*dt=-3`.
RK4's stability polynomial is `R(z)=1+z+z²/2+z³/6+z⁴/24`, so `R(-3)=1.375`,
while exact cooling multiplies temperature excess by `exp(-3)=0.049787...`.
Starting at 298.25 K in 298.15 K ambient gives **298.2875 K** after one RK4
step instead of **298.1549787 K**. The numerical solution initially heats a
cooling-only pack.

**Scope.** Source and scalar arithmetic are verified. A complete registered pack
and aircraft fixture was not loaded or flown, and no shipped pack is claimed to
have these parameters. Other admission requirements still apply. This proves
the missing term and an unstable scalar continuation, not a catalog incident.

**Repair contract.** Add a conservative thermal/electrical bound over the
declared temperature and cooling-speed domain, or qualify a compatible
integration policy. Include temperature-dependent resistance/OCV feedback and
new ESC/motor thermal/ramp states. Do not merely hard-code this example's value,
raise the global timestep tolerance, or clamp the result after instability.
Preserve atomic refusal and matching native/reference behavior. Start with a
flat-table, no-current analytic cooling fixture and test boundary-adjacent cases.
Existing `test_battery_session.gd` includes charge/filter stiffness cases; it does
not establish this thermal bound. Ownership: BAT + physics, EDF-04 dependency.

### EDF-A02: Low-RPM turbine mass flow violates its stated nonnegative contract

**Evidence.** `Turbine.mass_flow` (`turbine.gd:120–126`) returns zero below 1 RPM
and otherwise extrapolates the first two mass-flow rows without a nonnegative
continuation. The accepted A200 rows are `(20000, 0.02987)` and
`(30000, 0.04481)` in RPM and kg/s. Their line is approximately
`-0.00001 + 0.000001494*RPM`.

At **1 RPM**, flow is **-8.506e-6 kg/s**. It crosses zero near
**6.6934404 RPM**. `gross_thrust` (`:129–138`) divides by that extrapolated flow
and then multiplies a square root by signed mass flow. With the current A200
installed factor 0.92, static conditions at 1 RPM produce about
**-7.866e-6 N**. At the mathematical zero the formula is undefined; nearby
floating-point behavior needs a focused engine test.

The same expressions appear in
[`nk_liquid_propulsion.hpp`](../../../research/native-kernel/src/nk_liquid_propulsion.hpp)
around lines 203–217. Current finite-fuel source cutoff suppresses powered loads
during rundown (`flight_session.gd:4657,4669`; `liquid_fuel_flight.gd:73–81`), and
ordinary starts are at idle. **Normal-flight reachability is unproven.**

**Repair contract.** Define the turbine's admitted low-speed/start/rundown
domain, test the exact stopped threshold and both sides of the flow root, then
add a finite, physically stated continuation or refuse the unsupported domain.
Check native parity and existing idle/full/finite-fuel behavior. This is an AV
repair, not a reason to implement EDF by copying turbine flow tables. No runtime
fix is included in this planning branch.

### EDF-A03 and EDF-A04: Reuse the rotor balance, replace the load contract

`Propulsion.prop_torque` feeds `Qmotor-Qprop` into the electric rotor balance
(`flight_session.gd:5028–5035`). `loads_from_thrust_torque` also creates a
`-Qprop*axis` external moment (`propulsion.gd:683–690,738–741`). This is consistent
with the existing propeller contract; it cannot represent stator recovery without
a new installation moment channel. Native paths mirror this in
`nk_electric_coupling.hpp` and `nk_prop.hpp`.

`RotorCoupling.response` already solves body/spin acceleration; the session adds
its reaction once (`flight_session.gd:5113–5128`), and the rigid-body derivative
consumes rotor momentum. EDF must not add those moments again. Non-turbine
`Dynamics.rotor_momentum` (`dynamics.gd:17–25`) assumes positive thrust-axis spin;
explicitly support either spin sense or reject an unsupported sense in data.

`prop_torque`, `thrust_torque` and `loads` suppress non-glow loads below 1 RPM
(`propulsion.gd:437–446,652–675`). This disclosed limit loses stopped-rotor drag
and aerodynamic start from rest. The new map needs a separate dimensional
low-speed law. Preserve signed flow and distinguish aerodynamic windmilling from
electrical regeneration; the current ESC does not recharge the pack.

### EDF-A05 and EDF-A08: Admission, state and identity are cross-cutting

Independent family checks exist in `AircraftModules` (`:101–105,228–248`),
`AircraftData._propulsion` (`:1223–1235`), the v2 schema, quantity paths and
conditional modules. Rotor carrier admission at `aircraft_data.gd:575–576` also
depends on `electric_prop`. `Propulsion.source_kind/is_electric` and
`AircraftPropulsionRuntime` branch on that exact kind. Unknown families must fail
closed; relaxing an enum alone cannot install EDF energy behavior.

`FlightSession` packs wash, RPM, battery and wheel state in a defined order
(`:4857–4875,4928–4934,4985–5004`). The native kernel independently checks counts
and indices (`nk_kernel.cpp:821–842`); snapshots and preparation also pin family
(`native_stage.gd:318–325`, `nk_stage_snapshot.hpp:158`). Traces label known laws
and layouts (`trace.gd:969–986,1058–1089,1246–1267`). New map geometry, interpolation,
controller policy, source kind and state layout must be included in identity.

Reuse the `electric_battery_step` semantics through a qualified native equivalent,
after checking subdivision, exhaustion/stop, LVC and source-loss ownership;
do not invoke the existing GDScript step callback in an admitted EDF flight. New state cannot live
in mutable helper fields outside checkpoint/rollback. Under EDF-00-R2, refused
native preparation disables the EDF product launch; existing non-EDF routes
retain their own fallback policy. A failed live guard must refuse the tick
rather than switch backend mid-flight. The EDF reference is a test-only oracle.

### EDF-A06: Internal fan must not become an exposed propeller collision disc

`HullContact.prop_disc` (`hull_contact.gd:93–104`) excludes `turbine` and otherwise
creates a disc from `diameter` and `offset`. FlightSession uses it for strike
detection (`:2446,3332–3334`). A normalized EDF that reuses those field names can
therefore acquire a fictitious exposed blade-strike surface.

Make exposed-prop contact an explicit capability or explicitly exclude the EDF
family. Keep genuine fuselage/duct contact under the hull owner. Verify no phantom
strike in low-airframe and water-contact cases, while existing propeller strike
behavior is preserved. This finding describes a future misintegration, not an
already installed EDF bug.

### EDF-A07: The sibling needs its own authored mass and installation

The AV-06 generator builds inventory, injects kerosene, adds virtual ballast and
balances against a fuel-specific datum (`derive_physics.py:427–482`). It emits
the tank (`:1004–1008`) and turbine/finite-fuel capabilities (`:1095–1145`).
Create an independent EDF source/configuration pipeline or a reviewed shared
airframe extraction with a turbine byte-preservation check. Do not hand-edit the
generated turbine JSON or let the new path overwrite its default output/report.

Reusing the visual family is reasonable; silently retaining its old mass range,
fuel-specific balance or installation coordinates is not. The
[sizing investigation](physics-and-sources.md#same-airframe-mass-budget) records
the exact modeled removals and unresolved bundled components. Existing generated
battery templates are estimates, not measurements of the proposed high-power EDF.

### EDF-A09 and EDF-A10: Explicit consumer support or exclusion

| Consumer | Source evidence / risk | First-slice decision |
| --- | --- | --- |
| Audio | `flight_audio.gd:246–251` uses propeller torque for non-turbines; `soundscape.gd:130–147` and `powertrain_audio.gd:27–44` have family defaults | Explicit EDF route, safe observer-only fallback, accepted RPM and load inputs; no raw propeller map access. |
| Legacy audio | `main.gd:1202–1205` excludes only `electric_prop` before reading `propulsion.max_rpm` for the old engine sound | Explicit EDF-safe handling or a declared unsupported option; compare default and legacy starts for both siblings. |
| Catalog energy mode | `aircraft_catalog.gd:263–265,316–328` maps `data` to ideal and `battery_data` to pack; `home.gd:1585–1591` follows that capability | Generate explicit ideal-lab and finite-pack paths, default to pack, and verify loaded law/labels in Home, direct launch and restart. Finite-only data needs an explicit capability change. |
| Workshop | Generated descriptors bind base bytes/modules/visual family; `mass_edit.gd:397–413` rebases known offsets | Initially exclude EDF editing unless generator, schema, mass rebase and trial lifecycle are qualified. |
| Failures | `failures/catalog.gd:271–282,291–311,348–362` checks specific kinds | Explicitly include a tested source-loss mode or show EDF as unsupported. Never fabricate turbine flameout. |
| Natural Random | `scenario_config.gd:16,83–85,495–506`; `natural_random.gd:28–30` indexes an ordered aircraft list | Preserve v1's existing list and seed mapping; a new EDF-enabled policy needs a new version. |
| Creator imports | `creator/packages.gd:44–46,553–558`; `creator/phoenix/physics.gd:76` adapt imported EDF/jet information into existing turbine behavior | Leave legacy imports labeled as approximations; no automatic migration in this Avanti task. |
| Replay / recorder | Source, model, law, state and backend identities are pinned | A new EDF flight gets a new identity; old turbine recordings remain on their matching solver. |
| Crash and smoke | Energy source is explicit inventory metadata. `stock_profile.gd:13–15,51–67,75–77` selects the Avanti show-tailpipe profile by visual family; `aircraft_customization.json` binds that slot to a turbine, and `resolve_smoke_bindings` (`app/render/aircraft_customization.gd:318–348`) checks the source | Author LiPo source metadata and an EDF-safe stock profile/exclusion. Exercise requested show smoke and default startup without binding errors; preserve the turbine's show effect. This is a presentation compatibility trap, not proof an EDF emits hot exhaust. |

### EDF-A11: All-stage domain reporting needs an explicit transport design

`VehicleModel` documents `stage_context` as input to the k1 substep selector
(`vehicle_model.gd:41–46,94–96`). Its step-policy derivative callback returns
derivatives, not a general stage receipt (`:68–77`), and the kernel accepts only
the declared stage keys (`simulation.gd:1242–1255`). A k2 evaluation can leave
measured support while k1 and the endpoint remain inside it; endpoint observation
cannot establish that every stage stayed in the measured domain.

EDF-01 must prototype either a qualified generic accepted-path receipt extension
or a compatible owner-controlled policy, with no EDF branch in Simulation. Only
the final accepted stages/substeps may contribute quality flags; rejected event
bisections, subdivisions and rolled-back ticks must publish nothing. An
endpoint-only first version is a valid smaller choice if its limitation is
explicit. Every evaluated stage follows its declared physical or locator-only
envelope and refusal rules; EDF-A13 defines the numerical-probe distinction.
T06 discriminates these cases. This is a proposed
feature's integration prerequisite, not an existing runtime defect.

### EDF-A12: Spatial propulsion inflow already has an owner

`WindFlow.StagePointSampler` (`wind_aircraft_flow.gd:17–38`) samples the station's
ambient wind at the same stage time and transforms its difference from datum
wind. `stage_air` (`:53–89`) returns already-local `propulsion_air_body`;
`geometry` (`:116,217–245`) currently recognizes turbine, glow/electric prop and none,
so an EDF kind fails station admission. The sample contract (`:263–265`) already
includes `omega cross r` and the wind delta. `Dynamics.loads_from_air`
(`dynamics.gd:72–83,90–127`) requires matching ephemeral stage receipts.

The original plan incorrectly called spatial wind a future feature. Register the
EDF intake offset, use the existing local velocity once, and keep model/time/
density/native identity. Qualify uniform and spatial modes or explicitly reject
an unsupported mode at admission. Extend `test_spatial_powered_stage.gd` and
`test_spatial_propulsion_flow.gd` with gradient, body rate and datum-shift cases.

### EDF-A13: Event probes are not accepted negative physical states

`EventStep` (`event_step.gd:1–10,39–73,84–103,116–142`) intentionally evaluates
negative trial values while bracketing a stop. A derivative refusal aborts before
the locator can refine. `electric_battery_step.gd:24–33,55–58,166–192,229–236`
composes this policy with charge exhaustion. `FlightSession._coupled_response`
(`:5015–5020,5061–5086`) distinguishes negative-RPM moving-side probes from an
exactly stopped rotor's static hold and forward/reverse breakaway.

An EDF adapter must preserve a qualified finite trial extension, including its
possibly nonzero zero-speed aerodynamic load and whole-installation wrench.
Never copy the open propeller's zero-load assumption into that extension. Prove
coverage of all admitted probes or use a qualified guarded composition that can
refine crossings without treating malformed maps as crossings. A narrow negative
bound with unconditional failure still fails a coarse otherwise legal probe.
The rotorcraft guarded locator is a precedent, not a drop-in replacement for
the fixed-wing battery/contact/LVC composition. Accepted RPM/charge remain
nonnegative. T11 uses an analytic within-tick stop and simultaneous boundaries.

### EDF-A14: Source-off trim and finite-pack snapshots need explicit semantics

`Trim._rpm` / `_rpm_at` (`trim.gd:70–86`) return zero outside level-flight trim;
the later electric equilibrium path (`:304–321`) also handles level mode only.
FlightSession exposes a glide start (`:2964,3973`). A source-off freewheeling EDF
can have nonzero equilibrium speed and drag, so solve that branch or explicitly
label/refuse a stopped transient start. Distinguish static hold, stable rotating
root, unsupported root and no solution; verify the initialized first-tick residual.

`PackEcm.initial_block` (`:55–70`) starts rested RC states. Its rates (`:180–195`)
include charge, terminal energy, loss, polarization, temperature and sensing, so
nonzero current precludes equilibrium of the whole joint state. Freeze a declared
pack/controller snapshot for instantaneous trim, or additionally condition named
RC/filter/controller states for quasi-steady trim at fixed SOC/T. Retain actual
resource derivatives and sample phase; do not silently substitute a loaded pack
equilibrium for a requested rested start.

### EDF-A15: Native stage evaluation is not a native numerical flight

**Evidence.** `native_stage.gd` installs NK-3 evaluation callbacks.
`simulation.gd` owns sampling coordination, RK4/substeps/events, endpoint
transitions, validation and publication. `flight_session.gd` retains stateful
input conditioning in `_physics_process`, sampled turbulence/RNG in `_pre_step`,
terminal crash/gear decisions in `_session_after_input`, and committed pending
damage/incidents in `_on_sim_stepped`. `collision_world(active_only)` filters
proxies using broken scenery IDs, so immutable world geometry alone cannot
reproduce the next tick. A stage call counter does not cover these paths.

The native C++ source already prepares configuration and reuses some buffers,
but `nk_kernel.cpp` also constructs stage dictionaries/packed arrays, and
`StageResult`/stage evaluation use vector storage. Source inspection does not
establish zero allocation or zero-copy. Current `step_usec` is smoothed and
recorded before observers, so it cannot stand in for complete callback latency.

**Disposition.** EDF-01/05/06 propose a generic native numerical-tick capability
behind the same shared facade, with native initialization, conditioning, weather
sampling, events and admitted mutable world/session policies. One accepted owner
must checkpoint all continuation state and distinguish precommit rollback from
the proposed detected postcommit observer-violation policy. Current
`Simulation._publish_committed_boundary` guards prepared reset/restore, while
ordinary steps emit `events_located` then `stepped` without the same guard;
session damage commits during the latter. The native opt-in proposes complete
world/body commit before both signals and must qualify visibility, mutation,
reentry and explicit failure reports without changing legacy listener behavior.
This is a new capability, not an existing universal fault guarantee.
EDF launch refuses missing capabilities;
the reference is an explicit verification oracle and non-EDF behavior stays
unchanged. See the [native contract](native-runtime-design.md) and R2-07…14/20
in the [second research round](native-research-2026-11-21.md).

**Proof required.** T30/T31/T34 native callback traps and mutation controls,
raw-input/RNG fixtures, hit/restore/rejected-hit world continuation, existing
matching-host parity plus full-tick comparisons, and T27/T36 allocation/callback
measurements on actual native packages. A stand with excluded contact cannot
qualify ordinary runway or landing behavior. No such implementation or target
measurement is delivered in EDF-00-R2.

### Reuse boundaries confirmed by the external audit

`multirotor/electric_bus.gd:1–8,25–34` is a useful active-set reference but has
exactly four loads and omits finite-pack polarization/thermal and ESC limits.
It is not the first EDF's single-load pack solver. `test_electrical_bank.gd`
tests atmospheric electrical effects, not propulsion power distribution.
`aircraft_ground_electric.gd:21–30,34–46,63–68` is a fixed-gear foundation with
`launch_available=false`, not a qualified retractable finite-pack A200 session.
Use the current single-shaft session as the first integration boundary, keeping
wheel/contact/retract and source-event composition explicitly owned and tested.

## 3. Investigation limits and verification ownership

The checkout uses sparse materialization. Tracked source files outside the
materialized tree were read with `git show <baseline>:<path>`; their absence from
disk does not mean the repository lacks them. Runtime work needs the required
sources, generated data, imports and pinned engine materialized before testing.

This audit did not launch Godot, run a flight, build a native library, collect
hardware measurements or listen to EDF audio. The two counterexamples are
reproduced algebraically in [calculations.json](calculations.json), with that
scope embedded in the report. The delivery's actual document/CI results are in
the [research index](README.md#verification-and-delivery).

Do not claim a repair from this report. For an implementation, start with the
smallest existing tests listed in the [validation matrix](validation-matrix.md),
add discriminating negative cases, then inspect required CI for the exact tested
tree. Existing software checks, new numeric checks, measured propulsion fidelity
and target-hardware flight performance remain distinct gates.
