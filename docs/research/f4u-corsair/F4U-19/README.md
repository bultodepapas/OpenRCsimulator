# F4U-19: review of request revision 4 (g1.24 and g2.0)

Reviewed 2026-10-24 for the [F4U plan](../../../F4U-PLAN.md). The author delivered both parts of [request revision 4](../../../F4U-BLENDER-HANDOFF.md#revision-4-fuselage-fix-and-a-g2-detail-tier): **A** as g1.24 (`F4U_Corsair_g1_24_Revision4A.zip`) and **B** as g2.0 (`F4U_Corsair_g2_0_Revision4B`). Both were only read. Nothing is frozen into the repository or the app yet.

## Verdict

| Part | Delivery | Verdict |
| --- | --- | --- |
| A, fuselage winding | g1.24, twelve liveries | **Accepted.** All twelve GLBs pass the preflight, including the skin-orientation rule (`fuselage_core` outward 0.831). In the default GLB, `fuselage_core` is the only mesh that differs from the shipped g1.13 (positions, normals, UVs and index sets compared). |
| B, g2 detail tier | g2.0, Naval 308 only | **Accepted in substance; three corrections requested for g2.1** ([g2.1 request](../../../F4U-G2-1-REQUEST.md)). The rig, contacts and budget fit the contract and the frame cost is unchanged. The propeller paint and the main wheels are worse than g1. |

## g2.0 checks

| Check | Result |
| --- | --- |
| Package integrity | 155/155 files match `SHA256SUMS.txt`; the ZIP matches its `.sha256` |
| Our preflight, `--profile f4u-g2` | PASS without warnings: 349,878 triangles, 46 mesh nodes, 61 surfaces, 16 materials, four 2048² images, span 2.7778 m. Skins face outward: `fuselage_core` 0.815, wing panels 0.83, tail and control surfaces 0.87–0.97 ([report](checks/preflight-g2_0.json)) |
| Rig against g1.13 | All 80 g1.13 nodes are present with the same parents, `openrc_section` tags and rest transforms (largest difference below 1 × 10⁻⁵). Two meshes are new: `gear_retraction_link_left/right`, under `gear_fold_left/right` |
| Wheel contacts | Main tyre diameter 188.30 mm and tail 77.78 mm, lowest points −530.82 mm and −183.33 mm with the gear down: equal to g1 within 0.01 mm. Ground physics need no change |
| Budget against B5 | Inside the guide for the skins, control surfaces, tail, cowl, gear and exhausts. Over: `propeller_rotor` 35,811 (guide 12,000–18,000) and `canopy_glass` 6,431 (about 3,000). Under: `engine_face` 13,940 (20,000–30,000) |
| Material extensions | `KHR_materials_clearcoat`, `KHR_materials_specular` |

## Bench (F4U-18 cameras, 1080p, Godot 4.7.2 Compatibility)

Timing run with the machine idle; delivered GLBs (gear stowed) and gear-down exports of each source ([table](checks/bench-g2-timing-1080p.md)):

| | g1.24 | g2.0 |
| --- | ---: | ---: |
| Median frame, eight cameras | 0.94–1.35 ms | 0.93–1.07 ms |
| Measured GPU render | 0.29–0.40 ms | 0.31–0.42 ms |
| Visible + shadow primitives at 1.2–4 m / 40 m / 120 m | 120–157 k / 61 k / 48 k | 172–300 k / 68 k / 55–56 k |
| Load | 0.49–0.53 s | 1.23–1.34 s |
| Video memory | 161 MB | 253 MB |
| Imported scene (`.scn`) | 13.3 MB | 54.6 MB |

The automatic LODs work on g2: at 40 m it draws about as much as g1.

## Visual review

Rendered textured and in uniform grey from the eight F4U-18 cameras, beside g1.24 and R59.

Better than g1:

- The engine's front row, reduction gear and magnetos show through the cowl mouth.
- The cockpit now has a seat, panel, stick and gunsight.
- The intakes have their vanes.
- The main legs carry torque links and retraction links.
- Panel seams and fasteners come from the R59 normal map.
- Silhouettes, the cowl lip and the wing-root fillets are rounder.

Defects:

1. **Propeller paint.** The yellow tips are irregular slivers on one face of each blade, and the blade decals (the circular logo and the stencil marks) are gone. The author's own `previews/nose_close.png` shows the same.
2. **Main wheels plainer than g1.** The tyres are smooth, without grooves, and the rims are simple spoked discs. g1 (since g1.8) has grooved tyres, open rims with bolts, caps and valves: 1,664 triangles per wheel now against 5,752. The new torque links are an improvement.
3. **Shading noise under the normal map.** With the material replaced by plain grey, the fuselage, canopy and cowl show small dents. 23.7 % of neighbouring fuselage triangles meet at more than 10°, against 2.7 % on R59 and 9.2 % on g1.24 ([audit](checks/shading-audit.txt), [glb_shading.py](../../../../research/f4u-corsair/F4U-18/glb_shading.py)). The baked normal map hides most of it; faint blotches remain below the canopy in direct light. The Workshop is not affected: its paint slots change only the albedo of a copy of the material ([aircraft_customization.gd](../../../../app/render/aircraft_customization.gd)).

## What integrating g2 would change

- **Liveries.** The contract requires every livery to be the same airframe ([AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)), so g2 cannot ship beside g1 liveries. g2.0 alone would cut the Corsair's Paint row from five schemes to Naval 308.
- **Package size.** Each livery's imported scene grows from about 13 MB to about 55 MB. F4U-16's four extra schemes took 48.5 MB; on g2 they would take about 200 MB, and eight schemes about 440 MB.
- **No physics change.** Contacts, pivots and the gear rig are identical. Integration follows F4U-15: freeze, manifest, model compile, bindings and generators, then `verify_f4u.gd`, the livery suite and the retract, flap and fold checks in the production scene.

## Evidence

Committed: [preflight of g2.0](checks/preflight-g2_0.json) ([log](checks/preflight-g2_0.log)), [preflight of the twelve g1.24 GLBs](checks/preflight-g1_24.log), [bench table](checks/bench-g2-timing-1080p.md), [shading audit](checks/shading-audit.txt). Screenshots, comparison sheets and the bench GLBs stay outside the repository under `D:\OpenRCsimulator-evidence\f4u-detail-20261024\results\bench-g2-visual\` and `bench-g2-timing-1080p\`. Delivered GLB SHA-256: g2.0 `48d0a8a3…a98a173`, g1.24 default `cf6b0911…6ed4d`.
