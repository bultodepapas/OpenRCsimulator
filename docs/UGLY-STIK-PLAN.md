# Jensen Ugly Stik 60: current model and remaining acceptance

Checked 2026-10-19 · Owner: Stik model/finish track · Prefixes **US-01…08**, **US-V01…12** and repairs. This guide owns visual scope and acceptance. The [asset guide](../assets/aircraft/ugly-stik-60/README.md) owns sources, commands and model interfaces; dated research owns delivery evidence.

## Current implementation

The native model represents the 60-inch Jensen with a generic .61-class installation. It includes articulated controls and fixed-length links, five servos (two in the wing, US-V17), retainers, the owner's Blender O.S. 61 SF engine on a radial mount (US-V13), glossy red/white/black film, scalloped edges, wooden propeller grain and estimated weathering. Gear flex follows simulated wheel compression; prop-strike stubs, fracture details and soft-contact scuffs are implemented.

The [geometry](../assets/aircraft/ugly-stik-60/geometry.json) and [appearance](../assets/aircraft/ugly-stik-60/appearance.json) are separate editable sources. The manifest selects the native builder through the shared [model contract](AIRCRAFT_CONTRACT.md#model-and-package-contract). Mesh counts and v3/v4/v5/v6 report names describe delivery snapshots; use current verification for today's model.

The base catalog aircraft, `jensen-das-ugly-stik-60`, retains prescribed fuel and fixed tricycle gear without flaps. Finite-glow Stik configurations share the visual family but have distinct installations and energy behavior. Use the [glow guide](GLOW-ENGINES.md) and [fuel standard](FUEL-SYSTEM.md); the mesh does not select engine physics or establish mass/CG/inertia.

## Delivered work and pending gates

| IDs | Delivered scope / evidence | Remaining acceptance |
| --- | --- | --- |
| US-01 | Deterministic inspector and orientation cases; [v3 evidence](research/ugly-stik-model-v3.md) | Repeat comparable views after intentional visual changes. |
| US-02/03 | Drawing metrology and held-out fuselage station; [metrology](research/ugly-stik-model-v3-metrology.md) | Resolve scan/view disagreement and estimated vertical datum against a build. |
| US-04/05 | Tail/wing pose and clearance checks; [wing limits](research/ugly-stik-model-v3-wing.md) | Sampled software poses do not prove loaded-airframe clearance. |
| US-06 | 20/50/100 m orientation cases and pilot form | Owner readability scoring with the current finish. |
| US-07 | Generic installation, contact/frame handoff; [report](research/ugly-stik-model-v3-installation.md) | Identify actual installed equipment and validate ground behavior separately. |
| US-08 / V08 | Model cost and reproducible captures; [engine evidence](research/ugly-stik-engine-v5.md) | Target-GPU timing and rendered acceptance. |
| US-V01/02 | Appearance source, atlas, markings and scalloped edges; [v4 delivery](research/ugly-stik-model-v4.md) | Owner review of estimated finish, including underside. |
| US-V03…07 | Engine, control mechanisms, servos and fittings; [v4 evidence](research/ugly-stik-model-v4.md) | Exact commercial engine and hidden hardware remain unidentified. |
| US-V09a…h | Film/shading, structure normal map, throttle linkage, grain, residue, hatch and wear; [finish evidence](research/ugly-stik-finish-v6.md) | Pilot reading and target rendering cost. |
| US-V10/10b | Main-leg flex and sprung/steerable nose gear; [evidence](research/ugly-stik-finish-v6.md#us-v10--landing-gear-flex) | Measured loaded gear behavior. |
| US-V11/12 | Broken propeller and soft-contact scuffs; [evidence](research/ugly-stik-finish-v6.md#us-v11--broken-propeller-after-a-prop-strike) | Visual acceptance; these effects do not validate structural failure. |
| US-V13 | Owner's Blender O.S. 61 SF engine on an O.S. 905 radial mount replaces the native engine; [evidence](research/ugly-stik-finish-v6.md#us-v13--os-61-sf-engine-from-the-owners-blender-model) | Owner visual review; target-GPU cost of the 150k-triangle engine; the 6.4 mm hub offset waits for a physics step. |
| US-V14 | Main gear as the plan's tapered 0.090 in 2024-T3 aluminium plate; [evidence](research/ugly-stik-finish-v6.md#us-v14--aluminium-main-gear-plate) | Axle positions stay the physics contacts; the drawn ones are implausible, so only a measured build should move them. |
| US-V15 | Form pass: sanded round wing tips (true raked cap normal) and round tail-sheet edges; [evidence](research/ugly-stik-finish-v6.md#us-v15--form-pass-sanded-wing-tips-and-tail-edges) | Owner close-up review; wing leading-edge facets (F3) left as a note. |
| US-V16 | Lookdev vs the RCM photos: epoxy birch-ply firewall face; engine excluded from film scuffs (first contact 359 → 28 ms); [evidence](research/ugly-stik-finish-v6.md#us-v16--lookdev-colours-textures-and-the-firewall) | Owner choice on the RCM-only scheme differences (fuselage band, cross size, band colour, spinner). |
| US-V17 | Two-servo wing (owner's choice): one servo per semispan on a bottom hatch, short pushrod, nylon horn, no bellcrank; standard 40 × 20 × 36 mm servos seated from their shafts; shaped arms and horns; [evidence](research/ugly-stik-finish-v6.md#us-v17--servos-and-control-hardware) | Stations are estimates; the economy catalogue still prices one central aileron servo. |

The [2026-10-19 recheck](research/ugly-stik-finish-v6.md#2026-10-19-documentation-recheck) records focused verification separately from original delivery results. It does not close the full-suite, pilot or hardware gates.

## Limits and acceptance

The visible wing section is traced from a kit rib, not an identified airfoil polar. Hidden geometry, incidence/dihedral, engine proportions, materials and weathering include estimates. The assembly origin is not a measured CG; flight coefficients and inventory remain separate.

Current geometry/reference data use 720 in²; an older drawing/decision records 723 in². The drawing's 4.76-inch CG reference is not a measured build. Metrology retains scale residuals and uncertainty; [decisions](DECISIONS.md) retains the CG rationale.

Score the existing orientation cases with resolution, camera and target-GPU timing recorded. Preserve measured geometry and comparable views when responding to review. Mini/giant variants, full internal structure, LOD and an identified commercial installation remain future work.

The active [pull-up plan](UGLY-STIK-PULLUP-PLAN.md) owns D8b-R2 physics diagnosis, research polars and remaining physical/owner gates. Its opt-in experiments are separate from this visual delivery and do not establish Jensen-specific calibration. Preserve a baseline and exact replay before flight-model changes using [flight logging](FLIGHT-LOGGING.md).
