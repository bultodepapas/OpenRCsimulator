# Jensen Ugly Stik 60: model and finish

2026-10-13 · Revision 9 · **Status: visual geometry v3, finish v4 with the US-V09a–h glossy-film, shading, film-over-structure, throttle-linkage, propeller, weathering, hatch and field-wear passes, and engine detail v5 are implemented. Pilot readability and target-GPU acceptance remain open.** Prefixes: `US-` and `US-V`. Owned paths: `assets/aircraft/ugly-stik-60/`, `app/aircraft/ugly_stik_*`, shared `app/render/airplane.gd` contract, `research/ugly-stik/`, and `docs/research/ugly-stik-*`.

The reference is the Jensen 60-inch Ugly Stik with a generic .61-class nitro installation. The target is a recognizable, articulated airplane for the first owner playtest, not a certified replica. The [geometry source](../assets/aircraft/ugly-stik-60/geometry.json) and [appearance source](../assets/aircraft/ugly-stik-60/appearance.json) are authoritative; their compilers generate the Godot model data. The asset README has regeneration commands and the builder contract.

## Current implementation

The native builder exposes `build() → {root, propeller, hinges, gear, controls}` with root `airplane`, propeller `propeller`, and stable `aileron_left`, `aileron_right`, `elevator`, and `rudder` hinges. Fixed wing frames carry dihedral; the hinges carry surface deflection. The model includes the classic red finish (glossy film since US-V09a) with white fields and black crosses, scalloped trailing edges, a gold-head engine, silencer, generic servos, control links, retainers, and gear details. Engine v5 improves open intake/bores, cooling fins and exhaust geometry.

The model contract and reproducible visual evidence pass. The completed work and remaining acceptance are tracked here:

| ID | Result and proof | Status checked 2026-10-12 |
| --- | --- | --- |
| US-01 | Deterministic inspector, protected historical captures, 9 inspection and 36 orientation views; independent orientation render hashes match. [v3 validation](research/ugly-stik-model-v3.md) | Complete |
| US-02 | Jensen drawing metrology with source coordinates, scale and uncertainty; view disagreements and provisional vertical datum recorded. [Metrology](research/ugly-stik-model-v3-metrology.md) | Complete as an initial measurement session |
| US-03 | Fuselage stations and tail fit checked against a held-out dimension; this is not physical certification. [v3 report](research/ugly-stik-model-v3.md) | Complete |
| US-04 | Tail poses, containment and clearances checked across 99 pose pairs. [v3 report](research/ugly-stik-model-v3.md) | Complete for sampled poses |
| US-05 | Wing poses and clearances checked across 30 pose pairs; incidence and dihedral remain estimates. [Wing limits](research/ugly-stik-model-v3-wing.md) | Complete for sampled poses |
| US-06 | A 36-case, 20/50/100 m orientation study and v4 pilot form are ready. [v3 readability](research/ugly-stik-model-v3.md) · [v4 finish report](research/ugly-stik-model-v4.md) | Pilot responses pending |
| US-07 | Generic .61 installation, pivots, contacts and frame conversions documented. [Installation handoff](research/ugly-stik-model-v3-installation.md) | Visual handoff complete; physical installation remains generic |
| US-08 | v5 model has 74 meshes, 46,840 triangles and 25 materials. [Engine v5 validation](research/ugly-stik-engine-v5.md) | Implementation complete; target-GPU timing pending |

| ID | Visual deliverable and proof | Status checked 2026-10-12 |
| --- | --- | --- |
| US-V01 | Reproducible appearance source, vector art and atlas. [Finish report](research/ugly-stik-model-v4.md) | Complete |
| US-V02 | Red/white/black finish, UV mapping, articulated markings and scalloped edges. [Finish report](research/ugly-stik-model-v4.md) | Complete |
| US-V03 | Generic .61 engine and exhaust; v5 opens the intake, cooling slots and exhaust outlet. [Engine report](research/ugly-stik-engine-v5.md) | Complete; exact commercial variant unknown |
| US-V04 | Hinges, horns and fixed-length control links remain posed with the surfaces. [Finish report](research/ugly-stik-model-v4.md) | Complete |
| US-V05 | Generic servos, supports, arms and wiring. [Finish report](research/ugly-stik-model-v4.md) | Complete |
| US-V06 | Retainers, mounts, wheels and visible fittings. [Finish report](research/ugly-stik-model-v4.md) | Complete |
| US-V07 | Wing surface detail, propeller detail and reproducible close views. [Photo brief](research/ugly-stik-visual-photo-brief.md) | Complete |
| US-V08 | Geometry cost and repeated captures recorded; 20/50/100 m orientation form prepared. [Finish report](research/ugly-stik-model-v4.md) · [engine v5 validation](research/ugly-stik-engine-v5.md) | Implementation complete; pilot reading and target-GPU acceptance open |
| US-V09a | Glossy film covering, rounded fuselage corners, occluded hinge gaps, spline fin/rudder outline, smooth propeller and tyres, 2048 px atlas; before/after flight and bench captures. [Finish v6 report](research/ugly-stik-finish-v6.md) | Implemented 2026-10-13 (`b19f6a4`); pilot reading of the new finish open |
| US-V09b | Film-over-structure normal map from Jensen sheet 2 ribs/spars (replaces 2 in rib hint lines); narrow hinge bevel shaded with the adjacent skin. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09b--film-over-structure) | Implemented 2026-10-13; pilot reading open |
| US-V09c | Throttle linkage follows the command: separate carburettor lever on −X, gas servo and constant-length pushrod; 21-step sweep and rod/engine clearance probe. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09c--throttle-linkage) | Implemented 2026-10-13 |
| US-V09d | Varnished wooden propeller: tip-to-tip grain UVs, procedural straight grain, gloss; blur disc colour preserved. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09d--varnished-wooden-propeller) | Implemented 2026-10-13 |
| US-V09e | Glow-oil exhaust residue on the right side and belly (seeded, compiled into the atlas; `exhaust_residue.enabled` toggles it); fuselage side/belly UV unwrap. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09e--glow-oil-exhaust-residue) | Implemented 2026-10-13 |
| US-V09f | Oil spray on the right stab/elevator underside; stab undersides unwrapped into the atlas. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09fh--tail-spray-hatch-seams-and-field-wear) | Implemented 2026-10-13 |
| US-V09g | Fuel-tank hatch seams traced from Jensen sheet 1 (front to station 1). [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09fh--tail-spray-hatch-seams-and-field-wear) | Implemented 2026-10-13 |
| US-V09h | Grass/soil spray behind the nose wheel, belly scuffs and tail-strike scrapes (`belly_wear.enabled`). [Finish v6 report](research/ugly-stik-finish-v6.md#us-v09fh--tail-spray-hatch-seams-and-field-wear) | Implemented 2026-10-13 |
| US-V10 | Landing-gear flex: legs bend as clamped cantilevers to the axle the physics compression moves; nose fork rides with its wheel; GPU blend shapes. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v10--landing-gear-flex) · `tests/test_gear_flex.gd` | Implemented 2026-10-13 |
| US-V10b | Sprung steerable wire nose gear (Jensen torsion coil + owner-photo compression spring): wire telescopes into its spring, bows aft past solid; steering about the wire axis. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v10b--sprung-nose-gear) · `tests/test_gear_flex.gd` | Implemented 2026-10-13 |
| US-V11 | Broken propeller after a prop strike: hub and splintered stubs stay (pale fracture, slivers) instead of the whole propeller vanishing; same stubs on the wreck; blur respects the break. [Finish v6 report](research/ugly-stik-finish-v6.md#us-v11--broken-propeller-after-a-prop-strike) · `tests/test_prop_strike_feedback.gd` | Implemented 2026-10-14 |
| US-V12 | Contact scuffs: a soft touch that continues the flight leaves a grass, soil or runway scuff fitted onto the struck skin (rides with hinged surfaces; capped, cleared on restart). [Finish v6 report](research/ugly-stik-finish-v6.md#us-v12--scuffs-from-soft-contacts) · `tests/test_airframe_scuffs.gd` | Implemented 2026-10-14 |

## Limits and acceptance

The visible wing section is traced from a kit rib; it is not an identified airfoil polar. Hidden geometry, incidence, dihedral, materials, equipment and detailed engine proportions include estimates. The assembly origin is not a measured CG. Mass, inertia, propulsion and aerodynamic coefficients come from separate physics data; do not infer them from the mesh. No exact commercial .61 engine was identified from the reference photos.

The Jensen title block gives 720 in²; the older project decision records 723 in². Current geometry uses 720 in². A full-size plan read places its reference CG 4.76 in aft of the leading edge (39% of a 12.07 in measured chord); this is a drawing reference, not a measured build. The 12.00 in `720/60` ratio is a comparison, not an independent scale check. The metrology report records the scan-scale residual, and [DECISIONS](DECISIONS.md) records the CG choice.

The owner should score the v4 orientation cases and record resolution, camera and GPU time on the target machine. Any change prompted by that review must use comparable views and preserve the measured geometry. Mini and giant variants, internal structure, LOD, photoreal finish and a commercial engine installation remain deferred. The model can support first-flight playtesting while these fidelity limits stay explicit.

The detailed diagnosis and open validation of the high-speed pull-up remain in the active [pull-up plan](UGLY-STIK-PULLUP-PLAN.md). Its experimental polar path does not establish aircraft-specific calibration.
