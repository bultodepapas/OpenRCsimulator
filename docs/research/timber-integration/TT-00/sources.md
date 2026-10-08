# Turbo Timber Evolution: source and asset audit

**Status:** research only, 2026-10-08. Standalone evidence step TT-00; the owning plan and prefix are registered in the documentation map. **Scope:** official model references, owner-supplied Blender/CAD files, and Godot 4.7 import workflow. No app or physics data changed.

## Findings for the integration plan

The local asset package is a useful visual and geometric starting point, but it is not a validated flight model. Use the Blender/CAD source to build the presentation asset and take-off/landing contact references; use the manual and later flight measurements for physical data. Exact source hashes, audit commands and later-arriving gear scripts/ZIP are recorded in [TT-00](README.md). The package has detailed moving-part metadata, but the flight-critical numbers still need provenance and independent validation.

### Identify the model revision before choosing data

The official current Turbo Timber Evolution 1.5m is sold in two completion versions: **EFL105250B BNF Basic**, with the AR637TA receiver and AS3X/SAFE Select, and **EFL105275B PNP**, which requires a separate receiver. Both current B variants have the 2024 70 A Smart Lite ESC and heavier-duty landing-gear springs; both include optional slats and floats. These are configurations of the same airframe, not separate aerodynamic variants. [Current BNF product page](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html) · [current PNP product page](https://www.horizonhobby.com/product/turbo-timber-evolution-1.5m-pnp-includes-floats/EFL105275B.html)

The earlier unsuffixed **EFL105250 / EFL105275** editions used a 60 A Avian ESC and had different published masses. Do not mix those mass or power-system values into a model of the current B revision. [Earlier BNF page](https://www.horizonhobby.com/product/turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250.html) · [earlier EFL105250/275 manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250-Manual-EN.pdf)

### Verified current B-revision reference values

Values below come from Horizon Hobby's current EFL105250B manual unless stated otherwise. They are suitable as initial declared data, not proof that a simulated flight is accurate.

| Quantity | Published value | Evidence and use |
| --- | --- | --- |
| Wingspan / length | 1,555 mm / 1,040 mm | Model dimensions in the manual. Check the local mesh against both before setting model scale. |
| Mass, without battery | 1,860 g | Current B revision. Earlier unsuffixed manual says 1,820 g. |
| Mass with recommended 4S 3,200 mAh battery | 2,190 g | Current B revision. Earlier unsuffixed manual says 2,150 g. The 40 g revision difference is consistent with a hardware revision; do not silently average the values. |
| CG | 60 ± 5 mm aft of wing-root leading edge, **without slats** | Set the reference coordinate at the wing root and make the battery/loadout explicit. No slat-on CG is specified in the manual. |
| Motor | Brushless outrunner, 800 Kv, 14-pole; current part SPM-1012 | Motor data do not provide a thrust curve, propeller torque map, or installed thrust. |
| ESC | Avian 70 A Smart Lite, 3S–6S | Current B revision. The old 60 A part belongs to the previous unsuffixed edition. |
| Propeller | 11 × 7.3, three blade | The manual gives 11 × 7.3; Horizon's replacement part EFL5962 identifies it as a three-blade propeller. [EFL5962](https://www.horizonhobby.com/product/3-blade-propeller-11-x-7.3/EFL5962.html) |
| Battery | 3S or 4S, 2,200–5,000 mAh compatible range; recommended 4S 3,200 mAh 30C | Use the recommended battery for reproducing the manual's 2,190 g ready-to-fly mass. Capacity alone is not battery mass or CG. |
| Controls | Two ailerons, two flaps, elevator, rudder; six 9 g metal-gear servos | Manual's BNF/PNP equipment table. The radio setup groups paired surfaces by channel. |
| High / low throws | Aileron ±33 / ±25 mm; elevator ±20 / ±15 mm; rudder ±30 / ±20 mm | Manual quick-start setup. These are linear surface movements; do not compare directly with local hinge angles without converting at a defined measurement point. |
| Flaps | Half 20 mm; full 35 mm; down-elevator compensation 16% / 30% | Manual transmitter setup. These values define setup targets, not flap aerodynamic coefficients. |
| Slats | Optional. Manual recommends no slats for optimized high-speed performance and slats for maximum slow-speed performance. | A discrete geometry/configuration and aero case; do not blend slat-on and slat-off data. Manual CG is explicitly slat-off. |
| Floats | Optional included equipment; manual describes water taxi, planing “on step,” water takeoff and landing. | Float operation requires water-contact/planing physics that the existing ground-contact model may not represent. Treat as a later sub-scope. |
| Stabilization | BNF includes SAFE Select; AS3X remains active in both SAFE Select and AS3X modes. SAFE Select limits bank/pitch and self-levels around neutral; PNP's receiver is user-supplied. | A simulator model can expose optional assist modes, but this is receiver behavior and should be a separate layer from airframe aerodynamics. |

Primary reference: [current EFL105250B manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250B-Manual_EN.pdf). The manual specifies the current mass on PDF page 3, dimensions and equipment on page 3, CG and propeller on page 13, throws on page 14, slat choice on page 9, and SAFE Select/AS3X behavior on pages 4 and 14. The older unsuffixed manual gives 1,820 g empty, 2,150 g with 4S 3,200 mAh, 60 A ESC and the same basic CG/throws. This is the evidence for separating B revision from the earlier release.

The product/manual sources do **not** provide a measured aerodynamic coefficient set, mass moments of inertia, motor/propeller thrust and torque curves, servo speed/deadband, stall polar, or handling-quality measurements. Treat values derived from geometry or generic airfoil/motor data as estimates with evidence kind and uncertainty; obtain owner measurements or flight-identification data before claiming physical validation.

## Local asset audit

This is a filesystem/metadata audit. Blender was not installed in the research environment, so the `.blend` scene and its visual appearance were **not** inspected in Blender.

| Supplied file | Observed | Recommended planning use / limitation |
| --- | --- | --- |
| `Timber turbo evolution/turbo_timber_evolution_v12.blend` (32.5 MB) | Blender 5.2 file with Zstandard compression; a read-only DNA parse finds 171 objects, 130 meshes, 20 materials, 7 cameras, 2 lights, and actions `MandosAction` and `TrenAction`. Control-surface hinge parenting and drivers are present. No Blender executable was available for a visual open/export round-trip. | Preserve as the editable authoring source. Before choosing it as Godot's import source, perform a visual open/export check in Blender and review collections, object names, materials, transforms, textures, and actions. |
| `Timber turbo evolution/turbo_timber_evolution_v12.step` (41.2 MB) | STEP CAD source present. | Keep as a geometric reference/master for measurements and repair. Godot 4.7's supported scene-format list does not include STEP, so it needs a DCC/CAD conversion before runtime use. |
| `Timber turbo evolution/piezas_stl_v12/` | 112 binary STL files, 56.7 MB total; about 1.13 million triangles by binary STL headers. Includes fuselage, left/right wings, ailerons, flaps, tail surfaces, propeller, gear, springs, linkage and many hardware parts. | Useful for part identity, rough geometry and measurement. Do not import all pieces at full detail as the final in-flight model: two spring meshes alone contain about 765,000 triangles, and the slat-support meshes about 104,000. Retain detailed CAD offline; build a reduced render hierarchy and simple contact shapes. STL alone is not the source for materials or articulation. |
| `Timber turbo evolution/piezas_stl_v12/escena.json` (9.9 KB) | Spanish-keyed manifest maps part names to materials and describes hinge points/axes, pushrods, landing-gear anchors, component boxes/masses, motor-axis offsets and control limits. The CAD/manifest frame is millimetres, with X aft, Y right, Z up. | Valuable as a rig/measurement cross-check and a starting inventory for naming. It is not app-ready aircraft data: provenance is not recorded per field and geometry/physics values need validation and conversion into repository schema. |

Derived local geometry check: STL bounds are 1,548.1 mm across Y, 1,116.2 mm along X, and 434.0 mm along Z. The Y extent is close to the published 1,555 mm span (−0.45%); X extent differs from published 1,040 mm length by 76 mm (+7.3%). Inspect the assembled model, included protrusions and measurement endpoints before setting scale; this is not proof that either source is wrong. Blender object transforms are already metric, while manifest/CAD coordinates are millimetres: document the transform chain and avoid applying a second unit conversion to either representation.

The manifest's control-angle defaults are 22° aileron/elevator, 30° rudder and 40° flap, with 0.7 differential. The manual reports linear throws, so these local angles are **unverified authored settings** until hinge geometry and the manual's measurement point are reconciled. The manifest assigns 340 g to the battery; the manual's current ready-to-fly minus empty mass is 330 g (derived), a 10 g discrepancy to check against the exact battery and the rounded manual masses. Other useful geometry anchors are the prop hub at `[-251.5, 0, 0]` mm and motor offsets of 2° down and 2° right; Horizon's manual does not publish a motor-axis angle, so preserve these as local authored values pending measurement. Listed component masses sum to 674 g; this is not total aircraft mass and omits structural mass distribution. The manifest has no aircraft CG or inertia. The STL filenames include slat supports but no obvious slat or float meshes; confirm the optional geometry in Blender before planning those configurations.

## Godot 4.7 import guidance

Godot 4.7 recommends glTF 2.0 and supports both `.glb` and `.gltf`. A `.blend` file is imported by running Blender's glTF export internally, so it adds a Blender installation/version dependency for each developer and CI import environment. The team-friendly source-of-truth workflow is therefore: preserve the `.blend` authoring source outside the runtime asset path; export a curated, deterministic `.glb` for the project; import it through Godot's glTF scene importer. Use `.gltf` plus separate `.bin`/textures only when text diffs or external texture control materially help asset review. [Godot 4.7 available formats and Blender workflow](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)

Before export, establish a named object/collection contract for the airframe, moving control surfaces, propeller, optional slats, and landing gear. Keep simulation hinge definitions in the model/physics data contract; do not rely on an imported Blender animation to drive flight physics. Export in the Godot/glTF axis convention after checking the simulator's local aircraft axes; apply transforms and triangulate consistently. The current local manifest uses millimetre-looking XYZ points, whereas Godot uses right-handed Y-up coordinates and its oriented asset convention uses +Z as asset-forward, so axis mapping and unit scale need an explicit, measured import check. [Godot 4.7 model export conventions](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html)

Godot's Import dock/Advanced Import Settings can configure root scale, node visibility, per-object scene handling, mesh LODs, and other import settings. Godot also allows a post-import script, but prefer fixing the Blender source when a stable object contract can be authored there. Keep the imported file immutable and make the aircraft presentation scene an inherited/wrapper scene that adds app-owned pivots and effects. [Godot 4.7 import configuration](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html)

The existing app uses the Compatibility renderer. Confirm glTF materials/textures render on that target and review object count, triangle count, texture dimensions, transparency and shadow cost before accepting the source model. Preserve a separate physics representation; detailed visual meshes are not aerodynamic surfaces or ground collision geometry by default.

## Primary sources

- [Horizon Hobby: current BNF Basic EFL105250B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html)
- [Horizon Hobby: current PNP EFL105275B](https://www.horizonhobby.com/product/turbo-timber-evolution-1.5m-pnp-includes-floats/EFL105275B.html)
- [Horizon Hobby: current EFL105250B instruction manual (PDF)](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250B-Manual_EN.pdf)
- [Horizon Hobby: earlier EFL105250/275 instruction manual (PDF)](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFL105250-Manual-EN.pdf)
- [Horizon Hobby: 3-blade 11 × 7.3 replacement propeller, EFL5962](https://www.horizonhobby.com/product/3-blade-propeller-11-x-7.3/EFL5962.html)
- [Godot 4.7: available 3D formats and Blender/glTF workflow](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)
- [Godot 4.7: model export considerations and axes](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html)
- [Godot 4.7: scene import configuration](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html)
