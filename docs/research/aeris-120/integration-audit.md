# Repository integration audit

**2026-11-15 · A120 source investigation.** No runtime tests, model inspection or physical validation were performed. [The active plan](../../plans/aeris-120-3d-gas.md) owns implementation order and status. AERIS geometry and configuration remain prior design inputs pending measurement.

## Identity and base branch

- Repository: [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator).
- Audited default branch: `main`, commit `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; tree `cca9ad99ee0d1a6b5f70f1a960c8f8f36f488bf8`.
- The former development head `codex/m1-native-validation-20261106` at `8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd` is an ancestor: current main is ahead 268, behind 0.
- `codex/apple-silicon-native-default-20261113` at `f5219d7d682a7f2470bbf2af88c2cf64c1fe7833` diverges: compared with main it has 16 unique commits, while main has one. The compare file list shows no changes under `app/physics/` or `app/sim/`; it contains MetalFX/presentation, assets, tooling, packaging and tests. Do not silently merge that branch. Pin planning to main and recheck actual implementation base later.
- Evidence: [main commit](https://github.com/bultodepapas/OpenRCsimulator/commit/ad21070798bfb9658785576a9c0b8bfc9a71fc7f), [old native comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/8e5f2f0ba6aacd44efa1c4ac48c4023f181c47bd...ad21070798bfb9658785576a9c0b8bfc9a71fc7f), [Apple branch comparison](https://github.com/bultodepapas/OpenRCsimulator/compare/ad21070798bfb9658785576a9c0b8bfc9a71fc7f...f5219d7d682a7f2470bbf2af88c2cf64c1fe7833).

## Main conclusion

The simulator already has the right shared rigid-body, shaft, finite-fuel, control, imported-model and replay foundations. Adding a 120 cc 3D aircraft is primarily a new identified physical configuration plus a few bounded shared-law extensions. It is not a reason to replace the simulator kernel or scale the existing Extra .60 or P-51 coefficients.

The most consequential 3D gaps are the lack of wing propwash, restricted compatibility between axial wake transport and swirl, legacy gasoline datum-based propeller inflow, reverse-flow propeller approximations, static post-stall behavior, and aggregate sampled actuator dynamics. Each gap needs discriminating evidence before a new mechanism is selected; not every uncertain phenomenon warrants immediate complexity.

## Existing architecture and exact reuse seams

| Area | Verified source and symbols | Reuse for AERIS-120 | Limitation / proposed work |
| --- | --- | --- | --- |
| Kernel and vehicle boundary | `app/sim/vehicle_model.gd`; `app/sim/simulation.gd`; `app/sim/flight_session.gd` | Shared float64 6-DoF/RK4/240 Hz session; vehicle-owned layout/evaluators | No aircraft-ID branches in kernel; new states must participate in reset, checkpoint, replay and transaction rollback |
| Structural input | `app/data/schema/aircraft-contract-v2.json`; `openrc-aircraft-v2.schema.json`; `app/physics/aircraft_contract.gd`; `AircraftData.load_file()` | Existing closed v2 quantities and capability admission | Unknown fields cannot be parked in runtime JSON; proposed extensions must update registry, spec/schema, loader and consumers together |
| Capability registry | `app/data/schema/aircraft-modules-v1.json`; `research/aircraft-standardization/modules.py` | `controls: conventional`; `gear: fixed_taildragger`; `propulsion_layout: single_tractor`; `energy: finite_liquid_fuel`; `flaps: not_simulated`; existing applicable hull damage policy | Keep initial new configuration experimental; do not add selectable unsupported capability strings |
| Gasoline propulsion | `app/physics/propulsion.gd`: `source_kind`, `engine_torque`, `shaft_rate`, `steady_rpm`, `thrust_torque`; `FlightSession._coupled_response` | `propulsion.kind: glow_prop` plus `engine.shaft`, rotor inertia, independent prop tables and `gasoline_bsfc_v1` | `glow_prop` is historical combustion solver-family naming, not a claim of glow fuel. There is no `GasPropEngine` or accepted `gas_prop` kind |
| Finite gasoline fuel | `AircraftData._liquid_fuel`; `app/sim/liquid_fuel_flight.gd`: `initial`, `properties`, `evaluate`; `app/physics/liquid_fuel.gd` | Tank IDs, mixture registry, capacity/residue, BSFC/idle flow, source latch, mass/CG/inertia, coupled fuel depletion | No gasoline pickup/line pressure/slosh law; `_liquid_fuel` explicitly rejects pickup-position/feed-line extensions. Current tank is a uniform fixed box |
| Air loads | `app/physics/aero.gd`: `coefficients`, `_local_loads`, `_wing_flow`, `wing_strip_loads`, `tail_surface_increment`, `wing_wake_velocity` | Attached coefficient oracle + strip transition, asymmetric local velocities, tail geometry, spanwise stall, optional wing polars and separated-force offset | Current post-stall law is quasi-steady; wing/tail/downwash calibration remains aircraft-specific |
| Propwash | `app/physics/slipstream.gd`: `stage_loads`, `wake`, `immersion`, `sidewash`; `app/physics/wash_transport.gd` | Tail pieces, torque-linked swirl, sidewash, bounded optional axial speed transport | No wing immersion/scrub drag/transported wake direction or radius; transport is mutually constrained with other wake branches |
| Rotor/body coupling | `app/physics/rotor_coupling.gd`; `FlightSession._coupled_response`; `Dynamics.rotor_momentum` | Same-stage engine/prop torque, rotor gyroscopic momentum, relative-spin reaction once | Preserve external prop aerodynamic reaction versus internal engine exchange; no additional ad hoc torque-roll moment |
| Controls | `app/input/commands.gd`: `expo`, `shape_sticks`; `FlightSession.flown_commands`, `surfaces`, `_pre_step`; `ControlActuators.rate_limit`; `ControlSurfaces` | Calibration → device conditioning → profile → trim → sampled physical servo → shared aerodynamic/render angle mapping | One shared neutral-to-full servo time, three logical axis states. Multiple visible hinges do not imply independently simulated hardware |
| Catalog/model | `app/app_state/aircraft_catalog.gd`; `app/aircraft/imported_model.gd:build_checked/build_scene`; `model_registry.gd` | New unique aircraft ID/visual family; version-2 imported model manifest | Existing 3D model needs only later contract binding/inspection; no model recreation in this work |
| Generator chain | `assets/aircraft/model-bindings.json` → `research/aircraft-standardization/build_models.py` → `build_customization.py` → `research/aircraft-editor/build_descriptors.py` | Reuse manifest/customization/Workshop source pipeline and `--check` gates | Never hand-edit generated manifests/physics/Workshop descriptors; keep accepted saved-variant identities intact |
| Observability | `app/sim/flight_log.gd`, `docs/FLIGHT-LOGGING.md`, `tools/flight_log/flight_log.py` | `.orfl` baseline/exact replay/candidate comparisons, maneuver markers and actual-control observations | Candidate replay is open-loop; radio/expo/controller changes require new input-pipeline evidence |
| Native | `app/sim/native_stage.gd`; `research/native-kernel/src/nk_kernel.cpp`, `nk_aero.hpp`, `nk_prop.hpp`, `nk_wake*.hpp`, `nk_liquid*.hpp` | Capability-based preparation and reference fallback; source-bound qualification | New physics must be mirrored or explicitly reference-only; reference fallback never proves native coverage |

All code paths above refer to the audited commit. A pinned browser link is formed as `https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/<path>`.

## Correct first configuration

The current gasoline path used by the P-51 is the nearest software reference, but its warbird numbers are not AERIS inputs. The existing Extra 300S .60 is a useful aerobatics regression neighbor, but its 1.63 m geometry, 61FX installation, mass and borrowed polars are not suitable data to scale mechanically.

The initial AERIS source should author a dedicated physical generator and explicit parameter evidence, then emit a new `openrc-aircraft v2` configuration with stable semantic physical IDs. The proposed location `research/aeris-120/derive_physics.py` and `app/data/aircraft/aeris_120.json` are future paths, not existing assets.

The currently supported combination is:

```text
format: openrc-aircraft v2
convention_id: openrc-le-frd-v1
physical_identity_version: 1
controls: conventional
gear: fixed_taildragger
propulsion_layout: single_tractor
energy: finite_liquid_fuel
flaps: not_simulated
propulsion.kind: glow_prop
propulsion.engine.shaft: authored torque/power/friction installation
propulsion.fuel_consumption.law: gasoline_bsfc_v1
fuel_system: declared gasoline-family tank and inventory bindings
```

This is a conceptual field checklist, not a loadable JSON specimen. The exact damage selection should follow desired product behavior and the existing accepted policy. `finite_glow_fuel`/`glow_installation` would select the separate glow thermochemical/feed/lifecycle model and are the wrong shortcut for gasoline.

The default gasoline coupled-RK4 route is already selected by `FlightSession._commit_aircraft()` and explicit split selection is refused for finite propeller propulsion. The finite-liquid adapter evaluates stage mass, body/shaft loads, fuel consumption and source latch through the current shared contract.

The legacy engine uses a full-throttle brake-power curve plus friction and throttle-dependent admitted indicated power. It is not a measured DA-120 torque curve, carburetor transient, cylinder pressure model or ignition/choke simulation. The P-51 generator at `research/p51/p51-05/derive_physics.py` provides a structural example; its engine/26x12 four-blade prop calibration is explicitly estimated/BEM-derived.

## Falsifiable 3D gap map

### G1 — Hover roll authority and wing propwash

Observed: `slipstream.gd` augments only horizontal and vertical tail pieces by washed minus unwashed local load. The loader accepts only those two piece surface names. The source explicitly states wing slipstream is unmodeled. The wing strip evaluator receives free ambient/rotational flow, not propeller-added local wing flow.

Consequence: At near-zero translational airspeed, tail control can exist while aileron response on the washed inner wing is missing or misrepresented. Torque-roll arrest and hover roll may be wrong despite sufficient thrust.

Discriminating check: Place the aircraft in still air, prop turning, zero body rates; sweep aileron and log left/right strip forces and total roll moment. Then compare matched motor-off and powered conditions and measure actual installed wing immersion. Extend the shared station-flow contract with a compatible propwash source; avoid a direct aileron torque boost.

### G2 — Swirl and transport compatibility

Observed: `WashTransport` already carries one continuous axial speed state per neutral tail piece with a distance/convection-speed lag. It transports neither radius nor direction. `AircraftData._slipstream()` admits `transport_speed_floor` only with smooth profiles and zero swirl. Smooth wake requires axial shaft geometry. `propeller_sidewash` is accepted only on the legacy route, excluding both smooth profiles and transport.

Consequence: The plan cannot combine all listed wake effects by filling existing JSON fields. Fast transitions into hover/harrier need explicit scope choices. Torque-derived swirl is itself a documented heuristic, not closed angular-momentum accounting.

Discriminating check: Compare tail loads during throttle steps and rapid pitch/yaw at matched RPM/flow. Start with an honest quasi-steady calibrated baseline, then add a versioned combined law only if transient evidence distinguishes it. Schema, reference implementation, native mirror, replay state and bounded runtime cost must travel together.

### G3 — Gasoline local hub inflow

Observed: `Propulsion.stage_air_velocity()` adds rigid-point `omega × r` at the hub for explicit `is_glow(prop)` installations and electric propulsion. Historical shaft gasoline retains datum air velocity unless a complete `propulsion_air_body` spatial-stage override is present. `is_glow()` tests the normalized `glow` installation, not the `glow_prop` solver-family name. `FlightSession._coupled_response()` asks this helper every stage, but that alone does not make the legacy gas flow local to the hub.

Consequence: At high pitch/yaw rates, shaft load, disc angle of attack and crossflow may miss the hub's rotational velocity in uniform ambient wind.

Discriminating check: Evaluate a zero-translation pure rotation with an offset hub and analytic `v_hub = v_O + omega × r_hub`; verify all shaft, thrust, P-factor and wake source consumers see exactly one transform. Introduce versioned family-safe behavior and regress the old P-51/Corsair paths; do not silently change their established law.

### G4 — Tail slides and propeller reverse flow

Observed: Legacy `prop_torque()`, `thrust_torque()` and crossflow maps use `J = max(u,0)/(nD)`; coefficient extrapolation holds the first row at/behind its lower endpoint. `STOPPED_RPM` suppresses ordinary non-glow propeller loads near rest. Some positive-advance windmilling is possible when negative Cp is explicitly tabulated; that is distinct from signed reverse axial inflow and reverse shaft rotation.

Consequence: Tail-slide thrust/torque, reverse inflow and stopped-prop drag are approximation regions. Standard negative-flow table data alone will not be used correctly while J is clamped.

Discriminating check: Sweep signed axial inflow through zero at several RPM, plus near-zero RPM at finite forward flow; demand boundedness, continuity where physically appropriate and an explicit supported domain. Qualify a new signed-flow propeller law before claiming realistic tail slides or abrupt reverse-flow maneuvers.

### G5 — Harrier, wing rock, snaps and sustained spins

Observed: Current wing polars, strip progression and separated-force offset are quasi-steady. Downwash lag exists but is not dynamic stall. Local velocities from body rotation and smooth periodic separated-flow laws are useful foundations. The existing Extra guide leaves hands-off stalls, sustained spins and several directional maneuvers unqualified.

Consequence: A stable hover or recognizable snap animation does not prove correct aerodynamic hysteresis, wing rock, spin equilibrium or recovery. Do not inject a sinusoidal wing-rock motion or scripted maneuver state.

Discriminating check: Separate ramp-rate-dependent alpha sweeps, power-on/off stall progression, left/right snap entries, spin equilibrium versus spiral classification, release/recovery and upright/inverted harrier. Identify missing physics through independent measurements before adding dynamic-stall/separation states. Keep benchmark criteria separate from the same fitted coefficient set.

### G6 — Actuators, rates and pilot feel

Observed: Maximum throws admit 1–60 degrees. `servo_full_throw_time` means neutral to full physical surface travel, and one scalar sets all three normalized servo rates. It is not the manufacturer's sec/60-degree servo-arm rating. `ControlSurfaces` supports conventional shared-axis mapping and optional aileron differential, not independent six-servo bandwidth or hinge load. Multiple imported hinges may share a role.

`Commands.expo(x,e) = (1-e)x + e x^3`. The normal profile shapes keyboard sticks; gamepad already has device expo and gets travel scaling without duplicate expo. Calibrated radio passes its own rates/expo. `FlightSession.flown_commands()` adds trim after shaping; actual sampled servo state drives both aerodynamic and rendered deflections. Existing full/sport behavior belongs to session policy; the closed schema contains only `controls.rates.normal`.

Consequence: Do not add an unsupported `rates.3d` JSON block, double-filter the radio, or use arbitrary expo to hide an aerodynamic defect. For first integration, explicitly document normal and maximum throws plus transmitter setup. An independently adjustable per-axis/per-surface actuator or three-profile UI is a separate versioned extension with input/replay and user-settings compatibility work.

Discriminating check: Neutral-to-end and full reversal timing per physical surface, signed control checks in all aircraft attitudes, actual radio endpoint measurement, input-to-surface delay, input-to-visible-response delay, and repeatable rate profiles. Hinge torque/bandwidth should be measured or explicitly estimated; adding servo torque/current/receiver sag is optional further scope, not already implemented physics.

### G7 — Gasoline lifecycle and fuel supply

Observed: Finite-liquid fuel supports usable mass and source latch. Existing explicit `glow_cut`, `glow_start` and mixture routines refuse non-glow installations. Gasoline runway start initializes an already-running equilibrium idle. Fuel pickup/feed labels are not dynamic supply laws.

Consequence: DA-120 choke, ignition switch, hand/electric start, flooding, hot restart and attitude-dependent supply cannot be claimed by reusing glow controls. A first release can document a running-engine start and distinct supported cut/reset behavior; deeper gasoline lifecycle is a separate conditional module.

Discriminating check: Engine cut, exhaustion, restart/reset policy and no spontaneous relight; no arbitrary fuel starvation merely because the aircraft is inverted. Any future fuel-starvation state needs a physical pickup/feed mechanism and reset/checkpoint/logging evidence.

### G8 — Native implementation versus qualification

Observed current code correction: `docs/EXTRA-300-PLAN.md` contains a stale statement that the native decoder refuses `wing_separated_force_offset`. At this audit commit, `nk_kernel.cpp:decode_aero` explicitly accepts it, checks 0…0.25 and restricts it to a conventional wing without flaps. Therefore do not list that decoder support as missing. Source support does not establish current source-bound fleet qualification.

Discriminating check: Validate actual requested/selected backend, prepared law/config identity, C++ stage call receipts and matched candidate data. Mirror new steady/state laws or intentionally use the reference fallback with clear performance evidence. Apply native and package qualification after the shared physics stabilizes.

## Frames and physical truth that must remain explicit

- Authored positions: metres `[x_aft,y_right,z_up]`, leading-edge datum at centreline.
- Runtime body: FRD; world: NED; quaternion `[w,x,y,z]`, body to NED.
- Finite-fuel body state uses fixed reference-inventory CG datum O; live CG moves relative to it. Use the existing `FixedDatumBody`/mass-property contract and avoid subtracting CG twice.
- Inertia: `[Jxx,Jyy,Jzz,Jxy,Jxz,Jyz]` in kg m² with negative-product off-diagonal convention.
- `mean_chord` is `S/b`, not MAC. Keep aerodynamic coefficient reference chord separate from geometric MAC used to report CG.
- Aerodynamic elevator/aileron derivative signs are trailing-edge down, rudder trailing-edge left; pilot/render angles are trailing-edge up/right. `ControlSurfaces.deflections_from_surfaces()` owns conversion.
- Supported conventional prop rotation is clockwise viewed from behind. Declare viewpoint in every torque/P-factor/gyro sign test.
- Quantity evidence is exactly `manual`, `measured`, `borrowed`, `estimated`, `derived`. Uncertainty belongs in evidence reports until a consuming schema module exists.

## Bounded validation plan tied to existing tools

This audit executed no Godot tests and makes no passing-test claim. The following are verified existing tests/tools appropriate for future implementation selection:

| Change | Existing checks to select/adapt |
| --- | --- |
| New data/identity/module | `app/tests/test_aircraft_data.gd`, `test_aircraft_contract.gd`, `test_aircraft_modules.gd`, `test_aircraft_catalog.gd`; `research/aircraft-standardization/conformance.py`; own generator `--check` |
| Propeller/shaft | `test_propulsion.gd`, `test_propeller_table_continuity.gd`, `test_shaft_data.gd`, `test_shaft_equilibrium.gd`, `test_shaft_coupled.gd`, `test_shaft_refinement.gd`, `test_rotor_coupling.gd` |
| Wake | `test_propeller_wake.gd`, `test_slipstream_downwash.gd`, `test_slipstream_sidewash.gd`, `test_wash_profile.gd`, `test_wash_transport.gd` |
| Post-stall | `test_aero_continuity.gd`, `test_strip_induced.gd`, `test_wing_polar.gd`, `test_wing_reverse_flow.gd`, `test_wing_separated_offset.gd`, `test_wing_body_roll.gd`, `test_extra_post_stall.gd`, `test_spin.gd` |
| Fuel/state/events | `test_liquid_fuel.gd`, `test_liquid_fuel_session.gd`, `test_fuel_event_boundaries.gd`, `test_fuel_live_mass.gd`, `test_fuel_mass_reference.gd`, `test_fuel_start_fill.gd` |
| Controls/model binding | `test_control_actuators.gd`, `test_control_surfaces.gd`, `test_control_surface_observation.gd`, `test_controller_conditioning.gd`, `test_controller_rates.gd`, `test_aircraft_model_manifest.gd`, `test_aircraft_render_contract.gd` |
| State and backend | `test_flight_log.gd`, `test_flight_log_inputs.gd`, `test_aero_prop_checkpoint_laws.gd`, `test_native_stage.gd`, `test_native_replay.gd`, native family oracles/fleet campaign |

Use the owning checked runner or test pool according to `docs/tools/physics.md` and `tools/testqueue/README.md`. Do not launch the full suite for documentation work. Before a handling change, preserve a baseline `.orfl`, verify exact replay, then compare one candidate from a frozen source/config snapshot with the same tape. Check `complete` and `solver_changed`; interrupted prefixes are not complete flights. Controller/expo changes are not qualified by replaying already-conditioned controls.

`research/flight-test/run.py` and `compare.py` provide complementary maneuver cards; inspect profile/list output because unknown `--only` names are silently skipped. Aircraft data-only experiments can share a frozen app with `--data`, while new physics needs separate frozen source snapshots. Log commanded and actual surfaces, local wing/tail flow and force components, RPM/shaft power/thrust/torque, mass/CG, body rates, alpha/beta validity, and weather identity.

## Source references

Primary repository references inspected, all pinned to `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`:

- [Aircraft contract](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/AIRCRAFT_CONTRACT.md).
- [Propulsion source](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/propulsion.gd).
- [Aircraft parser and derived data](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/aircraft_data.gd).
- [Aerodynamic evaluator](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/aero.gd).
- [Tail slipstream](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/slipstream.gd).
- [Axial transport](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/physics/wash_transport.gd).
- [Flight session](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/flight_session.gd).
- [Finite-liquid adapter](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/sim/liquid_fuel_flight.gd).
- [Control command shaping](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/app/input/commands.gd).
- [Native decoder](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/research/native-kernel/src/nk_kernel.cpp).
- [Native workflow and qualification boundaries](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/research/native-kernel/README.md).
- [Existing Extra guide and qualification limits](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/EXTRA-300-PLAN.md).
- [Existing gasoline P-51 guide](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/P51-PLAN.md).
- [Flight logging](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/FLIGHT-LOGGING.md).
- [Physics verification tools](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/tools/physics.md).

External aircraft and method references live in the [source register](sources.md). The [physics investigation](physics-and-propulsion.md) and [controls/validation protocol](controls-and-validation.md) explain the proposed response to these gaps.
