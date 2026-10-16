# HX-700 advanced mechanical inspection

HELI-25c/26a, 2026-10-15. The owner's advanced Blender delivery has a strict neutral asset loader and an interactive mechanical inspector. The current work targets this articulated revision exclusively. Motion is source-derived kinematic inspection; it does not install a flight model or achieved servo dynamics. [Evidence](../../../../docs/research/helicopter/HELI-26a/README.md); [remaining flight integration](../../../../docs/plans/helicopter.md#811-articulated-hx-700-delivery-integration).

## Inspect the advanced mechanism

From the repository root:

```powershell
./research/helicopter/inspect-mechanics.ps1
# Any supported host with the pinned engine:
godot --path app --script res://tools/inspect_hx700.gd
```

The Spanish inspection panel exposes collective (±13°), lateral/longitudinal cyclic (±10°, with the source's 10° cyclic ring), tail pitch (±20°), rotor azimuth and slow inspection rotation (0–12 rpm). Presets select neutral, positive collective, cyclic and tail. Head, tail and whole-airframe cameras support right-drag orbit and wheel zoom; Space stops/resumes rotation and R resets control demand. Main blades and canopy can be hidden to expose the mechanism. Inspection colours distinguish servo horns, swash/grips and links; switching them off restores the imported materials, whose conversion limits remain below.

Three cyclic servo horns drive the fixed swash; the inner ring rotates while following the same tilted plane. Main grips and their sibling blades feather once. The tail servo drives its rod, bellcrank, nonrotating slider, rotating/sliding yoke and both feathering grips. The mast stays on its axis and the gearbox cases stay fixed. Source transmission transforms use the source's ratios, independently of any historical flight surrogate.

`motion-source.json` is extracted from the immutable Blender source by `research/helicopter/assets/extract_hx700_motion.py`. The offline compiler emits `app/render/rotor/hx700_motion_equations.gd` from a restricted arithmetic syntax and explicit dependency graph. Runtime executes compiled expressions, not arbitrary Blender drivers or Python. The compiler cuts the disabled aerodynamic precompensation dependency and pins all maintenance adjustments to neutral, including tail-belt tension. The current model has no runtime shape-key deformation, servo lag/rate response, coning or elastic blades.

`hx700_mechanism.gd` computes a complete candidate pose before applying it. All nine rod endpoint distances must close within 2 µm; failed, nonfinite or out-of-range requests retain the previous valid pose. Ball-link orientation uses deterministic neutral-frame transport, preserving rod mesh scales; Blender's Stretch To is not used as a runtime rod law. The source's bounded reconstruction and first-harmonic coupling remain source-specific; this is not a general linkage solver or a flight controller. [HELI-26a tests](../../../../app/tests/test_heli_mechanism.gd) compare actual native world frames with independent Blender samples.

## Source and outputs

The immutable source is `NEW HELI/HX-700_Helicoptero_RC_1.blend`, SHA-256 `1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f`. [HELI-25b](../../../../docs/research/helicopter/HELI-25b/README.md) records its rig audit. `export-report.json` owns output identity and geometry counts; `neutral-reference.json` samples evaluated source-world frames independently of the glTF local-transform serialization. Provenance/distribution clearance remains separate from local software qualification.

The export retains 108 nodes, including four servo outputs, fixed/rotating swash roles, blade/grip pairs, tail slider/yoke/bellcrank and nine linkage endpoint pairs. Controller/telemetry empties, force arrows, cameras, lights, the deformation guide and demonstration animation are excluded. Original local hierarchies remain intact. The generator freezes evaluated neutral transforms and functional mesh deformation/thickness, omitting decorative bevel/weighted-normal modifiers. Its 345,236 triangles and 208 material surfaces are an inspection tier, not a qualified flight budget.

**Appearance gate:** the source's procedural carbon/blade colours and livery-mask mixing are not faithfully converted by this direct glTF export. Native captures show white carbon surfaces and mask colours. Source baking and a matched source/native material comparison are required before visual promotion. Successful texture dependency checks establish resource availability, not shader equivalence.

## Construction profile v1

`construction.json` uses `schema: "openrc-rotorcraft-construction"`, `version: 1`, and `purpose: "neutral-mechanical-preview"`. This visual-only sidecar is separate from `openrc-aircraft v2` flight data and the conventional-airplane model manifest.

| Field | Meaning |
| --- | --- |
| `profile_id`, `source`, `asset` | Explicit revision, immutable source/Blender identity and runtime GLB path/hash. The loader pins both GLB and profile bytes. |
| `coordinates` | `gltf-y-up-metres`: source +X nose, +Z up, +Y left become +X nose, +Y up, −Z left. No aircraft datum/CG substitution. |
| `bindings` | Stable semantic `id`, `role`, replaceable source `node`, `parent_id` and evaluated neutral `rest_transform`. Root parent is blank; each exported node has one binding. |
| `rest_transform` | Twelve finite numbers: Basis X column, Y column, Z column, then origin. Basis is dimensionless; translation is metres in the parent's rest frame. Rod-mesh scale is retained. |
| `linkages` | Nine unique IDs, matching `.a`/`.b` endpoint IDs and positive `length_m`, measured between terminal node origins. These are construction lengths, not identified physical coefficients. |

Native admission checks exact keys, topology, identity, transforms, endpoint closure, meshes, materials/textures and imported semantic metadata. It rejects scripts, animation nodes, cameras/lights and unbound nodes. [The loader](../../../../app/aircraft/hx700_articulated_model.gd) exposes a detached preview and semantic-node map through `load_preview()`; it exposes no flight-builder ABI. Raw GLB bytes must be available for SHA admission; missing bytes fail closed. Standard production presets explicitly exclude the inspection asset directory until flight/distribution admission is complete.

The construction profile remains a neutral-rest contract. The separate motion adapter additionally pins its source/profile identities and generated pose binding IDs before articulating the admitted nodes. It does not broaden the profile's flight capability.

## Reproduce

From the repository root, use fresh `.tools` output directories:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --disable-autoexec 'NEW HELI/HX-700_Helicoptero_RC_1.blend' --python research/helicopter/assets/export_hx700_articulated.py -- --out .tools/heli25c-export
python research/helicopter/assets/compile_hx700_articulated.py --generated .tools/heli25c-export --install
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --editor --import
python research/helicopter/assets/verify_hx700_articulated.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out .tools/heli25c-proof --capture
```

The compiler refuses changed source/output identities and differing installed artifacts. Run it without arguments to check installed authored/runtime copies against the independent source frames. Do not hand-edit generated GLB/JSON files. A deliberate source or generator change needs a new reviewed identity and loader constants.

The verifier runs focused native checks, imports a minimal project from scratch, then builds and launches local PCK fixtures containing the imported scene, all three compressed texture payloads, raw GLB and profile. Omitted profile/GLB/texture cases must reject. `--capture` requires a display and records native materials in assembled and canopy-hidden inspection views. The isolated pack proof does not qualify the production release exporter or articulated flight. [Evidence and remaining gates](../../../../docs/research/helicopter/HELI-25c/README.md).

Reproduce the motion source and independent oracle with the same disposable Blender invocation, replacing the exporter script with `research/helicopter/assets/extract_hx700_motion.py -- --out .tools/heli-motion-source`. Copy its `motion-source.json` here and `motion-oracle.json` to `research/helicopter/reference/hx700_motion_oracle.json` only after reviewing a deliberate regeneration; the `.blend` is never saved. Then run:

```powershell
python research/helicopter/assets/compile_hx700_motion.py
python research/helicopter/assets/compile_hx700_motion.py --check
python research/helicopter/assets/verify_hx700_articulated.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out .tools/heli26a-proof --motion --capture
```

The `--motion` gate adds native, fresh-import and packaged motion tests against the external independent oracle, plus five interactive-view captures. Tests and compiler freshness also run through `app/test.sh`. Use a fresh proof directory each time.
