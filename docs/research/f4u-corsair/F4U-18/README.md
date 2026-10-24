# F4U-18: detail study of the R59 master and the g1 game model

Studied 2026-10-24 for the [F4U plan](../../../F4U-PLAN.md). The owner found the game Corsair too coarse and asked for experiments with the full-detail R59 master, or a request to the author for an intermediate model. Everything here was measured on copies outside the repository; R59 and the author's deliveries were only read.

## Findings

1. **The shipped fuselage is inside out.** In `fuselage_core`, 85 % of the surface area faces the thrust axis instead of away from it. R59's skin has 12 % facing inward, in its cavities ([orientation](checks/orientation-app-g113-default.json), [sections](checks/fuselage-sections.json)). The defect is in all five liveries in `app/assets/aircraft/f4u-corsair-250/` (g1.13) and all twelve g1.21 GLBs. The other exterior parts face outward. Godot culls back faces, so from outside you see the far inner wall of the fuselage. It looks like a dark box under the canopy with a ridge along the spine, and its markings read mirrored ("INSPECT", "NAVY", "08"). Reversing the faces of that one mesh, in memory, restores the round fuselage and readable markings, at the same triangle count and frame time. This defect, more than the triangle budget, is what makes the model look poor in close views.
2. **The cause is the author's derivation.** `derive.py` merges six R59 objects into `fuselage_core`, removes duplicate vertices and runs `bmesh.ops.recalc_face_normals` on the open merged shell. That chose the inward side. The author's views are Cycles renders, which shade back faces, so they hid it. Our preflight and `verify_f4u.gd` check names, sections, poses and counts, not winding ([lesson](../../../LEARNINGS.md)).
3. **g1 is a global collapse decimation, with parts left out.** `derive.py` disables Subdivision and Bevel and applies one Decimate modifier per part, with ratio budget/source. It also takes only a short list of source objects. The [table](#how-g1-was-derived) shows the result: skins kept 4–14 % of their triangles (cowl 6.5 %, inner wing 4.8 %), the propeller 1.7 % and the exhausts 0.1 %. The engine and the gear struts are plain because of the part selection: the engine face takes only nine cylinder heads and the reduction gear (6,200 source triangles), and the gear has no torque links, retraction struts or brake lines. The decimation also leaves irregular triangulation. At ×3 and ×6 budgets it opens dark patches near the left wing root.
4. **R59 as it is cannot ship.** Its 5,616 visible objects (5.66 M triangles, 5,723 surfaces) cost 15–22 ms per frame at 1080p, mostly in 9,000–17,000 reported draw calls, before any scenery is drawn. Other limits remain even when merged per material: the GLB is 137–200 MB, above GitHub's 100 MiB file limit and the 50 MiB repository check; it uses 454–535 MB of video memory and takes 1.3–1.6 s to load. About 2.45 M of its triangles sit mostly hidden inside the cowl and wings: the engine with its exhaust collectors (1.71 M, of which the six collectors are 1.24 M), the cowl-flap mechanics (0.42 M) and the wing mechanisms (0.32 M). The propeller hub's Subdivision adds 0.95 M. The active propeller is the F4U-4 four-blade reference, not the F4U-1D three-blade.
5. **Triangles are cheap; draw calls and size are not.** The same 5.66 M triangles merged into 97 meshes cost 1.0–1.3 ms. The variants at 83 k, 236 k and 450 k triangles all measured 0.8 ms, the same as g1.21 within noise. Godot's automatic mesh LOD works in the Compatibility renderer: g1.21 drops from 60 k visible primitives at 4 m to 24 k at 120 m, and R59 merged from 0.50 M to 0.11 M. It produced almost no reduction on the unreduced `derive_full` meshes (1.74 M at 4 m, 1.64 M at 120 m).

**Recommendation.** (a) The author fixes the fuselage winding in every livery (a g1.x revision), and the verifier and our preflight check winding from now on. (b) Commission a g2 tier of about 250–350 k triangles, with a 450 k ceiling and 70 or fewer surfaces. Build it by controlled reduction per part, not one global collapse. Add the missing visible parts: the engine front row, gear links and intake vanes. Bake panel seams and fasteners from R59 into a normal map. The request is [revision 4 of the delivery request](../../../F4U-BLENDER-HANDOFF.md#revision-4-fuselage-fix-and-a-g2-detail-tier). On this machine the bench shows no frame cost for that budget; slower GPUs are unmeasured.

## R59 composition

Posed neutral as in F4U-00/F4U-06 (gear down, wings spread, stores off). Render-visible aircraft content only ([summary](checks/r59-inventory-summary.json)):

| Collection | Triangles | Objects |
| --- | ---: | ---: |
| 01B Motor, visible details (cylinders, exhaust collectors) | 1,711,764 | 1,492 |
| 05 Hélice (hub 946,448 with Subdivision; four 25,598 blades) | 1,132,748 | 124 |
| 01C engine cooling (cowl flaps and mechanics) | 422,016 | 445 |
| 03 Cabina | 381,956 | 366 |
| 02B wing mechanisms R10 | 316,824 | 1,135 |
| Airframe collections 01, 01B R13 seams, 02 gull wings with flaps and ailerons, 04 tail. Main skins: fuselage 53,660, cowl 67,968, inner gull panels 2 × 40,404 (outer panels 2 × 43,706 are in 02C R51) | 662,334 | 459 |
| Gear (R22, R23, R27–R30) | 394,612 | 721 |
| Everything else (outer wing panels, intakes, gun ports, hinges, joints, antenna) | 636,520 | 874 |
| **Total** | **5,658,774** | **5,616** |

## How g1 was derived

The author's `source/scripts/derive.py`, rerun unchanged except for a budget multiplier ([patch](#reproduce)). At ×1 it reproduces the original g1 (82,925 triangles, 53 surfaces; g1.13 later reached 99,729 with rebuilt wheels and doors). "Source" is the selected R59 objects with Subdivision and Bevel disabled.

| Part | Source | g1 budget | Kept |
| --- | ---: | ---: | ---: |
| `fuselage_core` | 58,144 | 8,000 | 13.8 % |
| `cowl` (with 16 cowl-flap segments) | 76,416 | 5,000 | 6.5 % |
| `wing_center_fixed` | 199,127 | 9,500 | 4.8 % |
| `wing_left_fixed` / `wing_right_fixed` | 46,966 / 44,664 | 5,200 | 11 % |
| ailerons / each flap | 21–27 k / 11.9 k | 1,700 / 1,100 | 6–9 % |
| `stabilizer_fixed`, `elevator`, `fin_fixed`, `rudder` | 39.6 k, 53.7 k, 13.5 k, 43.9 k | 2,500, 2,200, 1,500, 2,200 | 4–11 % |
| `propeller_rotor` | 323,480 | 5,400 | 1.7 % |
| `exhaust_stacks` | 1,237,232 | 1,600 | 0.1 % |
| `cockpit_interior` | 72,456 | 2,200 | 3.0 % |
| main gear doors (each) | 11.5–18.0 k | 650 | 4–6 % |
| `engine_face` (nine heads and the reduction gear) | 6,200 | 4,000 | 65 % |
| gear struts and forks | 124–1,268 | — | not reduced |

## Bench

[bench.gd](../../../../research/f4u-corsair/F4U-18/bench/bench.gd), set up and run by [run_bench.py](../../../../research/f4u-corsair/F4U-18/run_bench.py), renders one GLB alone in Godot 4.7.2: Compatibility renderer, 1920×1080, MSAA 2×, a sky and a sun with the flight scene's 2-split PSSM shadows to 300 m, and a ground plane. It uses the app's Corsair import settings (LODs, shadow meshes, tangents) and vsync off, on an RTX 3090 (driver 617.42) with a Ryzen 9 5900X. Eight fixed cameras run from 1.2 m to 120 m. For each camera the bench takes 90 warm-up frames, then 300 measured frames. Every GLB has the gear down; the derived variants carry the derivation's plain materials. Full results: [table](checks/bench-1080p-1-table.md), [JSON](checks/bench-results.json).

| Model | Triangles | Surfaces | GLB | Video memory | Load | Frame, close views | Frame, 40–120 m |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| g1.21 (Naval 308) | 99,729 | 57 | 9.7 MB | 161 MB | 0.49 s | 0.82–0.85 ms | 0.75–0.78 ms |
| derive ×1 | 82,925 | 53 | 3.3 MB | 90 MB | 0.02 s | 0.80–0.85 ms | 0.74–0.77 ms |
| derive ×3 | 236,241 | 53 | 8.4 MB | 98 MB | 0.03 s | 0.81–0.85 ms | 0.74–0.75 ms |
| derive ×6 | 449,809 | 53 | 15.0 MB | 108 MB | 0.06 s | 0.81–0.85 ms | 0.75–0.76 ms |
| derive, no reduction | 2,507,835 | 53 | 134.5 MB | 263 MB | 0.40 s | 1.20–1.41 ms | 1.12–1.14 ms |
| R59, merged per material | 5,658,772 | 97 | 200.5 MB | 535 MB | 1.31 s | 0.98–1.31 ms | 0.81–0.96 ms |
| R59, as built | 5,658,772 | 5,723 | 136.9 MB | 454 MB | 1.58 s | 15.0–20.0 ms | 17.7–19.5 ms |

Second run with the fuselage faces reversed ([table](checks/bench-1080p-2-fixed-table.md), [orientation after](checks/orientation-g121-fuselage-reversed.json)): g1.21 0.84–0.90 ms, ×3 0.85–0.93 ms, ×6 0.83–0.86 ms. The author's Blender was running during this second run, so its times show the image fix, not a performance result.

Screenshots of every model and camera, textured and in uniform grey, and side-by-side sheets are kept outside the repository under `D:\OpenRCsimulator-evidence\f4u-detail-20261024\results\` with the exported GLBs, logs and derivation sandboxes.

## Reproduce

Blender 5.2.2, R59 SHA-256 `94edd59b…cf4dc3`, the g1.21 delivery's `source/`:

```sh
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-18/inventory_r59.py -- OUT.json
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-18/export_r59_glb.py -- OUT_DIR
# Copy g1.21 source/scripts to <sandbox>/source/scripts, then patch derive.py's specs() with
#   budget = budget * float(os.environ['F4U18_BUDGET_SCALE'])   (0 = no reduction); derive.py writes beside itself.
F4U18_BUDGET_SCALE=3 blender --background --disable-autoexec --factory-startup \
  --python <sandbox>/source/scripts/derive.py -- --master F4U_Corsair_R59.blend
blender -b --factory-startup --disable-autoexec GAME.blend --python research/f4u-corsair/F4U-18/export_game_glb.py -- OUT.glb SCALE [fuselage_core]
python research/f4u-corsair/F4U-18/glb_orientation.py MODEL.glb
blender -b -Y --factory-startup F4U_Corsair_R59.blend --python research/f4u-corsair/F4U-18/fuselage_check.py -- r59 OUT.json
python research/f4u-corsair/F4U-18/run_bench.py --bench <new dir> --out <new dir> --godot <Godot 4.7.2 win64 console> name=MODEL.glb ...
python research/f4u-corsair/F4U-18/make_sheets.py <result dir> name ...
```

`SCALE` is 10/9 for a sandbox derivation (1:5) and 1 for the delivered 1:4.5 sources. Run the bench with nothing else using the CPU or GPU.

## Limits

- The bench measures the model alone, not the flight scene. Scenery, HUD, simulation and the propeller blur are absent, and the app was not run with a changed model: another track was measuring in it at the time. It shows only the model's own cost on this machine; it is not a minimum-hardware claim.
- The exported R59 keeps image textures but loses procedural shader nodes. Its prop is the four-blade reference. The bench compares geometry and draw cost, not final appearance.
- The `fuselage_check.py` cross-sections use a ±6 mm band of vertices. On decimated meshes the band can miss the top or bottom of a section, so its per-station extents are reliable only for R59, ×6 and the unreduced variant. The orientation shares in `glb_orientation.py` do not depend on that band.
- The derived variants repeat the author's global decimation. They bound the cost of a given budget; they are not proposals for its appearance.
