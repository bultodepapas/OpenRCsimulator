# F4U Corsair 1/4.5: Blender game-delivery request

2026-10-24 · Revision 4 · To the F4U Corsair model author · Two requests: **A**, a fuselage correction for every delivered livery, and **B**, a new detail tier **g2** derived from master **R59**

**Status 2026-10-24:** revision 4 is delivered. A arrived as g1.24 and is accepted. B arrived as g2.0 and is accepted in substance ([review](research/f4u-corsair/F4U-19/README.md)). **The next delivery, g2.1, is specified in the [g2.1 request](F4U-G2-1-REQUEST.md).** Revision 3 (g1.3) was delivered and accepted on 2026-10-22 ([review](research/f4u-corsair/F4U-04/README.md#g13-accepted-2026-10-22)). Sections 0–13 below remain the base specification; revision 4 states what changes.

## Revision 4: fuselage fix and a g2 detail tier

Thank you for the twelve liveries through g1.21. The owner finds the Corsair too coarse at close range. We tested your R59 master, your game model and your derivation in Godot 4.7.2 ([F4U-18 evidence](research/f4u-corsair/F4U-18/README.md)). Most of the problem is one defect, described in A. The rest calls for a richer tier, g2, described in B. B also explains which parts of the aircraft players actually see, measured on R59, so that triangles go where they show.

### A: `fuselage_core` is inside out (every revision since g1, every livery)

In every delivered GLB, 85 % of the area of `fuselage_core` faces the thrust axis; R59's fuselage skin has 12 % facing inward, in its cavities. Godot culls back faces, so from outside the player sees the far inner wall: a dark box under the canopy, a ridge on the spine, markings mirrored ("INSPECT", "NAVY", "08"). Cycles shades back faces, which is why your renders did not show it. The cause is in `derive.py`: `bmesh.ops.recalc_face_normals` on the open shell merged from six R59 objects chose the inward side. Reversing that mesh's faces alone restores the round fuselage and readable markings ([orientation after the fix](research/f4u-corsair/F4U-18/checks/orientation-g121-fuselage-reversed.json)).

Please deliver the next g1.x revision with only this change:

1. Reverse the faces of `fuselage_core` in `aircraft_game.blend` and in every livery source, in place. Keep vertices, UVs, materials, textures, names, pivots and `GearRetract` unchanged.
2. Check every exterior skin. Measured about the thrust axis, the outward share of `fuselage_core` should be about 0.85. The wing panels, control surfaces and tail measure 0.86–1.00 today; keep them there.
3. Add the check to your verifier and fail on an inside-out skin. Review at least one preview with back-face culling on: Eevee with the material's *Backface Culling*, or the GLB in Godot.
4. Confirm from outside that markings on both sides read correctly. They were painted in 3D, so reversing the faces should be enough.
5. Re-export every livery and update the manifest, metadata and changelog.

Our preflight now rejects an inside-out skin: `python research/f4u-corsair/F4U-04/preflight_glb.py export/aircraft.glb` must pass.

### B: g2, triangles where the player looks

#### B1 Purpose and contract

g2 becomes the Corsair's model in the simulator once accepted; g1 stays as the fallback. It must hold up in the views where the aircraft fills the screen (B2). At flight distances Godot draws lighter versions automatically: it generates LODs when it imports the GLB. Measured on g1.21, they cut the drawn triangles from 60,000 at 4 m to 24,000 at 120 m. Do not deliver LOD meshes.

Everything in sections 3–7 and 9–12 still applies: names, hierarchy, `openrc_section` tags, pivots and their axes, the `GearRetract` carriers and 101 poses (equal to g1 within 0.01 mm and 0.01°), 1:4.5, export at frame 100 with the gear stowed, one GLB per livery. One exception: section 8's budget is replaced by B5. Deliver it as `f4u_corsair/g2_0/` beside g1.

#### B2 How the simulator shows the Corsair

The model is 2.778 m in span; distances below are in model metres.

| View | Distance | Direction and pose | What fills the screen |
| --- | --- | --- | --- |
| Home backdrop | whole aircraft fitted to the screen, about 4 m | fixed three-quarter view, on the ground, gear down | the whole airframe |
| Workshop | orbit; 4 m at 1×, about 1 m at the 4× zoom | any direction, on the ground, gear down, surfaces moved by the player | any part, up close |
| Orbit, in flight | 1.7–56 m, 5.6 m by default | from 20° below to 85° above, any side; gear up or down | any part |
| Close-up | 2.5 m | fixed, behind, left and above | fuselage, canopy, tail, left wing top |
| Chase | 3.9–39 m, 9.7 m by default | behind and about 20° above | top surfaces and tail |
| Pilot | 20–300 m from the ground, zoom up to 8× | mostly from below and from the side | silhouette and underside |
| Crash | about 8 m from the impact | — | separated sections and their closure faces |

The rig moves too. The player folds the wings on the ground (112°, F4U-17). Flaps go to 50°, the other surfaces to ±25–35°, and the gear retracts in flight. Each pose exposes faces that the neutral pose hides.

#### B3 The rule: triangle density follows screen size at the closest view

At 1.5 m, the closest regular view, a 1080p screen with a 45° field of view shows **0.87 pixels per millimetre of the model**. The Workshop zoom reaches about 1 m, where this becomes 1.3 px/mm; the textures carry that last step. From this:

- **Geometry only for relief of about 3 mm or more on the model** (13 mm full size), which is 2–3 px. Rivets (about 1 mm), panel seams, fastener heads, rib tapes, stencils and small steps belong in the normal map and ambient occlusion (B7).
- **Round sections need enough sides** so the outline stays within half a pixel of the true circle at 1.5 m:

  | Radius on the model | On screen at 1.5 m | Sides per full turn |
  | ---: | ---: | ---: |
  | 2 mm (wire, hose, brake line) | 1.7 px | 6 |
  | 5 mm (pushrod, small tube, pitot) | 4.3 px | 7 |
  | 10 mm (oleo, exhaust stub) | 8.7 px | 10 |
  | 20 mm (hub, link boss) | 17 px | 14 |
  | 39 mm (tail tyre) | 34 px | 19 |
  | 94 mm (main tyre) | 82 px | 29 |
  | 167–170 mm (fuselage, cowl) | 145–148 px | 38–39 |

  Apply the same rule to rounded edges: a leading edge, wingtip or cowl lip needs the sides that its radius calls for over the arc it turns through. More sides than this are invisible; fewer show facets on the outline.
- **Flat or gently curved areas get large triangles.** Add vertices only for the silhouette, real curvature, hinge lines, section boundaries and panel edges that carry a paint or UV seam.
- **Faces that no camera sees get no triangles.**

The GPU handles triangles cheaply. The costs are separate objects, file size and memory. 450,000 triangles in 53 meshes cost nothing measurable over g1. R59's 5,616 separate objects cost 15–22 ms per frame, the whole budget of a 60 Hz frame, and R59 as one file is 137–200 MB. Unused triangles also slow the import and weaken the automatic LODs.

#### B4 What R59 actually shows (measured)

We cast rays through the whole R59 aircraft from 1,680 camera positions: 1.5 m from six points (nose, cockpit, left main gear, tail, left wingtip, right wing root) and 4 m from the centre, every 30° around, from below to above. We did this in four poses: on the ground (gear down), in flight (gear up), landing (flaps 50°, every surface deflected) and wings folded. Rays pass through the glazing. One ray stands for 6–7 px of a 1080p frame. The tool is [visibility_r59.py](../research/f4u-corsair/F4U-18/visibility_r59.py).

- **2,340 of R59's 5,616 visible objects, 597,544 triangles, were never hit by any ray in any pose.** The largest groups are the engine internals (151,704), the wing mechanisms R10 (147,392), the cowl-flap mechanics R14 (94,948), the joint cylinders R59 (90,600) and hidden cockpit parts (27,520). Leave them out.
- **Other parts are seen only as a sliver.** The cowl-flap mechanics behind the closed flaps hold 413,568 triangles in all, the 94,948 above included, and never cover more than 3,487 px. Leave all of them out.
- **Some parts are huge in R59 and tiny on screen.** The six exhaust collectors hold 1,237,232 triangles but never cover more than 1,068 px in any view: only their stub exits show through the cowl.
- **Some parts fill the screen.** The fuselage reaches 2.0 million px (the whole frame), each outer wing panel about 1 million, each flap up to 0.5 million. They deserve their full R59 density.
- **Some "mechanism" collections are visible exterior trim.** These are the fold-joint end ribs (R53), the flush hinge covers (R55/R56), the balance tabs (R10), the flap upper lips (R57), the cowl flaps (R14) and the gun-port plates (R26). They are visible in every pose. Merge them into the skin they sit on. The folded pose adds little beyond them.

In the table, *largest view* is the most screen pixels the part covers in one 1080p view. The *density ceiling* sums, over the part's objects, one triangle per 10 px of each object's largest view, doubled because no single view shows a whole part, and caps each object at its R59 count. It is an upper bound, not a target. g2 aims at about 30 % of it. The complete per-object list (475 objects of 1,000 triangles or more, with the g1 part each one went to) is [r59-visibility.csv](research/f4u-corsair/F4U-18/checks/r59-visibility.csv). Use it to choose sources: an object with zero rays hit is out.

#### B5 Budget per part

**Target 300,000–350,000 triangles, ceiling 450,000. At most 70 mesh × material surfaces, 16 materials and 30 MB per livery GLB.**

| Part | R59 triangles | Never seen | Largest view (px) | Density ceiling | g1 | g2 guide |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `fuselage_core` | 71,608 | 0 | 2,036,531 | 59,060 | 8,000 | 30,000–45,000 |
| `cowl` with closed cowl flaps | 76,416 | 0 | 271,462 | 62,740 | 5,000 | 25,000–35,000 |
| `wing_center_fixed`, with intake ducts and well roofs | 219,258 | 0 | 409,950 | 149,900 | 11,599 | 45,000–65,000 |
| `wing_left_fixed`, `wing_right_fixed`, each | 44,664–46,966 | 0 | 869,118–1,067,175 | 43,839–44,426 | 5,200 | 20,000–28,000 |
| ailerons, each | 20,934–26,980 | 0 | 148,781–227,475 | 18,260–22,182 | 1,700 | 5,000–7,000 |
| flaps, each of six | 11,842–11,870 | 0 | 185,737–509,850 | 11,842–11,870 | 1,100 | 3,000–5,000 |
| stabilizer, elevator, fin, rudder, together | 150,848 | 0 | 215,268 | 126,847 | 8,400 | 30,000–45,000 |
| `propeller_rotor`: hub and dome (the F4U-1D blades are hidden in R59 and were not measured) | 1,002,128 | 0 | 181,012 | 42,254 | 5,400 | 12,000–18,000 |
| `engine_face`: what the cowl mouth shows | 474,532 | 151,704 | 55,012 | 48,260 | 4,000 | 20,000–30,000 |
| `exhaust_stacks` | 1,237,232 | 0 | 1,068 | 560 | 1,600 | 1,500–3,000 |
| cockpit, windshield, canopy frame (glass not measured) | 366,304 | 27,520 | 22,725 | 36,827 | 5,300 | 15,000–22,000 |
| gear: three legs, doors, wheels | 331,074 | 23,408 | 159,075 | 182,287 | ≈ 30,000 | 40,000–55,000 |
| wing details: intake vanes, gun ports, lamps, pitot | 225,364 | 19,220 | 27,281 | 32,380 | — | 10,000–18,000 |
| exterior trim: fold-joint ribs, hinge covers, balance tabs, flap lips, rib tapes | 671,434 | 275,340 | 104,512 | 98,077 | — | 6,000–12,000 |
| fuselage seams and fasteners (R13) | 72,980 | 0 | 84,768 | 8,787 | — | normal map; at most 3,000 |
| cowl-flap mechanics behind the closed flaps (R14) | 413,568 | 94,948 | 3,487 | 4,435 | — | none |
| antenna and small parts | 4,708 | 1,028 | 1,800 | 538 | 140 | 500–1,500 |

The guides sum to about 300,000 at the low end and 450,000 at the high end. The rows cover all 5,658,774 visible R59 triangles except R59's four-blade reference propeller (130,620). Rays pass through glass, so the canopy and windshield glass are not measured; give them about 3,000 triangles for a clean silhouette.

Where to spend and where to save, part by part:

- **Fuselage:** keep R59's density at the canopy and windshield junction, the cowl join, the wing-root fillets and the tail cone. The flat flanks can lose most of their vertices. Seams R13 (72,980 triangles, all under 1 px of relief) become normal map.
- **Cowl:** the lip, the cowl-flap trailing edges and the front ring need 39 sides per turn. The inside of the cowl ring needs only the depth visible through the mouth.
- **Wing centre:** the gull bend, the root fillets and the intake mouths carry the shape. Keep the wheel wells and their roofs: from below, with the gear down, each roof covers up to 82,237 px. Model them simply, without internal ribs.
- **Outer panels:** spend on the leading edge, the tip, the fold joint and the aileron cove. The upper and lower surfaces between them can be coarse.
- **Ailerons, flaps and tail surfaces:** the hinge gaps and coves show when deflected. Keep the trailing edges sharp; the flat panels need few triangles.
- **Propeller:** blade outlines, root cuffs and the hub silhouette. R59's hub has 946,448 triangles only because of its Subdivision; it never covers more than 181,012 px. Rebuild it from the base mesh, at about 6,000 triangles.
- **Engine:** only what the cowl mouth shows within 60° of the nose: the front row's heads and barrels, pushrod tubes, the ignition ring, the reduction gear case and the magnetos. A cooling fin is about 1 px thick at 1.5 m. Model the finned block with a few grooves, or put the fins in the normal map, never one by one. No ray reached most of the rear row or the accessories: 151,704 engine triangles were never hit.
- **Exhausts:** only the stub exits, 1,500–3,000 triangles in total, against R59's 1,237,232.
- **Cockpit:** seen through the glazing from above and the side at 1.5–2.5 m: seat, panel face, stick, gunsight, console tops and harness. Leave out what lies under the floor, behind the panel or below the sills.
- **Gear:** everything shows with the gear down at 1.5 m: oleo, torque links, retraction strut, brake line, wheels, both faces of each door and the well liners. Keep each part rigid on the existing carriers. Doors need 2,000–4,000 triangles each; tyres take the sides in B3.
- **Wing details:** the intake lips with their vanes (R20; the honeycomb as texture), the gun-port plates (R26), the lamps and the pitot.
- **Exterior trim:** merge the fold-joint ribs, hinge covers, balance tabs and flap lips into the skin they sit on, with the same density rules. The fold mechanism inside the joint is not needed.

#### B6 Method

1. **Start from R59.** Select the source objects for each part, leaving out those the CSV lists with zero rays hit, and delete the faces no camera can reach (inner faces, faces against another part).
2. **Reduce part by part. Do not use one global collapse Decimate.** g1 kept 4–14 % of each skin that way, and the result was irregular triangles and, at higher ratios, dark patches near the left wing root. Use limited dissolve and planar reduction on flat areas, remove edge loops along flat spans, and retopologize the hub, engine and gear by hand. Leave Subdivision off.
3. **Keep these exact:** silhouettes, hinge lines, section boundaries, closure faces, wheel contacts, and the landmarks and pivots (within 0.1 mm).
4. **Merge to stay within 70 surfaces.** Use one mesh per section and moving part, and share materials. Never keep R59's object split.
5. **Normals:** every skin faces outward (A). Shade smooth, with sharp edges only on real creases (trailing edges, panel steps). Weighted normals are fine.
6. **Measure the result.** Report the deviation from R59 for each main skin (maximum and 95th percentile, in mm), and overlay silhouettes from the front, side and top.

#### B7 Surface detail, UVs and liveries

**Bake detail into textures.** Bake a tangent-space normal map and ambient occlusion from R59 onto the g2 UVs: panel seams (R13), fasteners, rivets, access panels, rib tapes and engine fins. All liveries share them.

**Keep UV islands large.** On the unreduced F4U-18 meshes, Godot's automatic LOD still drew 94 % of the triangles at 120 m. The cause is not isolated; many small Smart UV islands are a likely contributor.

**Re-target the liveries.** The new topology needs a new shared `UVMap`. Make each livery look the same as on g1: rerun your paint scripts on the new layout, or bake each g1 texture onto g2 (*Selected to Active*). Deliver the default (Naval 308) first. The owner chooses the others; the simulator offers at most eight per aircraft.

#### B8 Verification and delivery

1. Run your verifier with the B5 budgets and the winding check from A.
2. `python research/f4u-corsair/F4U-04/preflight_glb.py export/aircraft.glb --profile f4u-g2` must pass.
3. Include the deviation report (B6) and a preview sheet with back-face culling on, from the B2 views: the Home three-quarter view, the orbit at 1.7 m around the nose, cockpit, main gear and tail, the chase view, and a view from below. Show the gear down and up, the flaps at 50° and the wings folded.
4. Our acceptance is our preflight, the model contract (`verify_f4u.gd`) and a side-by-side render against g1 in our bench ([F4U-18](research/f4u-corsair/F4U-18/README.md#bench)).

#### B9 Review of g2.0 and what g2.1 changes

Reviewed 2026-10-24 ([F4U-19](research/f4u-corsair/F4U-19/README.md)). A is accepted as g1.24 and B is accepted in substance as g2.0. Everything the author must change for the next delivery is in the [g2.1 request](F4U-G2-1-REQUEST.md).

## 0 Review of g1.2 and what g1.3 changes

**Revision 3 (2026-10-22, fulfilled):** g1.2 is accepted in substance; [section 0](#0-review-of-g12-and-what-g13-changes) lists the review and the two changes for g1.3: the owner moved the model to **1:4.5**, and `aircraft.glb` must be exported with the gear **stowed** (`GearRetract` frame 100), as revision 2 already asked. Sections 1, 2, 3, 4, 12 and 13 are updated for the new scale.

Reviewed 2026-10-22 from `f4u_corsair/g1_2/`: all 79 manifest SHA-256 values match; your verifier passes; our independent GLB preflight passes every structural rule; Godot 4.7.2 imports the GLB with 81 uniquely named nodes, every required pivot and gear helper, and `openrc_section` extras on all 44 meshes. The geometry, section split, closure work, door refinement, upper fold covers and the three liveries are what we hoped for. Thank you.

| Item | g1.2 | g1.3 |
| --- | --- | --- |
| Scale | 1:5, span 2.499993 m | **1:4.5, span 2.778 m.** On 2026-10-22 the owner chose a bigger model: the CARF-Models-class 1:4.5 Corsair with a Moki radial |
| Gear in `aircraft.glb` | Down: lowest vertex `gear_wheel_left` at −0.478 m (GLB up), 0.267 m below the lowest wing vertex | **Stowed, exactly `GearRetract` frame 100** (section 7, item 2). Our importer binds every carrier at the stowed sample and refuses another pose |
| Everything else | Accepted | Unchanged: names, hierarchy, sections, pivots, the action's frames and carriers, materials, UVs, liveries, budgets, documentation |

**Suggested method: scale g1.2, do not re-derive from R59.** Scale the finished g1.2 game scene uniformly by **10/9** (= (1/4.5) / (1/5)) about D0: mesh data, pivot and carrier locations, every location key of `GearRetract`, and the helper empties. Apply it to the data, never as an object scale, so exported node scales stay (1, 1, 1). Rotations, angles, rest orientations, UVs and textures do not change. A uniform scale preserves every clearance and contact result you already verified; only lengths grow by 10/9 (for example the 0.35 mm door bevels become 0.39 mm). Then:

1. Update `metadata.json`: `scale_factor` 0.2222222 (1/4.5); landmarks, pivots, wheel centres, contacts, radii, oleo travel, span, length and propeller diameter × 10/9; the new GLB hash.
2. Update the verifier's span rule from 2.500 m to **2.778 m** (12.5 m / 4.5; tolerance 0.01 m) and its gear check to compare the GLB with frame 100.
3. Export `aircraft.glb` with `GearRetract` at frame 100, still without animation, cameras or lights.
4. Re-run your verifier, round trip, clearance and motion witnesses; regenerate previews, `verification.json`, the manifest and the README figures; add a g1.3 changelog entry. The previous revisions stay as they are.

Expected g1.3 figures: span 2.7778 m, length 2.3811 m, propeller 0.9003 m, tyre diameters 0.1880 m (main) and 0.0778 m (tail), wheel track 0.8622 m, main wheel contact −0.5307 m below the thrust axis with the gear down. Our preflight now checks both changes: with g1.2 it reports `gear reaches 0.267 m below the lowest airframe vertex` and `span 2.5000 m differs from 2.7778 m`.

Thank you for R59. It is an exceptional master: gull wing, folding panels, sequenced retracts, cowl flaps, cockpit and engine are carefully built and documented. OpenRC Simulator cannot fly it directly, however. It is a full-size studio scene with millions of triangles, driver-based rigs and no game export. Please prepare a lightweight, editable **game version** at RC scale, as specified below. Keep R59 intact as the detailed master; this delivery is export preparation, simplification and separation into usable parts, not a rebuild.

This letter is self-contained. Repository links at the end are supporting evidence only.

## 1 What we found in R59

Reviewed 2026-10-21 with Blender 5.2.2 LTS (`d13f752e3b9c`), headless, scripts auto-run disabled. Source: `F4U_Corsair_R59_Blender_completo.zip` SHA-256 `e498cafc3bcffb8e215e7fbc06088c7e83c49085ffaa1018a9d51ee1425176cf`; `F4U_Corsair_R59.blend` SHA-256 `94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3`. Measurements were taken in memory after posing the rig neutral (root at identity, demo actions unassigned, controls zero, wings spread and locked, gear down, stores off); the file was not saved.

| Item | R59 as delivered | Needed for g1 |
| --- | --- | --- |
| Scale | Full size: 12.500 m span, 10.718 m spinner tip to tail cone | 1:4.5, uniform: 2.778 m span |
| Frame | Root frame +X aft, +Y right, +Z up; origin near the ground plane, thrust axis at Z ≈ 2.420 m | Section 4 frame, root at D0 |
| Triangles | ≈5.66 M in 5,616 visible aircraft meshes, plus ≈0.63 M in studio, audit and store collections | 60,000–100,000 target, 150,000 ceiling |
| Heaviest parts | Propeller hub 946,448 (Subdivision); six exhaust manifolds 1.25 M; engine detail 1.71 M; cowl flaps 0.42 M; cockpit 0.38 M; wing mechanisms 0.32 M | Section 8 budgets |
| Scene content | 8,725 objects: 198 cameras, 17 lights, audit/diagnostic collections R31–R42, R51, R58 Zebra layers, superseded variants | One `EXPORT_aircraft` collection with the aircraft only |
| Materials | 160 materials (104 used by visible meshes), ≈5,800 mesh × material surfaces, 20 emission materials | ≤24 materials, ≤60 surfaces target |
| Images | 19 packed images. The 4096 × 3072 paint maps are each packed three times (`.006`, `.008`). Plan scans `F4U1D_RC_plano.png` and `Corsair_R11_plano_1.png` are packed | 2048 atlases, no duplicates, no plan scans or reference photos |
| Rig | 1,806 drivers on 938 objects (774 drive visibility), 132 constraints, custom-property controls on the root and seven control empties, three demo actions | Static pivots with local +X axes; one `GearRetract` action |
| Saved pose | Root pitched 14.49° (the root also stores 15.36°); elevators 18°, rudder 12°, trims −5°, cowl flaps 22°; demo actions assigned | Neutral, root identity |
| Names | 5,493 visible meshes contain ` \| `, 144 contain non-ASCII characters, 1,350 end in `.NNN` | ASCII, unique, no automatic suffixes |
| Crash tags | No `openrc_section` properties | Every exported mesh and pivot tagged |
| Other geometry | 622 visible curve objects (cables, hoses); the retract hose deforms during the cycle | Mesh only; rigid parts only |
| UVs | 4,869 visible meshes have no UV map | UVs on every painted exterior part |
| Variant | F4U-1D airframe without chin scoop, but the active propeller is the F4U-4 four-blade 13 ft 2 in reference; the three-blade set is hidden in `05A` | One stated variant (section 6) |
| Finish | Reno Racer "57" with an interpreted SOHIO logo | Original liveries (section 9) |

Neutral landmarks in the R59 root frame (full size, metres): spinner tip (−5.568, 0, 2.420); wingtips y = ±6.250; wing fold joint y = ±2.64; inner-panel leading edge minimum x = −2.923; rudder trailing edge x = 4.494; tail-cone end x = 5.150; main tyres 0.846 m diameter centred at (−2.650, ±1.940, 0.455); tailwheel 0.350 m centred at (3.430, 0, 1.770); propeller diameter 4.0132 m. The model is 5.5 % longer than the published F4U-1D length of 10.16 m while the span matches. Please check the nose and tail endpoints against your references and record the result; do not rescale nonuniformly to hide the difference.

## 2 Owner decisions for g1

- **Scale 1:4.5** (revision 3; g1 and g1.2 were 1:5). Apply one uniform factor of 1/4.5 to the full-size master, or 10/9 to g1.2 (section 0). Expected values: span 2.778 m, length ≈2.381 m, propeller ≈0.900 m, main tyres ≈0.188 m, wheel track ≈0.862 m.
- **Retractable gear.** Deliver both main legs and the tailwheel as a sampled retraction (section 7).
- **Several liveries.** At least three original paint schemes on one shared UV layout (section 9).
- **Clean configuration.** No external stores, rockets, pylons, folding mechanism, parking struts or diagnostic content in the game file.

## 3 What to deliver

```text
f4u_corsair/g1_3/
  README.md                       Blender version, how to open and re-export, frame, changes from R59
  CHANGELOG.md
  LICENSE.txt                     authorship and asset terms (section 11)
  source/aircraft_game.blend      opens to the assembled neutral aircraft
  source/scripts/                 derivation, export and verifier scripts
  export/aircraft.glb             neutral runtime asset (default livery)
  export/aircraft_demo.glb        articulation and retraction reference only (optional)
  textures/liveries/<id>/         one folder per livery (section 9)
  metadata.json
  export-map.json
  verification.json
  previews/                       front, side, top, underside, three-quarter, control extremes,
                                  gear up/transit/down, exploded sections, each livery
```

1. **`source/aircraft_game.blend`** opens directly to the assembled, neutral aircraft in a framed three-quarter view. Parts are named and easy to select. It contains no drivers, constraints, linked libraries or missing caches, and includes a short text block with the export command, frame convention and node names.
2. **`export/aircraft.glb`** contains the same neutral aircraft with the gear stowed (section 7), its pivots, materials and section tags. This is the file Godot imports.
3. **Derivation.** Preferably, a script in `source/scripts/` derives the game file from R59, so a later master revision can be re-derived. A documented manual derivation is acceptable; the game `.blend` then becomes the editable source for later revisions. Re-exporting the GLB from the game `.blend` must not require R59.

Use Blender 5.2.2 LTS and its bundled glTF exporter; do not migrate to a newer build for this delivery. The target is Godot 4.7.2 with the Compatibility renderer.

## 4 Scale, frame, datum and neutral pose

Use metres. Left and right always refer to the pilot looking forward.

| Frame | Right | Up | Nose direction |
| --- | --- | --- | --- |
| R59 root frame | +Y | +Z | −X |
| g1 Blender export scene | +X | +Z | +Y |
| GLB and Godot model | +X | +Y | −Z |

From R59 to the export scene, with D0 measured in the R59 root frame: `export = (1/4.5) × (r59.y, −(r59.x − D0.x), r59.z − D0.z)`. This is a proper rotation about Z plus uniform scale, without reflection. The Y-up glTF export then applies `godot = (blender.x, blender.z, −blender.y)` once.

**D0** is the symmetry plane × wing-root leading-edge station × thrust-axis height. Our estimate is x ≈ −2.923, z ≈ 2.420 in the R59 root frame; please measure it on the actual root section and record it. D0 is not the CG. The export root has zero translation and rotation and unit scale.

Apply the 1/4.5 factor to mesh data and pivot locations, never as an object scale. Exported node scales are exactly (1, 1, 1), without reflection or shear.

**Neutral pose:** root identity (no ground attitude baked in); all controls and trims 0, including the left aileron trim tab, elevator and rudder trims and both balance tabs; flaps 0; cowl flaps closed; wings spread and locked, fold hardware hidden; canopy closed; zero oleo compression; tailhook stowed; stores and empty pylons removed; propeller at a recorded blade angle with zero visual pitch offset. The gear pose is set by `GearRetract`: frame 0 (down and locked) for landmarks and clearance checks, frame 100 (stowed) for the GLB export.

Record export-frame coordinates for: both wingtips, spinner tip, rudder trailing edge, tail-cone end, wing-root leading edge, propeller hub, every wheel centre and ground contact point with the gear down, nav and landing light lenses and the exhaust stack exits. Include wheel radii, propeller diameter, hinge lines and thrust-axis direction. Measure transformed mesh vertices, not rotated bounding boxes.

## 5 Parts, crash sections and hierarchy

A moving part and a crash section serve different purposes. An aileron rotates on its own in flight but leaves with its wing in a crash. Set the string custom property **`openrc_section`** on every exported mesh and pivot, and export Custom Properties so it reaches glTF node `extras`. A collection or material name is not enough.

Supported values: `core`, `wing_left`, `wing_right`, `wing_center`, `horizontal_tail`, `vertical_tail`, `engine`, `propeller`, `gear`, `canopy`. R59 already separates the outer wing panels at the fold joint, so use it: the inverted-gull inner panels are `wing_center`, and each outer panel from the fold joint outward is `wing_left` or `wing_right`.

```text
F4UCorsair                          identity root at D0, untagged
  fuselage_core                     [core]          fuselage, windshield, cockpit interior, antenna, stowed tailhook
  canopy_glass                      [canopy]        sliding canopy glazing, closed
  canopy_frame                      [canopy]
  wing_center_fixed                 [wing_center]   both inner gull panels, root intakes, wheel-well liners
  wing_left_fixed                   [wing_left]     outer panel, tip, nav lens, landing lamp if outboard
  wing_right_fixed                  [wing_right]
  stabilizer_fixed                  [horizontal_tail]
  fin_fixed                         [vertical_tail]
  cowl                              [engine]        cowl, closed cowl flaps, engine face, exhaust stacks
  aileron_left_hinge                [wing_left]
    aileron_left                    [wing_left]     includes trim and balance tabs at neutral
  aileron_right_hinge               [wing_right]
    aileron_right                   [wing_right]
  flap_left_1_hinge                 [wing_center]
    flap_left_1                     [wing_center]
  flap_left_2_hinge                 [wing_center]
    flap_left_2                     [wing_center]
  flap_left_3_hinge                 [wing_left]
    flap_left_3                     [wing_left]
  flap_right_1_hinge … flap_right_3 (mirror, sections wing_center / wing_center / wing_right)
  elevator_hinge                    [horizontal_tail]  one common axis
    elevator                        [horizontal_tail]  both halves and horn
  rudder_hinge                      [vertical_tail]
    rudder                          [vertical_tail]    includes trim tab at neutral
  thrust_frame                      untagged; fixed shaft orientation
    propeller_spin                  [propeller]
      propeller_rotor               [propeller]     blades, spinner, hub
  gear nodes                        [gear]          section 7
```

Keep different sections as sibling branches. Never parent the rotor under `cowl`: the crash collector takes a detachable section's whole subtree. Never weld across a section boundary. Keep horns, paint, lamps and small details with their own part; for example, the left nav lens leaves with the left outer panel. Several meshes may share a section; merge pieces only when motion, section and material all permit it.

Add simple closure faces at the fold joints, wing roots, tail attachments and cowl cut where separation would otherwise reveal an empty shell. Assign each to the piece it closes, keep a small hidden gap to avoid coplanar flicker, and keep them concealed when assembled. No ribs, splinters or pre-broken debris are needed.

Node names above are the requested g1 names. Keep them unique and ASCII, with no `.001` suffixes. The Godot adapter supplies the public `airplane` root and `propeller` wrapper; do not add competing wrappers.

## 6 Articulation

Each pivot rotates about its **local +X axis**, with angle zero at its saved rest orientation: `rest × rotation_about_local_X(angle)`. Keep the actual hinge line, dihedral and shaft tilt; do not reset a correctly tilted pivot to make the transform panel read zero. The three flaps per side may have different hinge lines; each gets its own pivot, and the simulator drives all three from one flap command per side.

| Articulation | Positive direction in the delivered asset | Check range |
| --- | --- | --- |
| Ailerons | Trailing edge down | R59 ±18°; check clearance to ±25° |
| Elevator | Trailing edge down | Check to ±25° |
| Rudder | Trailing edge toward the pilot's right | Check to ±35° |
| Flaps | Trailing edge down | 0–50°; demonstrate 0°, 20°, 40° and 50° |
| Propeller | Clockwise viewed from behind toward the nose | Full revolution about the shaft |
| Wheels | Forward rolling | Full revolution about each axle |
| Tailwheel steering | Same sense as rudder | Neutral and ±30° |

These ranges are geometric clearance cases; the simulator's throws come from its aircraft data. Report the clearance envelope; do not silently clamp a surface to hide an intersection. Cowl flaps, canopy, tailhook, wing fold and trim tabs stay fixed at neutral in g1.

**Variant.** The airframe follows the F4U-1D (no chin scoop), but the active propeller is the F4U-4 four-blade reference. State which variant g1 represents. We suggest the F4U-1D three-blade propeller you already preserved in `05A`, unless the owner prefers the four-blade.

## 7 Retractable gear

The simulator replays a **sampled** retraction. It interpolates rigid carrier transforms between gear-up and gear-down; the Ventage Jet uses the same route. Please provide:

1. One action named **`GearRetract`** in the game `.blend`: frame 0 = down and locked, frame 100 = fully up with doors closed, with progress uniform in frame. Include the 86° aft fold, the 90° wheel twist and the door sequence. Extension reverses the same path.
2. **Export `aircraft.glb` at frame 100.** The simulator binds every imported carrier at the fully stowed sample and refuses a mismatch, so stowed carriers in the GLB must equal frame 100 exactly. The game `.blend` may open at frame 0 for editing; the export command sets frame 100 first.
3. **Rigid carriers only.** Every moving gear part follows an object whose transform the action animates: location and rotation, unit scale. Bake drivers and constraints into the action. Replace the deforming hose with rigid segments or omit it.
4. Per wheel (`left`, `right`, `tail`), helper nodes that are correct when deployed:
   - `gear_compression_<role>`: slides along the strut axis and carries the lower oleo, axle and wheel.
   - `gear_spin_<role>`: local +X is the axle.
   - `gear_wheel_<role>`: tyre and hub mesh.
   - Tailwheel only, `gear_steer_tail`: local +Y is the steering axis, between the tail carrier and the compression node.
5. Record the authored oleo travel and the tyre radii. Doors and links that are hidden when the gear is down may be omitted from the down pose only if the action still shows them correctly.

Name carriers `gear_*`, tag them `gear`, and keep the gear subtree outside every other section. Keep the carrier count reasonable, roughly 20 or fewer.

## 8 Detail and rendering budget

This section is the g1 budget. For g2, [revision 4, B3–B5](#b3-the-rule-triangle-density-follows-screen-size-at-the-closest-view) replaces it.

The model is seen from 5 to 150 m. Protect the gull-wing outline, airfoil thickness, rounded tips, tail outlines, cowl profile, canopy profile, propeller silhouette and wheel size. Simplify hidden structure, fasteners, bevels, tubes and mechanisms first. Prefer controlled retessellation or local simplification to a global decimation that moves hinge boundaries or ruins shading.

| Group | Guide budget (triangles) |
| --- | --- |
| Fuselage, wings, tail and control surfaces | ≈40,000 |
| Propeller with spinner and hub | ≤6,000 |
| Engine face seen through the cowl (front cylinder row and gearbox only) | ≤8,000 |
| Exhaust stacks | ≤2,000 |
| Cockpit (seat, panel, stick, gunsight) plus one closed canopy glass shell | ≤8,000 |
| Gear, doors and wheels, all three legs | ≤20,000 |

Aim for 60,000–100,000 in total. 150,000 is a ceiling, not a target. Omit the engine's rear row, harnesses and mounts, internal ribs, flap actuators, hinge hardware, wing-fold mechanism, intake honeycomb geometry (use a texture or simple recess), stores and every diagnostic object. A pilot figure is not required.

## 9 Materials, UVs and liveries

Use exportable Principled materials; bake procedural appearance. Share material datablocks. Aim for **24 or fewer materials and 60 or fewer mesh × material surfaces**; report the actual count and the reason if section separation exceeds it. Keep glass to the glazing, avoid overlapping transparent shells, and enable backface culling on closed opaque shells. Verify normals, winding, smooth shading and assignments after export. Use geometry only for real relief; paint and markings belong in textures, not stacked decal shells.

**Paint regions.** Split the painted skin into separate materials so the simulator's solid-paint slots can target them: `paint_body` (fuselage and cowl), `paint_wing` (wing panels, flaps, ailerons), `paint_wing_tip`, `paint_tail` (stabilizer, fin, elevator, rudder). All regions sample the active livery's texture.

**Liveries.** Deliver at least three original schemes. Suggestions for owner review: an overall glossy dark blue, a wartime-style three-tone blue and white, and a red and ivory air-racer style with a fictional number. Mark one as the default.

- One shared, non-overlapping UV layout (`UVMap`) on every painted exterior part, identical for all liveries.
- Per livery, in `textures/liveries/<id>/`: a 2048 × 2048 sRGB base-colour atlas, an optional shared roughness/metal map, the editable layered source, and markings as separate alpha PNG layers.
- The GLB embeds only the default livery. Record each livery's `id`, name and description in `metadata.json`.
- Optionally place two empties, `marking_fuselage_left` and `marking_fuselage_right`, where a short registration of up to 12 characters fits: local +Z out of the skin, +X along the reading direction.

No real sponsor logos (including SOHIO), no real race number on a racer scheme, no real serials, squadron badges, nose art or copies of an individual photographed aircraft. If national insignia are used, keep them on a separate layer so the owner can turn them off.

## 10 Metadata, verification and package

`metadata.json` records: Blender and exporter versions, export settings, GLB SHA-256, scale factor, D0 in the R59 frame, landmarks (section 4), per-mesh and total triangle and surface counts, material and texture counts, and a `sections` list with each section's nodes. For each articulation record node, parent, member meshes, pivot, axis, local rest transform, positive direction and checked range with units. For the gear, record carriers, helper nodes, action frames, oleo travel and tyre radii.

`export-map.json` accounts for every R59 object exactly once as included, simplified or excluded, with a reason. Pattern or collection rules are acceptable if they resolve to the exact object list.

The verifier (`source/scripts/`) checks the GLB and the game `.blend` and exits nonzero when a mandatory check fails: root identity; unit node scales; ASCII unique names; every mesh and pivot carries a valid `openrc_section`; no detachable ancestor captures another section; all named pivots and gear helpers exist; no cameras, lights, drivers or constraints; `GearRetract` animates only listed carriers; counts within the stated budgets.

Export glTF 2.0 binary, Y-up, selected collection `EXPORT_aircraft` only, with Custom Properties enabled (`export_extras=True`). Disable cameras, lights and animation in `aircraft.glb`. Do not add compression extensions or material features that Godot 4.7.2 does not import. Pack all runtime images into the GLB; keep paths in the `.blend` relative or packed.

## 11 Rights and provenance

- `LICENSE.txt` states authorship. The model is the project's own work and needs no licence ([owner decision F4U-13](DECISIONS.md), 2026-10-23).
- List every reference used for R59 and g1: the Royal RC F4U-1D plan, the CARF Corsair manual, photographs, museum and archive sources. Say which were only consulted and which were traced or digitized.
- Remove packed plan scans and reference photographs from the game `.blend` and GLB. They may stay in the master.
- All paint and textures in g1 are original or carry their own compatible licence and attribution.

No mass, CG, inertia or strength data are required. The simulator team chooses the physical RC hardware reference and derives the flight data. Geometry volume and material names must not be presented as mass data.

## 12 Acceptance checklist

- [ ] A clean machine opens `aircraft_game.blend` and re-exports the GLB with the documented command, without R59 or missing files.
- [ ] A clean Blender scene re-imports `aircraft.glb` at 2.778 m span with the same hierarchy, materials and neutral pose, gear stowed exactly at `GearRetract` frame 100.
- [ ] Orthographic views of R59 (scaled 1/4.5) and g1.3 match in silhouette; markings stay readable in flight views.
- [ ] Root identity, metres, D0, left/right and axis conversion are correct; metadata and exported pivots and landmarks agree within 0.1 mm and 0.01°.
- [ ] Every control and gear pivot exists with the expected parent and moves its own meshes, including horns and markings.
- [ ] Positive and negative witness poses and the clearance sweep pass, and returning to zero restores neutral.
- [ ] `GearRetract` frames 0, 50 and 100 show down, transit and up with doors correct and no rigid part deforming.
- [ ] Every exported mesh and pivot carries a valid `openrc_section`; the exploded preview shows complete sections and closure faces with nothing left floating.
- [ ] Triangle, surface, material and texture counts are reported; no studio content, stores or duplicate aircraft reach the GLB.
- [ ] Each livery renders on the same UVs; the default is embedded; markings follow section 9.
- [ ] The verifier rejects a deliberately removed hinge and a missing or invalid section tag in disposable copies, with a nonzero exit.
- [ ] The package carries a revision, changelog, licence, source mapping, tool versions and GLB hash. R59 bytes are unchanged.

## 13 What we do after delivery

We will import g1.3 with Godot 4.7.2, verify `extras`, poses and landmarks, bind the controls, sample `GearRetract` into the retractable-gear rig, and check crash separation of each wing panel, tail, cowl, canopy, propeller and gear. The RC hardware reference is the CARF-Models F4U-1D 1:4.5 class with a Moki S250 radial; we derive the flight data through our own generator and add paint-slot and livery bindings. None of that requires changes to the Godot application from you.

## Supporting references

- [Blender aircraft delivery specification](BLENDER-AIRCRAFT-HANDOFF.md): the general authoring contract this request adapts.
- [Model and package contract](AIRCRAFT_CONTRACT.md#model-and-package-contract): imported-model construction, retraction rig and `gltf_extras` crash sections.
- [Ventage Jet asset guide](../assets/aircraft/avanti-s-a200/README.md): the sampled-retraction precedent.
- [Aircraft Workshop](AIRCRAFT-WORKSHOP.md): current paint slots and registration markings.
- [Aircraft licensing guide](AIRCRAFT-LICENSING.md): Corsair row.
- R59 review scripts: [inspect_blend.py](../research/f4u-corsair/F4U-00/inspect_blend.py) and [measure_neutral.py](../research/f4u-corsair/F4U-00/measure_neutral.py).
