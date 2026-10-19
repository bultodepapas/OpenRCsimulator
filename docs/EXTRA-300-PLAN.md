# Great Planes Extra 300S .60: current scope and remaining work

Checked 2026-10-19 · Owner: Extra aircraft/model track · Prefix **EX-00…13** and repairs. Code and accepted data define implementation; software verification and physical acceptance are separate results.

**GPMA0236**, the 64-inch kit, flies experimentally as `gp-extra-300s-60`. Club runway and airborne starts are implemented; fresh product preferences select runway. Gear is a fixed taildragger, without brakes, retracts or flight flaps.

The [aircraft data](../app/data/aircraft/gp_extra_300s_60.json) selects `finite_glow_fuel` and a dedicated [Extra installation](../app/data/glow/extra_61fx_2t.json). Shared glow physics supplies torque-balance propulsion and shaft reaction; fuel burn changes mass/CG/inertia. The 61FX profile is scaled from 55AX data, not measured on this Extra. Dry balance targets and live loaded CG remain distinct.

| Topic | Home |
| --- | --- |
| Geometry, finish, model interfaces and commands | [Asset guide](../assets/aircraft/extra-300s-60/README.md) |
| Generated aircraft assumptions | [EX-05 derivation](../research/extra-300/ex05/derivation.md); source is `ex05/derive_physics.py` |
| Shared engine/propeller and fuel behavior | [Glow guide](GLOW-ENGINES.md), [61FX dossier](research/glow-engines/NITRO-61FX/README.md), [fuel standard](FUEL-SYSTEM.md) |
| Dated results and comparison tools | [Realism audit](research/extra-300-realism/README.md), [EX-06/08 probes](../research/extra-300/ex06/README.md) |

Use the [aircraft contract](AIRCRAFT_CONTRACT.md), [player controls](FIRST-LAUNCH.md) and [flight logging workflow](FLIGHT-LOGGING.md). EX owns its sources, builder, generator, tests and research; shared physics/NITRO/fuel/input/crash/export boundaries stay with their [registered owners](README.md#tracks-plans-and-step-ids). Regenerate dependent data and model/Workshop bindings; never edit generated output.

## Steps and evidence

Original delivery results retain their dated scope. Neither old passing counts nor baseline failures establish current suite status.

| ID | Delivered scope | Remaining acceptance / work |
| --- | --- | --- |
| EX-00/01 | Kit selection and [plan metrology](../research/extra-300/ex01/metrology.json) | Identify estimated shape/installation details on the actual build. |
| EX-02/03/04 | Native model, catalog and articulation/clearance | Owner visual and loaded-airframe clearance review. [Model evidence](research/extra-300-model-v1.md). |
| EX-05/06 | Generated physics, dry balance, shaft and propeller consistency; later finite-glow integration | Matched engine/propeller, mass/CG/inertia and aerodynamic identification. |
| EX-07/08 | Handling/envelope/lifecycle probes and dated 240/480 Hz comparisons | Current installation parsing, maneuver trim, runway fixture and CI trace-reader failures remain open; see the recheck in the realism audit. |
| EX-08-R1 | Runway support and estimated breakaway data | Starter-aware takeoff regression and physical ground/circuit qualification. [Startup/replay evidence](research/extra-300-realism/README.md#2026-10-16--runway-startup-ex-08-r1). |
| EX-09 | Physical qualification | Open: matched observations, uncertainty and held-out comparisons. |
| EX-10 | Red/white/blue finish and orientation views | Pilot readability and target rendering cost. [Visual evidence](research/extra-300-visual-review-v1.md). |
| EX-11 | Select/fly/pause/restart/end integration | Recheck changed shared input/session/product paths. |
| EX-12 | Export/performance qualification | Current clean-checkout fleet packages, per-aircraft smoke, relevant uninterrupted suite and target hardware. |
| EX-13 | Further aerobatic/ground extensions | Deferred; require scoped shared mechanisms, data and lifecycle/qualification proof. |

## Current model limits

Lift/drag, low-Re polar, mass distribution and virtual ballast include estimates. The nominal 12×6 propeller uses borrowed APC 11×6 source data; the prototype propeller and installed response remain unidentified. Virtual ballast is not a hardware recommendation. Manual setup guidance does not establish measured stall/spin/Vne or structural limits.

The plan-derived 2° right / 0.5° down shaft and hub are consumed by physics. Torque-balance propulsion exists; propwash, P-factor, prop-disc side force and Extra-specific feed-pressure behavior do not. Retest the historical takeoff-yaw mismatch under current sources; do not hide missing mechanisms with a rudder bias or force multipliers.

Physical flight/ground measurements, pilot review and target-hardware/export acceptance remain open independently of software regressions. Keep the aircraft experimental until the applicable gates have evidence.
