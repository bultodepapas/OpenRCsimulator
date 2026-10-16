# Great Planes Extra 300S .60

2026-10-16 · Revision 7 · **Status: experimental aircraft with runway and airborne starts; software envelope checks are complete. Independent flight, target-hardware and export acceptance remain open.** Prefix: `EX-`. Owned paths: `assets/aircraft/extra-300s-60/`, `app/aircraft/extra_300s_*`, `app/aircraft/extra_clearance.gd`, `app/aircraft/verify_extra.gd`, `app/aircraft/inspect_extra.gd`, generated `app/data/aircraft/gp_extra_300s_60.json`, `app/tests/test_extra_handling.gd`, `research/extra-300/`, `docs/research/extra-300-*`, `docs/research/extra-300-realism/`.

The aircraft is the Great Planes GPMA0236, 64-inch balsa Extra 300S with an O.S. .61FX-class installation. The native model and physics are specific to this kit. The generated physics file is [gp_extra_300s_60.json](../app/data/aircraft/gp_extra_300s_60.json); regenerate it with [derive_physics.py](../research/extra-300/ex05/derive_physics.py) after changing any geometry inputs it reads. The [asset README](../assets/aircraft/extra-300s-60/README.md) documents source evidence, geometry, builders and current model interfaces.

The model flies as `gp-extra-300s-60` and remains marked experimental. Its builder exposes the stable airplane, propeller, hinge and gear interfaces used by the Stik-compatible render adapter. Geometry data and appearance are separate from mass, inertia, propulsion and aerodynamic estimates.

Runway is the default product start, with airborne practice still available. The generated contact data now includes an explicitly estimated breakaway factor; [EX-08-R1](research/extra-300-realism/README.md#2026-10-16--runway-startup-ex-08-r1) records parked/takeoff regressions and the paired airborne trace. Independent ground-handling acceptance remains open.

## Steps and evidence

| ID | Deliverable and proof | Status checked 2026-10-12 |
| --- | --- | --- |
| EX-00 | Select GPMA0236 and preserve sourced plans, manual and photos. [Family research](research/extra-300-family-research.md) · [resources](research/extra-300-resources.md) | Complete |
| EX-01 | Establish datum and initial dimensions from the kit drawing. [Metrology](../research/extra-300/ex01/metrology.json) · [model report](research/extra-300-model-v1.md) | Complete; some shape details remain estimated |
| EX-02 | Build and verify the native visual model. [Asset README](../assets/aircraft/extra-300s-60/README.md) · [visual review](research/extra-300-visual-review-v1.md) | Complete |
| EX-03 | Register a separate catalog ID and preview path. | Complete; the aircraft is selectable and flyable experimentally |
| EX-04 | Articulate surfaces and check moving-surface clearance at manual and 45° poses. `extra_clearance.gd` is part of the model verification. | Complete |
| EX-05 | Generate attributed aircraft-specific physics data from the geometry and manual. [Derivation](../research/extra-300/ex05/derivation.md) | Complete; inputs remain partly estimated or borrowed |
| EX-06 | Audit balance, propeller match and installed thrust frame. [EX-06/08 realism report](research/extra-300-realism/README.md) | Software corrections complete; propulsion remains physically unmeasured |
| EX-07 | Trim and fly through the real session loop. `test_extra_handling.gd` checks hands-off flight, roll response, looping and recovery. | Complete; experimental |
| EX-08 | Qualify the software envelope and lifecycle at 240/480 Hz. The audit adds 24 airborne and 7 ground cases and repairs the E5a research fixture without changing contact forces. [Verification summary](research/extra-300-realism/EX-08/verification-summary.json) | Software evidence complete; 13 unrelated baseline suite failures remain, and physical acceptance is open |
| EX-09 | Compare with independent observations and qualify handling. [Audit and open physical gates](research/extra-300-realism/README.md) | Open; no matched flight dataset |
| EX-10 | Apply the red/white/blue finish and prepare ground-orientation views. [Visual review](research/extra-300-visual-review-v1.md) | Implementation complete; pilot reading pending |
| EX-11 | Select the Extra, fly, pause, restart, end and return without mixing aircraft state. | Complete |
| EX-12 | Export both selectable aircraft from a clean checkout and measure cost on target hardware. | Open |
| EX-13 | Extend aerobatics and conventional-gear behavior with dedicated shared physics and evidence. | Deferred; follows ROADMAP Gate F and ground-physics work |

The bounded installation/envelope audit is preserved in [the research report](research/extra-300-realism/README.md), including before/after mass properties, shaft checks, flight metrics, baseline-failure triage and reproducible commands. Its software work does not close EX-09 physical validation.

## Current model limits

The plan and manual provide qualitative handling guidance, but no numeric stall, spin, Vne or structural limits for this airplane. The derived aerodynamics use estimated lift limits, drag, inertia distribution and no identified low-Re airfoil polar. The propeller's Ct/Cp data are borrowed from an APC 11×6 proxy; the selected visual/physics size is 12×6. Balance uses an estimated dry component inventory and bookkeeping ballast. It is not a measured ballast recommendation.

The installed 2° right / 0.5° down thrust angles now act through the shared angled-thrust consumer. The correction checks geometry and signs, but the model still lacks an Extra-specific torque-balance engine, propwash and P-factor. The manual's qualitative takeoff-yaw expectation is unmet. Do not add a rudder bias or tune force multipliers to conceal it. Independent mass/CG/inertia, engine/propeller measurements, low-speed observations, pilot assessment, export and target-machine cost remain acceptance work.
