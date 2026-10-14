# HX-700 articulated inspection asset

HELI-25c, 2026-10-14. This is a neutral mechanical preview of the owner's revised Blender delivery. The playable X-Cell trainer retains its existing visual and physics. No Blender control logic, aerodynamic telemetry, actuator dynamics or flight capability is installed by this profile. Motion axes, signs, travel and achieved actuator states require the next contract/kinematic stage in the [helicopter plan](../../../../docs/plans/helicopter.md#811-articulated-hx-700-delivery-integration).

## Source and outputs

The immutable source is `NEW HELI/HX-700_Helicoptero_RC_1.blend`, SHA-256 `1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f`. [HELI-25b](../../../../docs/research/helicopter/HELI-25b/README.md) records its rig audit. `export-report.json` owns output identity and geometry counts; `neutral-reference.json` samples evaluated source-world frames independently of the glTF local-transform serialization. Provenance/distribution clearance remains separate from local software qualification.

The export retains 108 nodes, including four servo outputs, fixed/rotating swash roles, blade/grip pairs, tail slider/yoke/bellcrank and nine linkage endpoint pairs. Controller/telemetry empties, force arrows, cameras, lights, the deformation guide and demonstration animation are excluded. Original local hierarchies remain intact. The generator freezes evaluated neutral transforms and functional mesh deformation/thickness, omitting decorative bevel/weighted-normal modifiers. Its 345,236 triangles and 208 material surfaces are an inspection tier, not a qualified flight budget.

## Construction profile v1

`construction.json` uses `schema: "openrc-rotorcraft-construction"`, `version: 1`, and `purpose: "neutral-mechanical-preview"`. This visual-only sidecar is separate from `openrc-aircraft v2` flight data and the conventional-airplane model manifest.

| Field | Meaning |
| --- | --- |
| `profile_id`, `source`, `asset` | Explicit revision, immutable source/Blender identity and runtime GLB path/hash. The loader pins both GLB and profile bytes. |
| `coordinates` | `gltf-y-up-metres`: source +X nose, +Z up, +Y left become +X nose, +Y up, −Z left. No aircraft datum/CG substitution. |
| `bindings` | Stable semantic `id`, `role`, replaceable source `node`, `parent_id` and evaluated neutral `rest_transform`. Root parent is blank; each exported node has one binding. |
| `rest_transform` | Twelve finite numbers: Basis X column, Y column, Z column, then origin. Basis is dimensionless; translation is metres in the parent's rest frame. Rod-mesh scale is retained. |
| `linkages` | Nine unique IDs, matching `.a`/`.b` endpoint IDs and positive `length_m`, measured between terminal node origins. These are construction lengths, not identified physical coefficients. |

Native admission checks exact keys, topology, identity, transforms, endpoint closure, meshes, materials/textures and imported semantic metadata. It rejects scripts, animation nodes, cameras/lights and unbound nodes. [The loader](../../../../app/aircraft/hx700_articulated_model.gd) exposes a detached preview and semantic-node map through `load_preview()`; it exposes no flight-builder ABI. Raw GLB bytes must be available for SHA admission; missing bytes fail closed. Standard production exports do not yet activate this asset.

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
