# HELI-25c: neutral construction admission

**2026-10-14 · Windows / Godot 4.7.2-stable · Blender 5.2.2 LTS.** The revised HX-700 now has a reproducible neutral inspection export, versioned semantic construction profile and strict native admission. The installed flyable X-Cell trainer is unchanged. This foundation does not animate the new mechanism, identify servo hardware, change flight state or activate a new aircraft. [Pipeline, format and reproduction commands](../../../../assets/aircraft/hx-700/articulated/README.md); [remaining integration order](../../../plans/helicopter.md#811-articulated-hx-700-delivery-integration).

## Export and independent geometry proof

Source SHA-256: `1919de349b74286bc36770ab2d7d08f743fd8a4062608d488c7e4e276103725f`. Output GLB: `f5f7de25a586b65b0f77ab17497665cc5f47cc409de6c531cadf490676159e47`; construction profile: `e3a045e3da856cac11c53bb4a417b020d6737769d9c67a0f7370035bd01539d2`. Two separate Blender exports reproduced both output hashes. Every source hash check passed. The source was opened in disposable factory-startup processes with automatic Python execution disabled and was never saved.

The new export preserves 108 nodes and 78 meshes: four servo outputs, separate fixed/rotating swash roles, blade/grip pairs, tail slider/yoke/bellcrank and all nine linkage pairs. Each exported node has a unique semantic ID, role, parent and evaluated neutral local transform, with matching glTF extras. Controller/telemetry empties, force arrows, cameras, lights and demonstration animation are absent. The source's parked rotor offsets remain; the exporter does not zero the authored mount orientations or reparent blades under independently pitched grips.

The 10,961,424-byte asset has 345,236 indexed triangles, 208 material surfaces and three embedded images. Functional mesh deformation and canopy thickness are evaluated; decorative bevel/weighted-normal modifiers are omitted. These counts are an inspection tier, not measured draw calls or a flight budget. The [generated export record](../../../../assets/aircraft/hx-700/articulated/export-report.json) owns detailed output measurements.

The [independent reference frames](../../../../assets/aircraft/hx-700/articulated/neutral-reference.json) are sampled directly from evaluated Blender world transforms before export. The offline compiler reconstructs glTF/profile world frames independently and compares all 108 frames and nine endpoint distances. [Recorded proof](compiler-proof.json):

| Check | Maximum error | Admission bound |
| --- | --- | --- |
| Source/export basis component | 0.000003325 | 0.000005 |
| Source/export translation component | 0.000000275 m | 0.000001 m |
| Reconstructed linkage length | 0.000000033 m | 0.000002 m |

glTF omits nearly identity rotations left by the source's numerical neutral solve, so basis and translation use distinct bounds. These are conversion residuals, not manufacturing tolerances or physical validation.

## Native and package checks

[Native results](native-checks.txt): **38 checks, 0 failures**, including two independent instances. Clean admission verifies exact keys/identity, unique IDs/names, role cardinalities, connected acyclic parents, local transforms, all rods, native meshes/materials and semantic extras. Negative cases cover missing/duplicate bindings, wrong purpose/source/digest, unknown fields, malformed/nonfinite/singular/overflowing transforms, native NaNs, wrapper transforms, missing meshes, changed metadata, reused endpoints, altered lengths, cameras/lights/animation/scripts, empty/null required textures, absent raw bytes and one-byte GLB corruption. Deliberate file changes use disposable `user://` copies.

[Windows verification](verification-windows.json) also imports a minimal project containing only the new loader, GLB and profile, with no existing `.godot` cache. It builds a local fixture PCK from the unmodified fresh imported scene, compressed texture payloads, import metadata, UID cache, raw GLB and profile. A process launched from an empty directory admits all 108 bindings. [Package identity](package-proof.json); [clean package log](package-complete.txt). Packages omitting the profile, raw GLB or one texture are rejected; the [missing-texture log](package-missing-texture.txt) intentionally contains engine dependency errors followed by rejection. The verifier allows only that fixture's expected resource-error chain, never script errors.

This work found two real packaging traps. A scene can load with null texture slots after missing dependencies, so checking dimensions of non-null textures is insufficient: the loader also requires the source's authored textured slots. Re-saving the scene with `BUNDLE_RESOURCES` did not preserve the full imported texture graph; the accepted fixture retains original imports and metadata instead. The complete accepted package has no engine errors or broken-resource warnings.

The source compiler runs in `app/test.sh`; its existing test discovery includes `test_heli_construction.gd`. Focused native parse/test and the isolated verifier ran here. The complete application suite, production release export and physical flight were not rerun for this inspection-only addition. Production presets explicitly exclude the inspection asset directory until admission is extended.

## Native inspection and open appearance gate

[Assembled](assembled.png) and [canopy-hidden mechanics](mechanics.png) are native Compatibility captures at 1280×800 on an RTX 3090, from the fresh project. They establish visible geometry/resource transfer, not final appearance or target-machine performance. The close view intentionally crops the rotor/boom to inspect the mechanism.

The captures reveal incomplete shader conversion. `Fibra_de_Carbono` and `Pala_Carbono` have linked procedural colours that become untextured white glTF defaults; source livery-mask mixing also does not survive faithfully. The source generator explicitly authors dark carbon and blade-tip bands. Bake those authored shaders/masks into game PBR maps and compare matched Blender/Godot views before visual promotion. The Blender export's shared-texture sampler warning also remains part of that review. No substitute carbon appearance is invented in this foundation.

Signed joint axes, motion limits, pose-sweep transfer, achieved servo state, phase/blur ownership, a flight LOD and the independent electric HX-700 physical profile remain under the [active plan](../../../plans/helicopter.md#811-articulated-hx-700-delivery-integration). The neutral construction format grants no flight capability, and the X-Cell/HX-700 physical identity remains separate.
