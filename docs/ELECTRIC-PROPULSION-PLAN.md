# Reusable electric propulsion

2026-10-12 · Revision 9 · Step prefix: **EL** (ROADMAP M4b namespace).

**Status:** Synthetic EL1b–e and EL2a routes are software verified. EL2a-P1/P2 reduce measured battery/event tick costs, but the 500 µs target and original-target remeasurement remain open. Timber data, physical validation and pilot acceptance are open; synthetic fixtures do not provide measured Timber parameters.

This physics subplan owns electric motor/supply/stop modules, electric tests and `research/propulsion/EL*`. Loader, trim, flight session and trace changes are shared main-line work. Aircraft/model data follows the model owner. Related plans: [coupled shaft](PROPULSION-CORE-PLAN.md), [Timber integration](TIMBER-INTEGRATION-PLAN.md), [atmosphere](ATMOSPHERE-PLAN.md), [ROADMAP](../ROADMAP.md).

## Current software contract

`openrc-aircraft v2` is the current aircraft-data boundary and carries the explicit `electric_prop` branch; v1 is a historical compatibility path. The loader normalizes provenance-complete motor, ESC and battery blocks alongside the existing propeller/rotor data. It rejects mixed combustion/turbine fields and unsupported configurations. See [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md) and the [schema/loader evidence](research/propulsion/EL1b/README.md).

The implemented motor is a stateless, positive-rotation DC-equivalent source: `E = rpm/Kv`, `kt = 60/(2πKv)`, `Im = max((d·Vbus − E)/Rm, 0)`, and `Qsource = kt(Im − I0)` while rotating. The ESC law is ideal averaged motoring with identity command-to-duty mapping. EL1 uses prescribed fixed voltage and has no battery state. EL2a supports a synthetic OCV/resistance pack with SOC, sag, charge/energy accounting, pack-side auxiliary current and exhaustion events. Pack heat is loss energy, not a thermal model.

Regeneration, reverse rotation, active braking, manufacturer current limiting, switching losses, controller dynamics and temperature response are not implemented by this contract. An ESC rating or nameplate Kv is not a measured motor/pack law. Propeller loads continue to use the shared signed `Ct/Cp` data and stage-local inflow/density.

Electric flight requires `coupled-rk4` with valid rotor inertia and carrier inertia; an explicit split integrator is refused. The session integrates body and rotor state together and localizes the stopped-rotor and, for EL2a, battery-exhaustion events. Fixed-bus developer routes are `-- --electric-demo=4s` and `-- --electric-demo=6s`; battery routes append `-battery`. They use labeled synthetic Stik configurations, are not catalog aircraft, and make no validated conversion claim. The integrated coupled contract is summarized in [PROPULSION-CORE-PLAN](PROPULSION-CORE-PLAN.md).

## Physical reference and promotion

The selected future reference is the E-flite Turbo Timber Evolution BNF Basic B, EFL105250B: 800 Kv motor, 70 A ESC and stock three-blade 11×7.3 propeller, with a 4S 3200 mAh pack class. The exact pack, installed hardware revision, motor R/I0, rotor inertia, loadout and matched stock-prop map still need identification. Manufacturer labels do not supply those parameters. SAFE and AS3X state must be recorded separately; disabling SAFE alone is not an unaided-flight reference. The sourced configuration and limits are in [Timber reference research](research/propulsion/EL1a/timber-reference.md).

EL5/EL6 require calibrated, matched, held-out physical measurements with hardware/firmware, temperature, environment, channel timing and uncertainty recorded. The ROADMAP targets remain ±10% for current/thrust and ±15% for endurance. The project's uncertainty rule passes when `abs(error)+Uerror <= limit`, fails when `max(0,abs(error)-Uerror) > limit`, and otherwise reports inconclusive; this is a project rule, not a manufacturer requirement. Preserve raw observations and the fit/validation split.

## Step register

| ID | Delivery and evidence | Status |
| --- | --- | --- |
| EL1a | Stateless motor source, ideal motoring ESC and fixed bus. [Kernel, 1,057 checks and mutations](research/propulsion/EL1a/README.md) | Complete — software only |
| EL1a-R1 | Hardware and measurement investigations. [Source/decision matrix](research/propulsion/EL1a-R1/README.md) | Complete — research |
| EL1a-R2 | Godot, data, numerics, tooling and identifiability investigations. [Probes and matrix](research/propulsion/EL1a-R2/README.md) | Complete — research/tools |
| EL1b | v2 loader/schema and two synthetic configurations. [Validation evidence](research/propulsion/EL1b/README.md) | Complete — software only |
| EL1c | Shared source dispatch, equilibrium and trim. [Independent solver checks](research/propulsion/EL1c/README.md) | Complete — software only |
| EL1d | Coupled session, stop events, checkpoint and telemetry. [Replay, rollback and regression](research/propulsion/EL1d/README.md) | Software verified; performance target missed |
| EL1e | Synthetic experimental aircraft routes. [Flight and product proof](research/propulsion/EL1e/README.md) | Complete — synthetic fixtures only |
| EL1f | Timber configuration and model handoff. [Ownership/input handoff](research/propulsion/EL1f/README.md) | Open — identified hardware/loadout and TT data required |
| EL2a | OCV/resistance pack, sag, state and exhaustion. [Independent oracle, replay and product proof](research/propulsion/EL2a/README.md) | Software verified; performance target and physical data open |
| EL2a-P1 | Reduce coupled stage cost with exact behavior preservation. [Paired evidence](research/propulsion/EL2a-P1/README.md) | Complete — battery medians 558–562 µs on the documented WSL host; 500 µs gate open |
| EL2a-P2 | Bound stop/exhaustion localization and event ordering. [Defects and paired measurements](research/propulsion/EL2a-P2/README.md) | Complete — event medians down 67–90%; event spike and Gate P remain |
| EL2a-E1 | Synthetic runway startup, takeoff, stall/recovery and landing. [Windows/Linux evidence](research/propulsion/EL2a-E1/README.md) | Complete — software scope only |
| EL2a-P3 | Smaller motor-stage result with exact session/event preservation. [Native comparison](research/propulsion/EL2a-P3/README.md) | Software complete; whole-session speedup not established under concurrent workloads |
| EL2b | One battery polarization RC pair, only if measured residuals justify it. | Planned |
| EL3 | Per-ESC ramp, cutoff, signal-loss and brake/freewheel modes. | Planned — exact controller behavior/data required |
| EL4 | Winding/ESC thermal state and derating. | Deferred — thermal data and energy accounting required |
| EL5 | Independent static/transient powertrain validation. | Planned — matched motor/ESC/pack/prop measurements required |
| EL6 | Endurance validation against recorded pack/flight data and cutoff. | Planned — physical data required |

EL2a-P1's 558–562 µs and P2's event-tick reductions were measured on a Ryzen 9 5900X under WSL, not the original target profile. They do not close the whole-session 500 µs/tick gate. [EL2a-E1](research/propulsion/EL2a-E1/README.md) adds synthetic 240/480 Hz maneuver checks; it does not close physical promotion. See [Gate P and original results](research/propulsion/EL2a/README.md#performance).

Detailed source/provenance limits remain in [motor and ESC investigations](research/propulsion/EL1a-R1/01-motor-esc.md), [battery investigations](research/propulsion/EL1a-R1/02-battery.md), [propeller validation](research/propulsion/EL1a-R1/03-propeller-validation.md), [numerics and uncertainty](research/propulsion/EL1a-R1/04-numerics-telemetry-uncertainty.md), [static validation tools](research/validation/VAL-7a/README.md), [RPM-step diagnostics](research/validation/VAL-7c/README.md), and [propeller provenance/coverage](research/propulsion/G1b1/README.md).
