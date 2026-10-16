# HELI-26a: advanced HX-700 elastic load bench

2026-10-16 · Windows · Godot 4.7.2-stable · advanced articulated source only. [Operating instructions](../../../../assets/aircraft/hx-700/articulated/README.md#elasticity-bench) own the UI and commands. This adds estimated structural response to the existing inspector, not a flight or landing qualification.

## Analysis and source geometry

An elastic landing support stores energy and rebounds; damping dissipates energy. These must be separate terms. NASA's [Ingenuity landing-gear explanation](https://science.nasa.gov/blog/keeping-our-feet-firmly-on-the-ground/) describes those distinct functions, while its [Wasp skid drop-test report](https://ntrs.nasa.gov/citations/20070031763) illustrates the need to compare structural models with measured drop response. Neither vehicle supplies transferable HX-700 coefficients.

The supplied [HELI-25b inventory](../HELI-25b/inventory.json) and immutable embedded `generar_hx700.py` define geometry, not modulus, damping, laminate construction or identified modes. Generator SHA-256 is `4c446055333b7d11c3a83b28d4adaaa061393ec03bc4c9e9cb97e835aa925e2e`; the existing source audit extracts it without execution. Coordinates below are source metres (+X nose, +Y left, +Z up):

- Lines 1967–1989: two rail tubes at Y=±0.0858, radius 0.0055, flat centreline Z=0.0084 over X≈−0.170…0.150. Four supports at X=±0.085 curve from (|Y|,Z)=(0.039,0.084) to (0.0858,0.0108). Upper mounting boxes, struts, low clamp rings, tube sweeps, end fittings and fasteners share one mesh but distinct material assignments.
- Lines 832 and 1761–1773: canopy posts at (X,Z)=(0.150,0.145) and (−0.040,0.204), on both sides. Posts and rubber grommets are separate meshes. Lines 1672–1706 define a shell with a 1.8 mm Solidify thickness; the source has no elastic shape keys. Its canopy-removal translation is not a flex mode.

The advanced geometry is not substituted into the historical flyable surrogate. Existing `skid_contact.gd` computes normal support from penetration and velocity; that penalty law is not an identified structural model. Its coefficients and the older source's contact/datum estimates are not reused here.

## Reduced model and declared estimates

Each independent generalized displacement obeys `m q'' + c q' + k q = F`. The held-force solution is analytic. All state/energy quantities use scalar doubles or packed float64 arrays. Render vectors occur only in the skin adapter. Work is `F * (q_new - q_old)`; dissipated energy is work minus the change in `½mv² + ½kq²`. Release preserves velocity and position. Invalid loads/times and excursions outside the declared domain fail without partial state commit. The first two alternating extrema are checked so a long frame cannot conceal an intermediate limit violation.

| Mode | Effective mass | Stiffness | Damping | Applied load domain | Displacement domain |
| --- | ---: | ---: | ---: | ---: | ---: |
| Each skid | 2.6 kg | 6000 N/m | 80 N·s/m | 0–51 N | ±20 mm |
| Canopy lateral | 0.06 kg | 800 N/m | 2.5 N·s/m | ±2 N | ±8 mm |

Every coefficient is an **estimate for this bench**. Each skid's effective inertia is half the source-declared 5.2 kg carried mass, not a measured rail/strut mass. It represents a loaded low-frequency compliance coordinate while the view stays in the chassis frame; the bench does not solve body heave/roll or a constrained laboratory fixture. The shell effective mass is an assumed modal participation. Stiffnesses give about 4.25 mm symmetric support compression and 2.5 mm shell displacement at the provided loads; damping gives decaying underdamped recovery. These choices are not fitted to real hardware. Slider forces are applied generalized loads, not inferred contact reactions or rotor vibration.

The source-declared 5.2 kg preset supplies `5.2 × 9.80665 = 50.99458 N`, divided equally or assigned to one skid. Two skid coordinates omit fore/aft twist and coupling. The shell coordinate represents lateral bending only. Mount compliance, local indentation, geometric nonlinearity, material hysteresis, ground resonance, damage and fracture are absent. Limits reject unsupported states; they do not create an artificial hard stop or permanent damage.

## Rendering integration

The instance-owned ArrayMesh morph pipeline consumes the hash-admitted source mesh. Rail tubes and fittings translate intact; low graphite clamps and screws follow them. Upper mounting boxes and bolts stay fixed. A smooth height weight bends only the support span. Outward rail motion per unit compression is `(0.084−0.0108)/(0.0858−0.039)`, preserving the end-to-end support chord length to first order; it is not an inextensible finite-strain beam calculation.

The canopy mode increases toward the nose and vanishes inside four estimated 8 mm attachment patches around the source post stations, with a smooth 45 mm transition. The two station coordinates apply on both shell sides. Posts and grommets remain untouched; flexible mount isolation is not claimed. Both shell surfaces and the rim use the same smooth field. Normals use inverse-transpose target deformation and tangents use the forward deformation; GPU interpolation is a small-deformation shading approximation. UVs, indices and original materials remain intact. Expanded culling bounds cover signed displacement. The construction profile, original meshes and all mechanism node transforms remain unchanged.

Morph arrays are built once per admitted instance; frames update three weights only. [Godot's ArrayMesh contract](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-method-add-surface-from-arrays) defines the vertex/normal/tangent morph arrays. Inspection colours and softer stage lighting make supports and shell curvature readable; disabling colours restores imported materials.

## Verification

[Native checks](elasticity-native-tests.log), [fresh-import checks](elasticity-fresh-tests.log), [isolated-package checks](elasticity-package-tests.log), [combined receipt](verification.json).

All **26 elasticity checks** pass in each environment. They cover an independently integrated RK4 reference, static `F/k`, symmetrical/asymmetrical loading, energy balance, passive release/rebound, 1/30/60/144 Hz held-load tapes, invalid inputs and hidden intermediate overtravel. Actual morph vertices establish fixed chassis bases/bolts, rigid rails/fittings/clamps, bending support spans and **224 pinned shell vertices**. Tests also check neutral geometry/material preservation, signed render weights, stopped-rotor animation, pause/step and rollback after mechanism rejection. Maximum numerical differences in the independent-reference and frame-rate comparisons are below 1e-13.

The 2026-10-16 audit adds 10,000 seeded variable-load/time steps: all are accepted, with maximum accumulated work/energy imbalance **1.42 × 10⁻¹² J**. Engine-evaluated mesh baking checks neutral, negative and greater-than-one morph weights, including the declared displacement limits; vertex error is zero against the linear modal displacement and normals remain finite/unit length. This checks the engine's evaluated geometry, not just the target arrays or assigned weights; it is not GPU performance qualification.

The companion mechanism, UI, timing and admission checks also pass; [current counts and audit findings](README.md#verification) are authoritative. Missing-resource packages and the deliberately wrong socket rotation remain rejected. These are software and dependency checks, not structural calibration. Full application regressions and production release exports were not run for this isolated inspector change.

Native captures show [unloaded](flex-unloaded.png), [symmetric support](flex-support.png), [one skid](flex-one-skid.png), [canopy loaded](flex-canopy.png), [25 ms after release](flex-release-025ms.png) and [recovery](flex-recovered.png). Scale is 1:1. Source Blender, GLB and construction hashes remain pinned by the existing verifier. No flight data, recorder/replay format, golden flight or shared Simulation code changes; the fixed-wing `.orfl` workflow is not represented as covering this standalone bench.

## Flight coupling remains a separate gate

For future articulated flight, add accepted elastic state through the vehicle model's layout/evaluator, evaluate deformed contact positions **and velocities** at each solver stage, and apply reaction work consistently to body and structural coordinates. Simply animating from the existing penetration spring while adding another dynamic spring would double-count compliance or introduce force lag. Canopy excitation needs declared local aerodynamic/inertial loads; collective or arbitrary RPM noise is not a structural force. Calibrate with source-specific force/deflection and ring-down observations, then validate drop response and energy before enabling that coupling.
