# F4U-19: review of request revision 4 (g1.24 and g2.0)

Reviewed 2026-10-24 for the [F4U plan](../../../F4U-PLAN.md). The author delivered both parts of [request revision 4](../../../F4U-BLENDER-HANDOFF.md#revision-4-fuselage-fix-and-a-g2-detail-tier): **A** as g1.24 (`F4U_Corsair_g1_24_Revision4A.zip`) and **B** as g2.0 (`F4U_Corsair_g2_0_Revision4B`). Both were only read. Nothing is frozen into the repository or the app yet.

## Verdict

| Part | Delivery | Verdict |
| --- | --- | --- |
| A, fuselage winding | g1.24, twelve liveries | **Accepted.** All twelve GLBs pass the preflight, including the skin-orientation rule (`fuselage_core` outward 0.831). In the default GLB, `fuselage_core` is the only mesh that differs from the shipped g1.13 (positions, normals, UVs and index sets compared). |
| B, g2 detail tier | g2.0, Naval 308 only | **Accepted in substance; three corrections requested for g2.1** ([g2.1 request](../../../F4U-G2-1-REQUEST.md)). The rig, contacts and budget fit the contract and the frame cost is unchanged. The propeller paint and the main wheels are worse than g1. |
| g2.1 request, F1–F4 and I1 | g2.1, Naval 308 only | **Accepted and integrated (2026-10-24, [below](#integration-of-g21-2026-10-24)).** F1–F4 are done and nothing else changed. One small follow-up remains: the new blade material lost its normal map. I1 (optional) is not met. [Review below](#g21-review-2026-10-24). |

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

## g2.1 review (2026-10-24)

The author delivered `F4U_Corsair_g2_1` for the [g2.1 request](../../../F4U-G2-1-REQUEST.md). Package: 145/145 files match `SHA256SUMS.txt` and the ZIP matches its `.sha256`. GLB SHA-256 `cf4cdad6…fda945b3`.

| Item | Result |
| --- | --- |
| Preflight, `--profile f4u-g2` | PASS without warnings: 337,664 triangles, 57 surfaces, 14 materials, six images, span 2.7778 m, `fuselage_core` outward 0.815 ([report](checks/preflight-g2_1.json)) |
| Scope | All 82 nodes keep their parents, sections and rest transforms exactly (difference 0.0). 41 of 46 meshes have the same geometry as g2.0. Only `propeller_rotor`, `canopy_glass` and the three wheels changed |
| F1 blade paint | Done. One textured material (`naval_blade_paint`, g1.24's 1024 × 256 image) with a clean tip band on both faces and the logo and stencil marks back. The 1,712 blade triangles are unchanged from g2.0. **Regression:** the material lost g2.0's normal map (R59 bake on UV0, scale 0.65), and its roughness fell from 0.72 to 0.37. Faceted diagonal streaks now show on the blades at 1.6 m |
| F2 wheels | Done. `gear_wheel_left/right/tail` are geometrically identical to g1.24 (5,752, 5,752 and 3,320 triangles) with the g1 gear atlas; g2's torque and retraction links stay. Contacts are unchanged |
| F3 budget | Done. `propeller_rotor` 35,811 → 16,473 (only the hub was reduced, from 34,099 to 14,761, with the same bounds) and `canopy_glass` 6,431 → 3,427. The optional `engine_face` increase was not made (13,940) |
| F4 one AO texture | Done. The separate `ao` image is gone; occlusion reads the ORM's red channel. Six images remain: normal, ORM and base colour, plus the gear atlas (two maps) and the blade image requested by F1–F2 |
| I1 shading dents | Not met (optional). Neighbouring triangles above 10°: `fuselage_core` 23.7 %, `canopy_glass` 13.1 % (from 26.1 %), `cowl` 22.9 % ([audit](checks/shading-audit-g2_1.txt)). The author found no safe reprojection |
| Bench, 1080p, idle machine | Median frame 0.98–1.29 ms against g2.0's 0.98–1.18 and g1.24's 0.99–1.18 ms. Draw calls are down to g1's 117. Load 1.25 s; video memory 247 MB ([table](checks/bench-g2_1-timing-1080p.md)) |

Visual review, from the F4U-18 cameras beside g1.24 and g2.0:

- The blade tips and decals now match g1, and the wheels are g1's again, with g2's links.
- The rest is unchanged from g2.0.
- The only new defect is the blade streaking.

The fix for the author is small: keep the normal map on UV0 at scale 0.65 in `naval_blade_paint`, beside the base colour on UV1, and check the roughness.

## Integration of g2.1 (2026-10-24)

On the owner's decision ([DECISIONS](../../../DECISIONS.md), F4U-19), the simulator flies g2.1 with Naval 308 as its only paint. The owner is adapting all twelve g1 schemes to g2.

| Step | Change |
| --- | --- |
| Freeze | `assets/source-deliveries/f4u-corsair-g2-1/`: 75 files, 55 MB. The texture folder and preview images (71 files) are omitted; their author hashes are in [source-manifest.json](../../../../assets/aircraft/f4u-corsair-250/source-manifest.json), visual revision `g2.1-cf4cdad638da`. g1.13 and g1.3 stay frozen as evidence |
| Generators | `manifest.py` reads the author's `manifest.json`. `sample_gear.py` reproduces the 17 carriers and 101 poses (largest change 2 × 10⁻⁸). `compile_model.py` declares no liveries for a one-paint delivery; rests and the rig are unchanged within 1.1 × 10⁻⁷. `install_liveries.py` removed g1.13's four runtime livery GLBs. `liveries_path` is gone from the Corsair's entry in `model-bindings.json`. Physics, costing, propeller and ground effect are current without regeneration |
| Shared outputs | `build_models.py` regenerated the six model manifests: the other five change only in the `model-bindings.json` hash. `build_descriptors.py` regenerated nine descriptors, each changing one manifest hash. `build_customization.py` changed hashes only |
| Tests | `verify_f4u.gd` pins the g2.1 hash and counts (46 meshes, 57 surfaces, 337,664 triangles). With no shipped multi-paint aircraft, `test_aircraft_liveries.gd` runs the livery contract and on-use checks on a synthetic five-entry manifest and checks the Corsair as a one-paint aircraft; the full set returns with the g2 schemes. `test_ui_home_rebuild.gd` selects the Corsair's second scheme when one exists. `test_preflight_glb.py` takes its inside-out fixture from the frozen g1.13 and requires the shipped g2.1 to pass `f4u-g2` |

Verification on Windows, Godot 4.7.2:

| Check | Result |
| --- | --- |
| Generators in `--check` mode | `manifest.py`, `compile_model.py`, `install_liveries.py`, `derive_physics.py`, `costing_entry.py`, `build_models.py`, `build_descriptors.py`, `build_customization.py` (and its unit tests): all current. `test_preflight_glb.py` 17/17; large-file check passes |
| `verify_f4u.gd` | 33/33 with no engine error: hash and counts, rests, controls, throws inside the clearance envelopes, wing fold, sampled gear, oleo, propeller diameter, exhaust, paint slots, contacts within 0.6 µm of the wheel bottoms, crash sections |
| Suites touching the Corsair or the catalog | 38 of 40 pass through the checked runner ([list](checks/integration-suites.txt)), among them the catalog, liveries 42/42, customization 159, crash energy 225, economy, retracts, gear contacts, flaps, trace metadata 411 and Home. The other two also fail on a clean checkout of `343be4b0b`, the commit before the integration: `test_ui_aircraft_flow` ("Fly shows Preparing flight before building", with the Stik) and `test_retractable_gear_input` (Avanti; every check passes, then the process exits with 0xC0000374) |
| Production flight scene, 1920×1080, OpenGL | Retracts, flaps and smoke: 15/15 ([checks](checks/integration-systems-check.json)). Wing fold with the throttle interlock: 8/8 ([checks](checks/integration-fold-check.json)) |
| Full-scene frame A/B | Same commit, Corsair files at g1.13 (A) or g2.1 (B). Direct route, close-up camera, 1920×1080, VSync on, 45 s per run, alternated A-B-A-B. Median 16.63–16.67 ms against 16.66 ms; p95 17.09–17.16 against 17.09; p99 17.27–17.49 against 17.30–17.34. Both hold 60 fps, and each second run has one hitch near 34 ms ([runs](checks/integration-frames-ab.json)). Other tracks' headless tests ran during the A/B |

Limits:

- The A/B is VSync-bound and shows pacing, not GPU headroom; the isolated bench above measures that.
- `research/f4u-corsair/F4U-16/livery_check.gd` expects five schemes and waits for the g2 liveries.
- Twelve schemes will exceed the contract's limit of eight.

## What integrating g2 would change

- **Liveries.** The contract requires every livery to be the same airframe ([AIRCRAFT_CONTRACT](../../../AIRCRAFT_CONTRACT.md#model-and-package-contract)), so g2 cannot ship beside g1 liveries. g2.0 alone would cut the Corsair's Paint row from five schemes to Naval 308.
- **Package size.** Each livery's imported scene grows from about 13 MB to about 55 MB. F4U-16's four extra schemes took 48.5 MB; on g2 they would take about 200 MB, and eight schemes about 440 MB.
- **No physics change.** Contacts, pivots and the gear rig are identical. Integration follows F4U-15: freeze, manifest, model compile, bindings and generators, then `verify_f4u.gd`, the livery suite and the retract, flap and fold checks in the production scene.

## Evidence

Committed: [preflight of g2.1](checks/preflight-g2_1.json) ([log](checks/preflight-g2_1.log)), [g2.1 shading audit](checks/shading-audit-g2_1.txt), [g2.1 bench table](checks/bench-g2_1-timing-1080p.md), [preflight of g2.0](checks/preflight-g2_0.json) ([log](checks/preflight-g2_0.log)), [preflight of the twelve g1.24 GLBs](checks/preflight-g1_24.log), [bench table](checks/bench-g2-timing-1080p.md), [shading audit](checks/shading-audit.txt). Screenshots, comparison sheets and the bench GLBs stay outside the repository under `D:\OpenRCsimulator-evidence\f4u-detail-20261024\results\bench-g2-visual\` and `bench-g2-timing-1080p\`. Delivered GLB SHA-256: g2.0 `48d0a8a3…a98a173`, g1.24 default `cf6b0911…6ed4d`.
