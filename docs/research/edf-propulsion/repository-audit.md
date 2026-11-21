# Repository audit for EDF propulsion

**EDF-00 · 2026-11-21 · Baseline `57abea025f62b20233ca281d58d2acbee4ab8b8e`.**
This is a source audit and implementation handoff. No runtime repair or EDF flight
is delivered by this research branch. Line references below apply to that pinned
revision; the linked symbols remain the useful lookup points after code moves.
The [plan](../../plans/edf-propulsion.md) owns work order and the
[validation matrix](validation-matrix.md) owns proposed proof.

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
| Kernel | [Simulation](../../../app/sim/simulation.gd), [VehicleModel](../../../app/sim/vehicle_model.gd): fixed 240 Hz, float64, RK4, events, atomic publish, checkpoints and rollback | Keep laws in adapter callbacks; no EDF branch in the shared kernel. |
| Flight orchestration | [FlightSession](../../../app/sim/flight_session.gd), [propulsion runtime](../../../app/sim/aircraft_propulsion_runtime.gd) | Extend explicit family/capability dispatch, layout, trim, reset and telemetry. |
| Source and shaft | [electric_motor.gd](../../../app/physics/electric_motor.gd), [propulsion.gd](../../../app/physics/propulsion.gd), [rotor_coupling.gd](../../../app/physics/rotor_coupling.gd) | Reuse electrical conventions and simultaneous rotor/body balance; separate fan shaft load from installation wrench. |
| Supply | [electric_supply.gd](../../../app/physics/electric_supply.gd), [pack_ecm.gd](../../../app/physics/battery/pack_ecm.gd) | Reuse stage bus solve and pack state; add identified ESC current/ramp behavior and new numerical bounds. |
| Events | [electric_battery_step.gd](../../../app/physics/electric_battery_step.gd), FlightSession battery endpoints | Preserve one transactional owner for contact subdivisions, source loss, exhaustion, stop and LVC sampling. |
| Turbine sibling | [turbine.gd](../../../app/physics/turbine.gd), [liquid_fuel_flight.gd](../../../app/sim/liquid_fuel_flight.gd) | Retain turbine law and finite fuel; EDF must not inherit fuel burn, turbine spool or ECU claims. |
| Aircraft admission | [aircraft_modules.gd](../../../app/physics/aircraft_modules.gd), [aircraft_data.gd](../../../app/physics/aircraft_data.gd), [v2 contract](../../../app/data/schema/aircraft-contract-v2.json) | New family, conditional fields, units, quantities, capability/energy combinations and invalid-data refusal. |
| Data sources | [AV-06 generator](../../../research/avanti-s/av06/derive_physics.py), [AV-06 inputs](../../../research/avanti-s/av06/inputs.json), [battery generator](../../../research/battery/bat-05/build_batteries.py) | Separate reproducible EDF inputs/output and pack identity; generated JSON is not an editing surface. |
| Native backend | [native_stage.gd](../../../app/sim/native_stage.gd), [native kernel source](../../../research/native-kernel/src/), [admission guide](../../../research/native-kernel/README.md) | Prepared EDF layout/maps, immutable configuration guards, reference parity, source/binary identity and platform admission. |
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

Reuse `electric_battery_step` only after checking ownership of subdivisions,
exhaustion/stop localization, LVC and source-loss ordering. New state cannot live
in mutable helper fields outside checkpoint/rollback. A refused native prepare
may retain an explicitly reported reference fallback; a failed live guard must
refuse the tick rather than switch backend mid-flight.

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
| Workshop | Generated descriptors bind base bytes/modules/visual family; `mass_edit.gd:397–413` rebases known offsets | Initially exclude EDF editing unless generator, schema, mass rebase and trial lifecycle are qualified. |
| Failures | `failures/catalog.gd:271–282,291–311,348–362` checks specific kinds | Explicitly include a tested source-loss mode or show EDF as unsupported. Never fabricate turbine flameout. |
| Natural Random | `scenario_config.gd:16,83–85,495–506`; `natural_random.gd:28–30` indexes an ordered aircraft list | Preserve v1's existing list and seed mapping; a new EDF-enabled policy needs a new version. |
| Creator imports | `creator/packages.gd:44–46,553–558`; `creator/phoenix/physics.gd:76` adapt imported EDF/jet information into existing turbine behavior | Leave legacy imports labeled as approximations; no automatic migration in this Avanti task. |
| Replay / recorder | Source, model, law, state and backend identities are pinned | A new EDF flight gets a new identity; old turbine recordings remain on their matching solver. |
| Crash and smoke | Energy source is explicit inventory metadata; turbine presentation is not an EDF energy law | Author LiPo source metadata; no inherited kerosene consumption or automatic hot-exhaust effect. |

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
explicit. Every evaluated stage still enforces the law's finite continuation
envelope and refusal rules. T06 discriminates these cases. This is a proposed
feature's integration prerequisite, not an existing runtime defect.

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
