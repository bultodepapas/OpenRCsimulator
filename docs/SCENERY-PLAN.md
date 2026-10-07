# Scenery plan: a living RC club field

Written **2026-10-07**, revision 4. Revision 2 (same day) made the owner's reference photo the target look; revision 3 folded in four online research reports; revision 4 applies the SC-01 measurements in the real renderer. **Status: proposal. SC-00 and SC-01 are done ([desk research 01–04](research/scenery-investigations/01-prop-asset-sources.md), [probe and bake-off](research/scenery-implementation/SC-01/README.md)); the owner's style choice (O-3) and two Quaternius license files are pending. Next: SC-02 (seam and switch), after the landscape track answers request G-1. No scenery code, data or assets in `app/` yet.**

- **Step IDs:** `SC-00…SC-24`, gate **Gate SC**.
- **Owns:**
  - code: `app/scenery/`, `app/tests/test_scenery_*.gd`
  - data and runtime assets: `app/data/scenery/`, `app/assets/scenery/`
  - sources and tools: `assets/scenery/` (with `PROVENANCE.json`), `tools/scenery/`
  - research and evidence: `research/scenery/`, `docs/research/scenery-investigations/`, `docs/research/scenery-implementation/<ID>/`
- **Builds on:**
  - [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md): sky, haze, treeline, ground, L10 cue objects, L14 collisions
  - [VISUAL-QUALITY-PLAN](VISUAL-QUALITY-PLAN.md): asset rules (§6.1), contracts (§11), presets (VQ-06)
- **Research:**
  - [01 prop asset sources](research/scenery-investigations/01-prop-asset-sources.md)
  - [02 flora, motion, sound, birds](research/scenery-investigations/02-flora-and-ambience.md)
  - [03 field layout rules, markings, structures, photos](research/scenery-investigations/03-rc-field-layout-references.md)
  - [04 Godot techniques and prior art](research/scenery-investigations/04-godot-techniques-and-prior-art.md)
  - [SC-01 probe and bake-off: measured merging, depth, shadows, ground bug, style](research/scenery-implementation/SC-01/README.md)
- **Does not touch:** ROADMAP, the physics line (`sim/`, `physics/`), or any other track's plan.

## Why

The field is empty: ground, runway, sky and 480 trees. A real club field is full of life:
- cars parked in the shade, covered pit rows, a pavilion with a flag;
- hay bales in the next meadow, a red barn in a gap in the trees;
- wind turbines turning on the horizon.

All of that makes the place beautiful, and much of it helps the pilot: objects of known size give scale, field edges give perspective lines, and landmarks give orientation ("turn at the barn").

Other simulators point the same way ([04 §5](research/scenery-investigations/04-godot-techniques-and-prior-art.md#5-prior-art-how-rc-and-fpv-sims-populate-fields)):
- Photo fields win on looks but break moving cameras.
- 3D fields are called "dated" when trees and textures visibly repeat.
- Aerofly sells wind-driven motion: windsocks, flags, turbines.

This track is a **separate team working in parallel**. It adds scenery around the landscape track's field without changing that track's steps, files or proofs.

## Reference field: the owner's photo (2026-10-07)

The owner chose an aerial photo of a real club field as the target look (local only: `references/scenery/owner-inspiration-aerial-2026-10-07.png`, SHA-256 `d6a1960c…a4a`, license unknown, never committed). It shows a **compact club where everything sits on one side of the runway**: the pilot's side, the side this plan reserves for color and buildings.

**What the photo shows, and who builds it:**

| In the photo | Built by | Real-club evidence ([03](research/scenery-investigations/03-rc-field-layout-references.md)) |
| --- | --- | --- |
| Two long **open-sided pit shelters** with light metal roofs and bench tables, one towards each runway end | SC-07 | Covered pit rows 3 × 28 m (Perrine, FL); pole barns 6 × 15 m with a 29-gauge steel roof on 6 × 6 in posts, eaves about 3 m (OTOW, FL) |
| A small **white pavilion** with a hipped roof in the middle | SC-08 | Pavilions 6 × 9 m (Perrine) and 10 × 5 m (Tri-County); hip roof plus steel sheet documented (OTOW) |
| **5–8 cars parked nose-in** along a tree clump; a van apart near a shed | SC-06 | BMFA: "position your car park near some obstacle to flying such as trees or a high hedge" |
| A **fence along the runway** with gaps; pilot stations | L10 (landscape track) | Pilot stations about 1.5 × 1.2 m on concrete, barriers 0.6–0.9 m |
| **Six black square pads** at the fence gaps, about one runway-width square | Ground surface: requested (O-6) | Clubs describe taxi strips and start-up stations; our reading is a hypothesis |
| An **asphalt runway**, dashed white centreline, **yellow X at each end** | Ground surface: O-6 | The X is the FAA closed-runway mark; on RC strips it is read as "not for full-size aircraft" (a forum reading, no RC standard). Florida paved RC runways are 107–183 × 9–18 m; ours (100 × 12 m) is like Triple Creek's 350 × 35 ft |
| **Post-and-wire boundary fences** | SC-11 | A 4 mm wire is 0.3 px wide at 10 m: only the posts read |
| **Shade-tree clumps** (broadleaf, palms) behind the club, a shed | L8 trees (landscape track); SC-08 shed | — |
| A **dirt access road**; mown stripes; low sun | SC-06; L9c; L19 | — |

**Scale check:**
- Along the runway, the photo scaled by our 100 m runway gives shelters of 25–35 m and a pavilion 8–12 m wide. That matches the real clubs above.
- The cars' spacing comes out at about 2.6 m, a normal parking bay, so the scale is plausible.
- Depths across the runway can't be measured (the photo's tilt is unknown). They come from the distance profiles below.

## Five rules

1. **The airplane comes first.** Scenery never makes the airplane harder to read. Every step reruns the L6c readability measurement with scenery on and must stay within the thresholds proposed for Gate L. Busy, sharp backgrounds hurt visibility ([04 §5](research/scenery-investigations/04-godot-techniques-and-prior-art.md#5-prior-art-how-rc-and-fpv-sims-populate-fields)).
2. **Color lives behind the pilot; calm lives in front.** Saturated colors go south, behind the safety line, over BMFA's "dead airspace" (pits, cars and approach: at least 90°, up to 180°). The flight box and the horizon get a muted, natural palette; landmarks are the exception, and they are few and narrow.
3. **Visual only, and invisible to the simulation.** Scenery never collides (`collides=false`) until L14 and the physics line's ground contacts support it. Every step proves that `--trace` and the golden flights are byte-identical with scenery on and off.
4. **Off until the owner says yes.** A switch (`--scenery=on|off`, or `OPENRC_SCENERY` for the Home route) defaults to **off**, so every existing capture, golden file and readability baseline stays byte-identical. Gate SC decides whether the default becomes on.
5. **The project's usual discipline.**
   - Every number is `{value, unit, kind, source}`.
   - Placements are generated offline, as integer-quantized positions, from a hash and never an RNG.
   - Animation is driven only by `sim_clock` and `wind_vec`; `TIME` is never used. Every third-party grass or flower shader checked uses `TIME`: copy none.
   - Every asset needs CC0 or verified license evidence **for the exact file**, recorded in `PROVENANCE.json` with its SHA-256.
   - Each step is one small change with one proof.

## The field, top-down

Positions are in NED, with the pilot at the origin, north up and the runway centre 15 m north (L5 data). The safety line is the runway's south edge, at north = 9 m (AMA). Depths behind the pilot follow the **`photo` profile**; the other profiles are checks.

```
 ~1.5–5 km   church steeple · 3–5 wind turbines · pylons            SC-15 (≤ 5 km, moving parts ≥ 6 m from what they cross: measured)
 400–900 m   farmstead (barn, silo, house) in a treeline gap         SC-13; cows and sheep outside the box SC-14
 250–600 m   ════════ treeline ring (L6b) ═══════════════
 ~240 m      hedgerow + post-and-wire fence, flight-box edge          SC-11 (AMA sport box: 229 m deep)
 30–220 m    hay meadow: bales, uncut flower margins along fences     SC-12, SC-16 (all low: ≤ 1.5 m)
  9–21 m     ═X══ runway 100 × 12 m (L5), surface per O-6 ══X═   ← south edge = safety line
             ▪   ▪   ▪   ▪   ▪   ▪   start-up pads at fence gaps (requested surface, O-6)
   0 m       fence with gaps · pilot stations · windsock (L10) · P   (9 m behind the safety line)
 −15…−22 m   [pit shelter W ~28 × 3–6 m]   pavilion   [pit shelter E]   SC-07, SC-08; fleet SC-09
 −22…−30 m   spectators on benches in the shade, flower borders         SC-10, SC-17
 −30…−45 m   car row, nose-in, along a shade-tree clump (L8) · van, shed SC-06, SC-08
 beyond      boundary fence · dirt access road                          SC-11, SC-06
```

**Distance profiles** (from [03](research/scenery-investigations/03-rc-field-layout-references.md#numbers-for-the-layout), all `manual`; read as minimums behind the safety line). The loader stores the chosen profile per field and checks every placement against it.

| Profile | Pilots | Pits | Spectators | Parking | Source |
| --- | --- | --- | --- | --- | --- |
| `ama-2010-min` | ≥ 7.6 m | ≥ 13.7 m | ≥ 19.8 m | ≥ 24.4 m | AMA 2010, cross-checked with the AMA 2022 table |
| `bmfa` | — | ≥ 30 m from the take-off/landing path | — | ≥ 100 m, "if possible" | BMFA handbook §11.2 |
| `ama-2010-carpark` | — | — | — | ≥ 91 m from the landing strip | AMA 2010, chapter 1 |
| **`photo`** (default) | 9 m | 24–31 m behind (≥ 30 m from the runway centreline) | 31–39 m | 39–54 m | Owner's photo, laid out to satisfy `ama-2010-min` and BMFA's pit rule; labeled `estimated` |

Revision 3 moved the shelters from −10 to **−15 m**. That keeps the photo's look and also meets BMFA's pit rule. Only the car row stays closer than BMFA's and AMA 2010's car-park numbers: decision O-7.

## Art direction and sources

**One family, one palette atlas.** All props are re-coloured into **one shared scenery palette** in the natural, moderate colours of VQ §2, so every zone merges into one material. Sources ([01](research/scenery-investigations/01-prop-asset-sources.md), [02](research/scenery-investigations/02-flora-and-ambience.md)):

| Role | Source | License evidence | Why |
| --- | --- | --- | --- |
| **Primary** | Quaternius "classic" flat-colour packs (2018–2020): Cars, Farm Buildings, Farm Animals, Background Posed Humans | CC0 per pack page; CC0 read inside the archive for Cars (SHA-256 `af8f45d6…`) and Farm Animals; **two license files still blocked** (Farm Buildings, Posed Humans; Drive IDs in [SC-01](research/scenery-implementation/SC-01/README.md#license-evidence)) | Same author as the L6a trees, and the [bake-off](research/scenery-implementation/SC-01/README.md#5-style-bake-off) shows they sit well together. Near-real proportions (car 4.4 × 1.88 m, but 1.23 m tall: about 15 % low, corrected in SC-04). Flat materials with no textures, so they palette-merge. The Poly Pizza pickup has 6,432 triangles (decimate or skip) |
| Small props and flora | Kenney (Survival Kit, Nature Kit, City Kit Suburban fences) | CC0 in every archive checked | Every model has one material. But the cars are toy-shaped (length/width 1.7 against about 2.5 real): no Kenney cars except a van fallback |
| Bush fallback | KayKit Forest | CC0 on the page; archive file not yet read | One gradient atlas; no flowers |
| **Built ourselves** | Pit shelters, pavilion, round and square bales, pit tables, folding chairs, coolers, stands, flagpole and flag, post-and-wire fence, continuous hedgerows, turbines, pylons, church, meadow "flower cushions", bird mesh | Ours | Nothing suitable or fitting exists, and these are simple shapes where real dimensions matter more than detail |
| Rejected | Quaternius MegaKit flowers and bushes (alpha-mask cards of 285–1,690 triangles, "Ghibli" scale); Poly Haven (photoreal style clash); "Poly by Google" uploads (CC-BY 3.0); Sonniss audio (no redistribution) | — | Fails the opaque path, the style or the license |

**License risk:** quaternius.com switched to a new license (QAL v1.0) on 2026-08-28. It forbids redistributing raw assets but "will not apply retroactively". Every Quaternius file therefore enters only with CC0 evidence for its exact archive and SHA-256, as L6a did.

## Architecture

| Piece | What it does | Notes |
| --- | --- | --- |
| `app/data/scenery/<field_id>.json`, format `openrc-scenery v1` | Distance profile, zones, prefab instances (`prefab`, `north`, `east`, `yaw`, `tier`) and generated scatter sets (positions only, with a SHA-256) | A separate file, so the landscape loader (`field_loader.gd`, one treeline object) stays unchanged |
| `app/scenery/scenery_loader.gd` | Validates the file and returns `{ok, errors, scenery}`, the same pattern as `field_loader.gd` | Rejects unknown prefabs, non-finite values, positions outside the field, anything on the runway or in the runway-end corridors, flight-box props above their height limit, profile violations, overlaps with L6b trees, and `collides=true` |
| `app/scenery/prefabs.gd` + `app/assets/scenery/catalog.json` | One entry per prefab: mesh, real dimensions with source, triangles, tier | A test checks every mesh against its catalog dimensions |
| `app/scenery/scenery.gd` | `build(field, scenery) -> Node3D`. **Compatibility has no automatic 3D batching** (measured: 40 cars as separate meshes = 220 draws). Static props are merged at load with **`SurfaceTool.append_from`, one tool per material**, per **spatial cell** (about 30–50 m, estimated): one palette material makes a cell 1 draw (40 cars: 1 draw, pixel-identical). Repeated small items use MultiMesh per chunk | Not `ImporterMesh.merge_importer_meshes`: it relit mirrored parts (3,278 px). Cells, not whole zones: a merged zone can't be culled, and a narrow view then cost 78 draws against 32 (SC-01). Build time ≤ 150 ms (40 cars: 45–50 ms on this VM's CPU) |
| `app/scenery/scenery.gdshader` | Palette atlas, per-instance tint (`set_instance_color`, packed to 16-bit in Compatibility: fine for colour), pivot-based sway and rotors from `sim_clock`/`wind_vec` | Opaque only. Alpha-to-coverage and alpha hash do nothing in Compatibility 4.7.2 |
| The seam (SC-02) | **One line** in `app/render/field.gd`: `if Scenery.enabled(): result.add_child(Scenery.build(field, ...))` | The visual track owns that file, so this change is agreed with it |
| `tools/scenery/` | `adapt.mjs`: the glTF Transform 4.5.0 already pinned in `tools/trees` runs `flatten` → `palette` → `join`, plus the Khronos validator. `place.py`: integer-only placement. `capture.sh`. Blender (pinned) for built-ourselves meshes and for vertex-colour AO | Outputs committed with a SHA-256; a `--check` mode for CI. The adapter checks that every vertex has a colour: once any merged mesh has colours, meshes without them turn **black** |

**Technical rules from the research** ([04](research/scenery-investigations/04-godot-techniques-and-prior-art.md)):
- **Contact shadows:** alpha-blended dark quads, measured within 0.5–7 % of the expected fogged radiance; `blend_mul` is 57–59 % too dark (SC-01).
- **Shadow quad lift:** a fixed **2 cm** held in every tested view up to 100 m camera height and 400 m away (2–5 mm flickered from 100 m). Report 04's "lift ∝ d²" over-lifts 3–15×. It needs a subdivided ground (request G-1); on today's two-triangle ground even a 10 cm lift vanished in some raised views.
- **Ambient occlusion:** baked into vertex colours. No LightmapGI: it renders in Compatibility, but baking needs a Forward+ or Mobile device.
- **Depth precision:** the depth buffer is 24-bit. The formula d²/(near·2²⁴) predicts a 15 m step at 5 km with near 0.1 m, but the measured turbine was clean at 5 km with a 6 m gap; only a 3 m gap flickered (12 % of crossing pixels). Up to 2.5 km even 3 m was clean (SC-01, llvmpipe; re-check on the owner's GPU).
  - Landmarks therefore stay at **≤ 5 km**, with moving parts at least 6 m from what they cross. The 0.1 m near plane stays (O-8 resolved by measurement).
  - Thin or moving parts are geometry, never alpha cards, and at least 1 px wide.
- **Visible size:** at 1280 × 720 and 50° vertical FOV, an object spans about 772/d px per metre at distance d. To show at least 2 px it must be at least d/386 m: 0.26 m at 100 m, 0.57 m at 220 m ([02](research/scenery-investigations/02-flora-and-ambience.md#summary-and-recommendations)). Smaller geometry only sparkles.
- **Animation:** rigid-part pivot animation in the vertex shader. A `Skeleton3D` adds a pass per surface per frame and blocks merging: at most 4 figures, and only after a measurement.

**Height rules (proposed):**
- Inside the flight box, no prop is taller than 1.5 m (estimated).
- Around each runway end, an approach surface rising 1:20 (borrowed: the ICAO Annex 14 code-1 slope; an analogy, not an RC rule).
- Tall landmarks only beyond the treeline.

## Budgets (proposed, to be agreed with the landscape track)

The scenery budget is part of the landscape's own (≤ 300 draw calls, ≤ 1 M primitives, ≤ 15 MB download), not on top of it.

| Measure | Scenery budget | How it is measured |
| --- | --- | --- |
| Visible draw calls, any pilot view | ≤ 40 | `Performance` counters in the Xvfb `opengl3` capture run, scenery on minus off (not headless: those counters read 0) |
| Shadow-pass draws | 0 | Same manifest |
| Primitives | ≤ 150 k | Same |
| Video memory | ≤ +32 MB | `RENDER_VIDEO_MEM_USED` |
| Download | ≤ +8 MB (audio included) | Export zip delta |
| Build time | ≤ +150 ms at field load | Timed in the scenery test |
| Frame time | Judged only on the owner's hardware at Gate SC (L0e logger); llvmpipe numbers are never used for performance | |

## Steps

Each row is one change that keeps `app/test.sh` green. **Every step's proof also includes the standing proof below**, so it is not repeated in the rows.

**Standing proof:**
- `--trace` and the golden flights are byte-identical with scenery on and off.
- With scenery off, all existing captures are byte-identical.
- With scenery on, the L6c readability run stays within the Gate L thresholds proposed in L6c:
  - mean ΔE ≥ 40 in the game view and ≥ 30 in the 50° fixture;
  - ΔE p10 ≥ 8 in every case;
  - nearly-invisible share ≤ 30 %.

### Phase SC-A: Foundations

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-00 | **This plan**, registered in the [track registry](README.md#tracks-plans-and-step-ids) | Review by the owner and the landscape/visual track | — | ✅ 2026-10-07 (rev 3) |
| SC-01 | **Research and art direction.** (a) Layout, distance profiles and structures from rules and real clubs. (b) Sources, licenses and art family. (c) Godot techniques and prior art. (d) Still to do: a **style bake-off render** (the primary family next to the L6a trees at 20/60/150 m), the 3 missing Quaternius license files re-fetched, and a **technique probe** on a scratch copy | (a)–(c): reports [01](research/scenery-investigations/01-prop-asset-sources.md)–[04](research/scenery-investigations/04-godot-techniques-and-prior-art.md). (d) Probe measurements, from report 04: (1) `ImporterMesh` versus `SurfaceTool` build time for one zone; (2) draws per merged zone; (3) a turbine at 2.5 and 5 km with near 0.1 and 0.5 m, flicker measured as a 2-frame diff; (4) the fogged alpha shadow against the ground at 400 m. Plus the contact sheet | — | In progress: (a)–(c) done 2026-10-07 |
| SC-02 | **Seam and switch.** Loader with distance profiles, empty `default.json`, `Scenery.build()` returning an empty node, the `enabled()` resolver (CLI, then env, then default off), and the one-line hook in `field.gd` (agreed with the visual track) | Loader tests: a valid file, ≥ 12 refused mutations, each profile's rules. Captures identical with scenery **on and off** (the scenery is empty). Three clean-clone exports contain `data/scenery/default.json` | Visual track agrees to the hook | Planned |
| SC-03 | **Evidence harness.** `tools/scenery/capture.sh` reuses `main.gd`'s existing `--look_az/--look_el/--visual_pose` arguments: 8 horizon views, pits, car row, pavilion, top-down, and one view framed like the reference photo. Counter deltas between on and off. Budget assertions. Readability run with scenery on | Two runs byte-identical. A copy that breaks the budget fails. The `capture.sh` owned by the visual track is not changed | SC-02 | Planned |
| SC-04 | **Asset pipeline.** Source → validated GLB → `flatten`/`palette`/`join` → normalized to catalog dimensions → scenery palette atlas (sampled at cell centres, mips capped) → merged at load. Provenance entry per file. Vertex-colour AO baked in Blender | One sample prop end to end: 0 Khronos errors, dimensions within 2 %, no vertex without a colour, byte-repeat bake, clean-clone import and export | SC-01 | Planned |
| SC-05 | **Grounding.** Contact shadows as alpha-blend footprint quads projected along the fixed sun (the idea of `render/shadow.gd`), lift ∝ d², one quad set per zone; AO in vertex colours | A/B capture: props no longer "float" (owner's eye). No z-fighting at 40, 180 and 400 m (2-frame diff). ≤ 1 draw per zone. Sun direction from `Spec.ATMOSPHERE`, tested equal | SC-04 | Planned |

### Phase SC-B: The club, behind the pilot (no readability risk; this is what the Home backdrop shows)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-06 | **Car row and access road** (photo). 5–8 cars nose-in along a tree clump (Quaternius Cars, re-coloured to the palette, 4–5 body types), a pickup or van apart, a dirt access road (built by us; Godot Road Generator only as an offline GLB exporter if the curves need it). The gravel or worn-grass strip under the cars is our own flat mesh until L9c offers a surface type | Dimensions test; bay spacing 2.6 m (estimated from the photo). `photo` profile checked by the loader. ≤ 6 draws. Side-by-side capture with the reference-photo framing | SC-03, SC-05 | Planned |
| SC-07 | **Pit shelters** (photo). Two open pole-barn shelters, about 28 × 3–6 m with 3 m eaves, a light steel roof on 6 × 6 in posts (Perrine and OTOW dimensions, `borrowed`), bench tables with model stands and sloped start-up benches 0.48–0.70 m high underneath. Folding chairs, field boxes, fuel cans and coolers are built by us (Kenney Survival Kit for small props) | Dimensions test. `photo` and `bmfa` pit rules pass. ≤ 6 draws for both shelters with their furniture. Light roofs pass the L3 white check (L\* p99 < 95) | SC-06 | Planned |
| SC-08 | **Central pavilion** (photo). A white hip-roof building, about 6 × 9 m (Perrine, `borrowed`), open or half-open, with picnic tables, a club sign and a flagpole with our own flag mesh (static until SC-18). A shed among the trees by the van | ≤ 8 k triangles, ≤ 3 draws. White walls pass the L3 clipping check. Postcard capture from the Home camera | SC-06 | Planned |
| SC-09 | **Parked fleet.** Static snapshots of the catalog aircraft on stands under the shelters: `MeshInstance3D` surfaces collected read-only from the model teams' public builders, merged per material with `ImporterMesh` (dedupe by surface name) | ≤ 3 draws per snapshot (the flying Stik costs about 100). Builders checked for non-uniform scales first (merged normals are only right for uniform scale). Silhouette IoU ≥ 0.98 against the live model at 20 m. The `verify_*` contracts still pass. No node or hinge renamed | SC-07; model teams informed | Planned |
| SC-10 | **Spectators, static.** 6–10 figures from Quaternius Background Posed Humans: looking up, sitting, cheering, waving. Benches | License file for the exact archive (one of the three to re-fetch). Height 1.6–1.9 m. ≤ 2 draws | SC-07 | Planned |

### Phase SC-C: The countryside, in front (visible in flight; readability-checked)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-11 | **Field boundaries.** Our own continuous opaque hedgerow mesh, so no segment repeats visibly; post-and-wire fence (posts plus at most one line: the wire itself is sub-pixel); a Quaternius rail fence for the paddock; a Kenney farm gate | Height rules enforced by the loader. ≤ 4 draws. No visible repetition at 100 m (the "dated" complaint in [04](research/scenery-investigations/04-godot-techniques-and-prior-art.md)) | SC-05 | Planned |
| SC-12 | **Hay meadow.** Our own round bales (1.2 m) and square-bale stacks along mown rows. Uncut flower margins along the fences: the gov.uk hay-meadow rule, no cut before mid-July, keeps an uncut margin | Bale size test. Height ≤ 1.5 m. ≤ 2 draws | SC-11 | Planned |
| SC-13 | **Farmstead landmark.** Quaternius Farm Buildings re-coloured: a red-roofed barn, house, silo and tractor, in an existing L6b treeline gap at 400–900 m | Visible in exactly one horizon view, at a distinct azimuth. Loader refuses overlap with L6b positions. Fog fade from the engine only | SC-11; gap chosen with the landscape track | Planned |
| SC-14 | **Pasture.** Quaternius Farm Animals (CC0 read in the archive), cows or sheep in a fenced paddock outside the flight box, static poses | ≤ 2 draws. Each animal at least d/386 m tall | SC-13 | Planned |
| SC-15 | **Horizon landmarks**, built by us as geometry: a village with a church steeple, 3–5 wind turbines, a line of pylons, all at ≤ 2.5 km (unless O-8). Rotor at least 3 depth steps in front of its tower; blades at least 1 px wide | Each landmark ≤ 1.5° wide from the pilot (estimated limit). No flicker in a 2-frame diff. Fog from the engine. A blinded orientation check: the owner names the direction from a landmark. Coordinated with L7 | SC-03, SC-01 probe; L7 informed | Planned |

### Phase SC-D: Flora

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-16 | **Wildflower meadows.** Our own "flower cushions": flat, low clumps of 6–12 opaque triangles, each at least d/386 m across (0.1–0.6 m), coloured faces on top. One mesh and one surface, one MultiMesh per chunk; the species colour (buttercup yellow, daisy white, clover purple, poppy red) from `set_instance_color` and the position hash. Strips along field edges and fences | ≤ 4 draws, ≤ 60 k primitives. Byte-repeat. No sparkle in a 2-frame diff. Same chunking as L11a grass | SC-04; L11a contract | Planned |
| SC-17 | **Flower borders and bushes** around the pavilion, the pilot line and the car row: Kenney Nature Kit flowers (76–154 triangles) and bushes (16–104), material colours baked to vertex colours, merged to one surface, re-coloured to the palette; KayKit Forest as the fallback | Counters. Captures. Offered as the delivery of **L11b** if the landscape owner agrees (O-2) | SC-08 | Planned |

### Phase SC-E: Life (each step behind its own gate)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-18 | **Motion from the clocks.** Turbine rotors (a slow idle rotation now, wind-driven from M5), flags, a wind pump, canopy flutter and grazing heads move in the vertex shader. Pivots are stored per vertex; the per-instance phase comes from a world-position hash. Amplitude ∝ \|`wind_vec`\| (zero until M5) plus an optional tiny idle term | Same sim time gives the same pixels. Pause freezes everything. Every frequency is a multiple of 1/1024 Hz (the L0d rule). Bounds cover the motion (VQ §10) | SC-08, SC-15; L15c contract for flags | Planned |
| SC-19a | **Synthesized ambience**: a seeded wind bed (filtered noise) and bird chirps (sine sweeps with AM envelopes), pre-rendered once at load into an `AudioStreamWAV`, in testable GDScript like `engine_sound.gd` | A unit test hashes the samples. Pause mutes. No download | — | Planned |
| SC-19b | **Recorded ambience** (optional): 2–4 Freesound recordings (a countryside bed, skylark, blackbird, a distant crowd), each confirmed CC0 on its own page; mono OGG at about 22 kHz with offline loop crossfades | Provenance per file. Volume follows UI-08 when it exists. Fits the download budget | SC-19a; menu track (UI-08) | Optional |
| SC-20 | **Birds** (optional; L19 already lists birds off by default): our own 4–8-triangle "V" mesh with the wing flap in the vertex shader, on an **analytic** path (a closed curve plus per-bird hash offsets; no boids state), **≥ 300 m away**: a 1 m bird at 150 m is as large on screen as the airplane at 225 m | Off in every test and capture. Readability unchanged with the flock on | L19 owner agrees | Optional |
| SC-21 | **Animated people** (optional): idle loops for 2–4 spectators, rigid-part pivot animation first | A cost table; `Skeleton3D` only if measured, ≤ 4 figures | SC-10 | Optional |

### Phase SC-F: Presentation and variety

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-22 | **Home postcards.** 3–5 fixed Home backdrop compositions (the pits, the pavilion, the meadow), offered to the menu track | Captures in English and Spanish. No second camera or environment left alive in flight (`app_root.gd` contract) | Menu track (UI-06) | Planned |
| SC-23 | **Field themes.** Palette variants of the scenery atlas: green spring, dry Mediterranean summer, autumn. The grass tint is requested from the landscape track | One atlas swap per theme. Readability measured for each theme | SC-16; landscape track for the ground | Planned |
| SC-24 | **Quality tiers.** Each instance is tagged `landmark` (always shown), `standard` or `ornament`. A tier change rebuilds the zone mesh deterministically at load; MultiMesh sets use a hash ranking plus `visible_instance_count`. Plugs into the VQ-06 presets | Low keeps every landmark position. Applying the same preset twice changes nothing. Traces identical | VQ-06a/b | Planned |
| **Gate SC** | **"Is the field more beautiful and alive, and does flying stay as readable and as fast?"** The owner flies the Gate 2 maneuvers with scenery on. Measured: blinded L6c kit still ≥ 22/24, frame time p95 on the owner's machine, draws, memory, download. The owner decides whether scenery becomes **on by default** | Notes and ratings in this plan; the decision in DECISIONS | SC-06…SC-16 | Open |

**Suggested order:** finish SC-01 (bake-off and probe) → 02 → 03 → 04 → 06 (proves the pipeline at low risk) → 07 → 08 (the Home postcard: the biggest visible win) → 05 → 11 → 12 → 16 → 13 → 15 → 09 → 10 → 14 → Gate SC. SC-17…24 after the gate, or when their dependencies land.

## Interfaces with other tracks (requests, not edits)

| Track | What we need | What we promise |
| --- | --- | --- |
| Visual quality / landscape | (1) The SC-02 one-line hook in `field.gd`. (2) Our sub-budget inside theirs. (3) **O-1:** L10 keeps the flight cues; the cars and pit furniture move to SC-06/07. For L10's own use, report 03 has pilot-station data: about 1.5 × 1.2 m pads, barriers 0.6–0.9 m, fence gaps at the start-up pads. (4) **O-2:** L11b. (5) A gravel/parking surface type in L9c. (6) For O-6, an asphalt look in L9c: dashed centreline (dash to gap about 1:1 in the photo; the FAA's full-size ratio is 3:2), a yellow X at each end, square pads about one runway-width wide. Shader or geometry: no decals until Godot 4.8. (7) One treeline gap for SC-13. (8) Presets consume the SC-24 tiers. (9) Optionally, the alpha-blend shadow-quad technique from SC-05 | No change to `render/`, the field file, `capture.sh` or their thresholds. Scenery off by default until Gate SC; after that, one agreed re-baseline |
| Physics (main line) | Nothing for scenery. If O-6 picks a paved field: an `asphalt` surface type in `surface_friction.json` (FlightGear's dry asphalt is the 1.0 reference). If O-8 is accepted: pilot-camera `near` ≥ 0.5 m in `Spec.CAMERA` | Never reads or writes `sim/`/`physics/`. Proof of identical traces in every step. Any future `collides=true` goes through L14 and the contact work (E3d), never directly |
| Menus (UI) | Home postcards (SC-22); a "Scenery" toggle in preferences (UI-07) after Gate SC; ambient volume (UI-08) | The `app_root.gd` scene-lifecycle contract is respected |
| Model teams | Read-only use of the public builders for the parked fleet | No node, hinge or appearance file touched |
| Crash and damage | Later: scenery collisions as impact causes (after L14) | Prefab dimensions and materials published in the catalog |
| Wind (M5) | `wind_vec` | Consumer only; never invents wind in a shader |

## Ideas parking lot (only through a step and a gate)

- F3A aerobatic poles (4 m high, 150 m out, at the centre and ±60°) for an aerobatics field theme.
- Fun-fly event day: pop-up canopies (3 × 3 m), more cars, banners, a food van.
- Dusk flying with warm pavilion lights (after L19).
- A pond with ducks (the water shader uses `TIME`: needs adapting).
- A combine harvester working the next field, or a distant train, on deterministic `sim_clock` schedules.
- A dog chasing along the fence.
- Another pilot's airplane waiting on a start-up pad.
- The owner's own club, rebuilt from photos (pairs with L17).

## Risks

- **Pretty but harder to fly.** Rules 1 and 2, the readability check in every step, and the d/386 m visible-size rule. If a step fails, it tones down before anything is added.
- **Draw-call creep.** Compatibility does no 3D batching. One palette material, merging per zone, MultiMesh per chunk; count surfaces and passes.
- **Black vertices after merging** meshes with and without colours. Checked in the SC-04 pipeline.
- **Z-fighting:** landmarks with the 0.1 m near plane, and contact quads with a fixed lift. Handled by the ≤ 2.5 km rule, separation along the view ray, lift ∝ d², and O-8.
- **Visible repetition** ("dated"). Continuous hedgerows, varied body types, hash-varied tints.
- **Style clash.** One primary family, everything re-coloured into one palette; photoreal assets are reference only.
- **License drift** (Quaternius QAL since 2026-08-28; Poly Pizza per model). Evidence for the exact archive, with its SHA-256, before any intake.
- **Ownership collisions.** Only `field.gd` is touched, once, by agreement. Run `git status` before editing any shared document.

## Open decisions for the owner

| # | Question | Proposal |
| --- | --- | --- |
| O-1 | Who builds the cars and pit furniture listed in L10? | SC (SC-06/07); L10 keeps the flight-cue objects |
| O-2 | Who delivers L11b (bushes and flowers)? | SC-17, if the landscape owner agrees |
| O-3 | Art family | The Quaternius classic packs plus our own meshes, in one palette (report 01); confirmed by the SC-01 bake-off render |
| O-4 | Scenery in the Home backdrop before Gate SC? | Yes, behind `OPENRC_SCENERY=on` for previews only |
| O-5 | Field theme to start with | Green temperate (matches today's grass and the photo); Mediterranean summer next |
| O-6 | Paved runway like the photo? This is ground, not scenery: the look is L9c and the friction is the physics line's `surface_friction.json`, where the runway is grass today | Keep grass in `default.json`; ask both tracks for an `asphalt` surface type and a second field file, `paved.json`, that copies the photo. Report 03 supports this: Florida clubs commonly pave 107–183 × 9–18 m |
| O-7 | Car row depth: the photo (39–54 m behind the safety line) or the car-park rules (BMFA 100 m "if possible", AMA 2010 91 m)? | The photo for the default field: it meets AMA's minimums, and BMFA itself advises parking along trees. Profiles are stored per field with their source |
| O-8 | Raise the pilot camera's near plane from 0.1 m to ≥ 0.5 m? It owns depth precision for every distant object. This is the physics line's `Spec.CAMERA`; the chase and inspect cameras may need their own value | Decide after the SC-01 probe measures flicker at both values. Until then, landmarks stay ≤ 2.5 km |
