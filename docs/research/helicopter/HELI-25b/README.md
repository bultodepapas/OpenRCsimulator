# HELI-25b: articulated HX-700 source review

**Date:** 2026-10-14. **Status:** delivery inspected; integration is planned, not installed. The [helicopter plan](../../../plans/helicopter.md#811-articulated-hx-700-delivery-integration) owns implementation order. The current flyable X-Cell research trainer retains its accepted asset and physics.

## Source and inspection

Source: `assets/source-deliveries/hx-700-articulated/HX-700_Helicoptero_RC_1.blend`, 4,044,205 bytes, SHA-256 `1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f`. Blender 5.2.2 LTS opened it in a separate factory-startup background process with automatic Python execution disabled. The embedded generator was extracted and inspected, not executed. Simple-expression drivers evaluated. Every probe confirmed the source hash unchanged. The user's live Corsair scene was inspected read-only and left untouched.

The scene contains 182 objects: 82 meshes, 79 empties, 16 cameras, four lights and one curve; no armature. The aircraft subtree contains 145 objects and 81 meshes, with 675,534 evaluated triangles, versus 217,892 in the earlier source audit. Scene totals include study geometry. The largest aircraft contributors include the 163,880-triangle canopy, 60,000-triangle cyclic-servo mesh and 28,184-triangle landing gear. This is a detailed master, not a qualified runtime budget.

[Inventory](inventory.json) records hierarchy, transforms, driver expressions, constraints and embedded-document hashes. There are 286 object drivers in the full scene; this count excludes material/node-tree animation. The aircraft has 18 Damped Track and nine Stretch To constraints. It has no `openrc_section` tags. Source coordinates are metres, +X nose, +Y left, +Z up; millimetres in the UI/rod document do not change the metre coordinate basis.

Embedded `LEEME`, `RIG_JUNTAS.json` and `RIG_BIELETAS.json` describe three cyclic servos, a tail servo, fixed/rotating swash, main and tail feathering, nine rod assemblies, a tail slider/bellcrank/yoke, belts, planetary gears and a freewheel demonstration. The source's mechanical geometry and diagnostic formulas are useful authoring evidence; they do not establish actuator performance or flight aerodynamics.

[Assembled inspection](assembled.png) and [mechanism inspection](mechanics.png) use Workbench colours by object to distinguish parts. They are not paint/material acceptance images.

## Pose probes

[Raw 26-sample results](pose-probes.json) include neutral, collective ±10°, cyclic, tail ±15°, combined commands, four rotor phases, adjustments, actuator saturation and an intentionally invalid rod length. Actions were detached in the disposable process before inputs were set.

| Observation | Result / interpretation |
| --- | --- |
| Admissible rod geometry | All 25 admissible samples close the nine endpoint distances to under 0.00008 mm numerical residual; no invalid object drivers. This is floating-point closure evidence, not manufacturing precision. |
| Collective / tail | ±10° collective and ±15° tail track their requested values closely in neutral cyclic. |
| Mechanical coupling | Pure cyclic changes the reported mean pitch by approximately −0.068° to −0.074° across sampled phases. Mixed collective/cyclic also varies with phase. Compare full phase curves/harmonics, not a blanket zero-mean error assumption. |
| Tracking adjustment | A +1 mm head-A link adjustment gives about 2.12182° tracking difference and changes mean pitch. |
| Tail adjustment | A +1.5 mm tail rod adjustment gives about −4.5042° tail pitch at zero requested tail command. |
| Servo limits | Reduced cyclic travel saturates front-left/rear; reduced tail travel saturates tail. The achieved geometry differs from command and remains closed. |
| Negative control | +100 mm on a cyclic rod is outside the source's declared ±3 mm adjustment range. It produces an 88.04 mm maximum closure residual and one invalid `ALF` driver on `Mezclador_15_Plato_Real`; the general alert rises but `bloqueo_mecanico` stays zero. Reject invalid ranges and check driver validity and every closure independently; that flag alone is not a complete admission test. |

The source solver uses inverse trigonometric clamping and two swash reconstruction passes. Preserve its branch choices as oracle data, but require convergence/residual and reachability checks before admitting a runtime solver. Runtime admission must reject the +100 mm negative control against the source's ±3 mm cyclic-rod bound; a raised LED is insufficient. Never stretch a rigid rod to hide a failed closure.

## Export probe and contract gaps

The existing static HX export helper produced a 9,084,512-byte GLB: SHA-256 `9dff4d561a94e07a83b3129eb4df00ab0ef19c70879028f2e7511aeb2d253fcd`, 86 nodes, 78 meshes, 28 materials, three images and zero animations. Its JSON accessors/primitives contain 262,716 indexed triangles and 206 material surfaces; these differ from the evaluated Blender master count and are not measured draw calls. [Export record](export-probe.json). It is a neutral snapshot, not a working transferred mechanism. The exported node list omits joint-anchor/helper empties; retain/export or encode all required local attachment frames in the new binding pipeline. No Godot articulated-import or packaged-flight acceptance is claimed.

The exporter also warned that multiple image-texture nodes share a texture and the first node determines its glTF sampler. Check the canopy's texture sampling and material appearance in Godot before acceptance; the Workbench inspection does not validate this conversion. A second fresh export reproduced the GLB hash above.

The existing adapter cannot simply consume this hierarchy. `Pivote_Rotor_Principal` includes the shaft, planetary carrier and inner swash; tilting its entire mount with `a1/b1` would tilt mechanical parts that must stay on the shaft. Main blades and grips are siblings driven independently, not a ready-made feather hierarchy; applying a pitch to both after reparenting would double it. The tail slider is nonrotating; its yoke both rotates and slides. Keep these distinct frames.

The source's 53.13° virtual swash rotation combines linkage lead and its precession convention. Resolve this against the flight kernel's cyclic signs/dynamic response before composing transforms. The current analytic rotor has disc-flap states, but no coning or per-blade elastic state. Do not infer those motions from collective alone.

The Blender rig describes an electric candidate: 5.2 kg, 2100 rpm, 12S/44.4 V, 530 KV and 3.5 kW; motor/main ratio 9.636364 and tail/main 4.923077. These are source-declared design values. The current X-Cell surrogate is 8.2 kg, 167 rad/s and tail/main 4.66 with a different drive. Do not copy the Blender aerodynamic telemetry, governor, mass or gear values into that profile. Servo manufacturer, BEC rail, loaded response, component masses and full inertia remain unverified.

## Reproduce

From the repository root (use fresh output directories for exports):

```powershell
$Blender = 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
& $Blender --background --factory-startup --disable-autoexec 'assets/source-deliveries/hx-700-articulated/HX-700_Helicoptero_RC_1.blend' --python research/helicopter/assets/audit_hx700_revision.py -- --out .tools/heli25b-audit
& $Blender --background --factory-startup --disable-autoexec 'assets/source-deliveries/hx-700-articulated/HX-700_Helicoptero_RC_1.blend' --python research/helicopter/assets/probe_hx700_revision.py -- --out .tools/heli25b-poses
& $Blender --background --factory-startup --disable-autoexec 'assets/source-deliveries/hx-700-articulated/HX-700_Helicoptero_RC_1.blend' --python research/helicopter/assets/preview_hx700_revision.py -- --out .tools/heli25b-preview
```

Reference: [Blender glTF animation/custom-property export](https://docs.blender.org/manual/en/5.1/addons/import_export/scene_gltf2.html) describes transform/shape animation and extras; [Godot's import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) confirms that `.blend` import also passes through glTF. A baked demonstration can document poses; it does not replace live control logic. Source-specific export behavior above was measured with installed Blender 5.2.2.
