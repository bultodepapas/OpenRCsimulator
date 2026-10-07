# Scenery plan: a living RC club field

Written **2026-10-07**, revision 2 (same day: the layout now follows the owner's reference photo). **Status: proposal. Only SC-00 (this plan) exists. No scenery code, data or assets yet. Next: SC-01, research and art direction.**

- **Step IDs:** `SC-00…SC-24`, gate **Gate SC**.
- **Owns:**
  - code: `app/scenery/`, `app/tests/test_scenery_*.gd`
  - data and runtime assets: `app/data/scenery/`, `app/assets/scenery/`
  - sources and tools: `assets/scenery/` (with `PROVENANCE.json`), `tools/scenery/`
  - research and evidence: `research/scenery/`, `docs/research/scenery-investigations/`, `docs/research/scenery-implementation/<ID>/`
- **Builds on:**
  - [LANDSCAPE-PLAN](LANDSCAPE-PLAN.md): sky, haze, treeline, ground, L10 cue objects, L14 collisions
  - [VISUAL-QUALITY-PLAN](VISUAL-QUALITY-PLAN.md): asset rules (§6.1), contracts (§11), presets (VQ-06)
  - Field-layout sources: [landscape-research](research/landscape-research.md) (AMA, BMFA)
- **Does not touch:** ROADMAP, the physics line (`sim/`, `physics/`), or any other track's plan.

## Why

The field is empty: ground, runway, sky and 480 trees. A real club field is full of life:
- cars parked in the shade, pop-up canopies in the pits, a clubhouse with a flag;
- hay bales in the next meadow, a red barn in a gap in the trees;
- wind turbines turning on the horizon.

All of that makes the place beautiful, and much of it helps the pilot: objects of known size give scale, field edges give perspective lines, and landmarks give orientation ("turn at the barn").

This track is a **separate team working in parallel**. It adds scenery around the landscape track's field without changing that track's steps, files or proofs.

## Reference field: the owner's photo (2026-10-07)

The owner chose an aerial photo of a real club field as the target look (local only: `references/scenery/owner-inspiration-aerial-2026-10-07.png`, SHA-256 `d6a1960c…a4a`, license unknown, never committed). It shows a **compact club where everything sits on one side of the runway**: the pilot's side, the side this plan already reserves for color and buildings.

**What the photo shows, and who builds it:**

| In the photo | Built by |
| --- | --- |
| Two long **open-sided pit shelters** with light metal roofs and benches underneath, one towards each runway end, parallel to the runway | SC-07 |
| A small **white pavilion** with a hipped roof in the middle, behind the fence | SC-08 |
| **5–6 cars parked nose-in** in one row along a tree clump, with a van parked apart near a shed | SC-06 |
| A **fence along the runway** on the pit side, with gaps; pilot stations between them | L10 (landscape track); SC-11 for the other fences |
| **Six black square pads** on the pit-side edge of the runway, at the fence gaps (probably start-up/taxi pads; not confirmed) | Ground surface: requested from the landscape track (L9c) and the physics line (friction). Not scenery |
| An **asphalt runway** with a dashed white centreline and a **yellow X at each end** (meaning not confirmed) | Ground surface: decision O-6 |
| **Post-and-wire boundary fences** across the meadow | SC-11 |
| **Shade-tree clumps** (broadleaf trees and palms) close behind the club, with a small shed among them | Trees within 150 m are L8 (landscape track); SC-08 adds the shed |
| A **dirt access road** along the far boundary | SC-06 |
| Mown stripes in the grass and a darker rough beyond | L9c (already planned) |
| Long tree shadows: low sun | L19 (time of day); SC-05 contact shadows meanwhile |

**Rough proportions** (estimated from one oblique photo, scaled by our 100 m runway; SC-01 replaces them with labeled values):
- Along the runway, scaling is fair: each shelter is about 25–35 m long and the pavilion about 8–12 m wide. The cars' spacing comes out at about 2.6 m, which is a normal parking bay, so the scale is plausible.
- Across the runway, the photo's tilt is unknown, so no distance can be measured. The shelters look about as far behind the fence as the pilot stations are deep, and the car row about twice as far. That is consistent with AMA's zone order (pilots, pits, spectators, parking) but **much closer than BMFA's ≥ 100 m car park**: decision O-7.

## Five rules

1. **The airplane comes first.** Scenery never makes the airplane harder to read. Every step reruns the L6c readability measurement with scenery on, and must stay within the thresholds proposed for Gate L.
2. **Color lives behind the pilot; calm lives in front.** The pilot looks north over the runway. Saturated colors (cars, canopies, signs) go south, behind the safety line, where the airplane never flies (BMFA "dead airspace" over pits and cars). The flight box and the horizon get a muted, natural palette. Landmarks are the one exception, and they are few and narrow.
3. **Visual only, and invisible to the simulation.** Scenery never collides (`collides=false`) until the landscape track's L14 and the physics line's ground contacts support it. Every step proves that `--trace` and the golden flights are byte-identical with scenery on and off.
4. **Off until the owner says yes.** A switch (`--scenery=on|off`, or `OPENRC_SCENERY` for the Home route) defaults to **off**, so every existing capture, golden file and readability baseline stays byte-identical. Gate SC decides whether the default becomes on.
5. **The project's usual discipline.**
   - Every number is `{value, unit, kind, source}`.
   - Placements are generated offline, as integer-quantized positions, from a hash and never an RNG.
   - Animation is driven only by `sim_clock` and `wind_vec`; `TIME` is never used.
   - Every asset needs CC0 or verified license evidence, recorded in `PROVENANCE.json`.
   - Each step is one small change with one proof.

## The field, top-down

Positions are in NED, with the pilot at the origin, north up and the runway centre 15 m north (L5 data). The layout follows the reference photo. The distances are **targets to be derived and labeled in SC-01**; the south-side depths follow the photo's compact layout unless O-7 picks BMFA.

```
 ~2–6 km     church steeple · wind turbines · power pylons            SC-15 (above the L7 hills)
 400–900 m   farmstead (barn, silo, house) in a treeline gap           SC-13; cows and sheep outside the box SC-14
 250–600 m   ════════ treeline ring (L6b) ═══════════════
 ~240 m      hedgerow + post-and-wire fence, flight-box edge            SC-11
 30–220 m    hay meadow: mown rows, round bales, wildflower strips      SC-12, SC-16 (all low: ≤ 1.5 m)
  9–21 m     ═X══ runway 100 × 12 m (L5), surface per O-6 ══X═   ← south edge = safety line (AMA)
             ▪   ▪   ▪   ▪   ▪   ▪   start-up pads at fence gaps (requested surface, O-6)
   0 m       fence with gaps · pilot stations · windsock (L10) · P
 −10…−20 m   [pit shelter W ~30 m]     pavilion      [pit shelter E ~30 m]   SC-07, SC-08
             parked fleet and pit tables under the shelters                  SC-09
 −20…−30 m   spectators on benches in the shade, flower borders              SC-10, SC-17
 −30…−45 m   car row, nose-in, along a shade-tree clump (L8) · van + shed     SC-06, SC-08
 beyond      boundary fence · dirt access road                               SC-11, SC-06
```

The layout sources say:
- **AMA:** flight box 229 m deep beyond the safety line; pits, then spectators, then parking behind the pilot line.
- **BMFA:** pits ≥ 30 m from the take-off and landing path; car park ≥ 100 m away, behind the pits.

## Architecture

| Piece | What it does | Notes |
| --- | --- | --- |
| `app/data/scenery/<field_id>.json`, format `openrc-scenery v1` | Zones, prefab instances (`prefab`, `north`, `east`, `yaw`, `tier`) and generated scatter sets (positions only, with a SHA-256) | A separate file, so the landscape loader (`field_loader.gd`, one treeline object) stays unchanged. The loader checks it against the loaded field |
| `app/scenery/scenery_loader.gd` | Validates the file and returns `{ok, errors, scenery}`, the same pattern as `field_loader.gd` | Rejects unknown prefabs, non-finite values, positions outside the field, anything on the runway, inside the runway-end corridors or in the flight box above its height limit (rules below), overlaps with L6b trees, and `collides=true` |
| `app/scenery/prefabs.gd` + `app/assets/scenery/catalog.json` | One entry per prefab: mesh, real dimensions (with source), triangles, surfaces, tier | Real sizes come from sources (car length from a spec sheet, canopy 3 × 3 m retail standard, round bale 1.2 m). A test checks every mesh against them |
| `app/scenery/scenery.gd` | `build(field, scenery) -> Node3D`. Static props are **merged per zone into one mesh with one shared palette-atlas material**; repeated small items use MultiMesh, grouped by sector | Typically 1 draw call per zone, as L6b showed: the budget is counted in surfaces and passes, not nodes. No `_process` except for SC-18 animation |
| `app/scenery/scenery.gdshader` | Palette atlas, per-instance tint from a position hash, optional sway from `sim_clock`/`wind_vec` | Opaque only. Alpha-to-coverage and alpha hash do nothing in Compatibility 4.7.2 (landscape investigation 04). Contact shadows use alpha blend on flat ground quads |
| The seam (SC-02) | **One line** in `app/render/field.gd`: `if Scenery.enabled(): result.add_child(Scenery.build(field, ...))` | The visual track owns that file, so this one change is agreed with it. Home and flight then share the scenery, as they share the field |
| `tools/scenery/` | `place.py` (integer-only placement, the same idea as `tools/trees/place.py` and L13a), `adapt.mjs` (glTF Transform + Khronos validator; reuses the trees lockfile), `bake_palette.gd`, `capture.sh` | Outputs committed with a SHA-256; a `--check` mode for CI, as in `compile_geometry.py` |

**Height rules (proposed; the figures are borrowed or estimated and must be labeled):**
- Inside the flight box, no prop is taller than 1.5 m (estimated: bales, fences, flowers).
- Around each runway end, an approach surface rising 1:20 (borrowed: ICAO Annex 14 code-1 approach slope; an analogy, not an RC rule).
- Tall landmarks only beyond the treeline.

## Budgets (proposed, to be agreed with the landscape track)

The scenery budget is part of the landscape's own (≤ 300 draw calls, ≤ 1 M primitives, ≤ 15 MB download), not on top of it.

| Measure | Scenery budget | How it is measured |
| --- | --- | --- |
| Visible draw calls, any pilot view | ≤ 40 | `Performance` counters in the Xvfb `opengl3` capture run, scenery on minus off (not headless: those counters read 0) |
| Shadow-pass draws | 0 | Same manifest |
| Primitives | ≤ 150 k | Same |
| Video memory | ≤ +32 MB | `RENDER_VIDEO_MEM_USED` |
| Download | ≤ +8 MB | Export zip delta |
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
| SC-00 | **This plan**, registered in the [track registry](README.md#tracks-plans-and-step-ids) | Review by the owner and the landscape/visual track | — | ✅ 2026-10-07 |
| SC-01 | **Research and art direction.** (a) Turn the [reference photo](#reference-field-the-owners-photo-2026-10-07) into a labeled layout: proportions along the runway from the photo; depths from AMA/BMFA and O-7. Find 5–9 more licensed photos of club fields for details such as shelter construction and pad size (local only if the license is unclear). (b) **Style bake-off:** 3 prop families next to the L6a trees at 20/60/150 m from the pilot's eye. Candidates: Kenney Car Kit + City Kit Suburban + Furniture Kit; KayKit; Quaternius Farm/Animals with CC0 evidence for the exact archive; Poly Pizza CC0 picks. (c) **Technique probe** on a scratch copy: merging per material, a palette atlas, MultiMesh per-instance colour in Compatibility, alpha-blend contact shadows, draw counts | Report in `docs/research/scenery-investigations/`. Contact sheet. A table deciding reuse / adapt / create for each prop class, following the VQ §6.1 procedure. Measured counters | — | Planned |
| SC-02 | **Seam and switch.** Loader, empty `default.json`, `Scenery.build()` returning an empty node, the `enabled()` resolver (CLI, then env, then default off), and the one-line hook in `field.gd` (agreed with the visual track) | Loader tests: a valid file plus ≥ 12 refused mutations. Captures identical with scenery **on and off** (the scenery is empty). Three clean-clone exports contain `data/scenery/default.json` | Visual track agrees to the hook | Planned |
| SC-03 | **Evidence harness.** `tools/scenery/capture.sh` reuses `main.gd`'s existing `--look_az/--look_el/--visual_pose` arguments: 8 horizon views, pits, car park, clubhouse, top-down. Counter deltas between on and off. Budget assertions. Readability run with scenery on | Two runs byte-identical. A copy that breaks the budget fails. The `capture.sh` owned by the visual track is not changed | SC-02 | Planned |
| SC-04 | **Asset pipeline.** Source → validated GLB → normalized to its catalog dimensions → palette atlas → merged mesh. Provenance entry per file | One sample prop: 0 Khronos errors, dimensions within 2 % of the catalog, byte-repeat bake, clean-clone import and export | SC-01 | Planned |
| SC-05 | **Grounding.** A baked contact shadow per prefab, its footprint projected along the fixed sun (the idea behind `render/shadow.gd`), as one alpha-blend ground quad set per zone | A/B capture: props no longer "float" (owner's eye). ≤ 1 draw call per zone. Sun direction taken from `Spec.ATMOSPHERE`, so it is tested equal | SC-04 | Planned |

### Phase SC-B: The club, behind the pilot (no readability risk; this is what the Home backdrop shows)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-06 | **Car row and access road** (photo). 5–8 cars parked nose-in in one row along a tree clump, in 4–5 body types with varied paint; a van or pickup parked apart; a dirt access road along the boundary. The gravel or worn-grass strip under the cars is our own flat mesh until L9c offers a surface type | Dimensions test against the catalog; bay spacing about 2.6 m (from the photo). Distance rules from O-7 checked by the loader. ≤ 6 draws. A capture side by side with the reference photo's framing | SC-03, SC-05 | Planned |
| SC-07 | **Pit shelters** (photo). Two long open-sided shelters, about 25–35 m (estimated), with a light metal roof on posts and bench tables underneath, parallel to the runway towards each end. Under and beside them: pit tables, folding chairs, field boxes, fuel cans, airplane stands, a cooler. Pop-up canopies (3 × 3 m) only as event-day extras | Dimensions test. Distance rules from O-7. ≤ 6 draws for both shelters with their furniture. The roofs' light colour must not clip under ACES (the L3 white check: L\* p99 < 95) | SC-06 | Planned |
| SC-08 | **Central pavilion** (photo). A small white building with a hipped roof, behind the fence midway along the runway, open or half-open, with picnic tables, a club sign and a flagpole with a static flag. Also a small shed among the trees by the van. A BBQ, water tank, portable toilet and bins are optional extras. Reused kit or a kit-bash in a pinned Blender | ≤ 8 k triangles, ≤ 3 draws. White walls pass the L3 clipping check. Postcard capture from the Home camera | SC-06 | Planned |
| SC-09 | **Parked fleet.** Static snapshots of the catalog aircraft on stands in the pits, built read-only through the model teams' public builders and merged per material | ≤ 3 draws per snapshot (the flying Stik costs ~100). Silhouette IoU ≥ 0.98 against the live model at 20 m. The model teams' `verify_*` contracts still pass. No node or hinge renamed | SC-07; model teams informed | Planned |
| SC-10 | **Spectators, static.** 6–10 low-poly people, seated and standing, with benches. Licensing as in VQ §6.1 (people are in the catalog of animation sources) | Each license recorded. Height 1.6–1.9 m checked. ≤ 2 draws | SC-07 | Planned |

### Phase SC-C: The countryside, in front (visible in flight; readability-checked)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-11 | **Field boundaries.** Hedgerows (opaque low-poly), post-and-wire fence and a farm gate on the flight-box edge. Their perspective lines give speed and distance cues | Height rules enforced by the loader. ≤ 4 draws. Standing readability proof | SC-05 | Planned |
| SC-12 | **Hay meadow.** Round bales (1.2 m) along mown rows inside the flight box; a few square-bale stacks | Bale size test. Height ≤ 1.5 m. ≤ 2 draws | SC-11 | Planned |
| SC-13 | **Farmstead landmark.** A red-roofed barn, house, silo and tractor, placed in an existing L6b treeline gap at 400–900 m | Visible in exactly one horizon view, at a distinct azimuth. Loader refuses overlap with L6b positions. Fog fade matches the L2 haze (standard fog, no custom term) | SC-11; gap chosen with the landscape track | Planned |
| SC-14 | **Pasture.** Cows or sheep in a fenced paddock outside the flight box, static poses | Licensing per file. ≤ 2 draws | SC-13 | Planned |
| SC-15 | **Horizon landmarks.** A village with a church steeple (2–3 km), 3–5 wind turbines (4–6 km), a line of power pylons. Silhouettes only, no collision | Each landmark ≤ 1.5° wide from the pilot (estimated limit). Fog-faded. A blinded orientation check: the owner names the direction from a landmark. Coordinated with L7 (which owns the hills); not blocked by it | SC-03; L7 informed | Planned |

### Phase SC-D: Flora

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-16 | **Wildflower meadows.** Patches and strips in the meadow (buttercup yellow, daisy white, clover purple, poppy red along the edges) as tiny opaque meshes. The species colour comes from the position hash. Density is fixed per instance by distance from the pilot, so nothing pops | ≤ 4 draws, ≤ 60 k primitives. Byte-repeat. Same chunking rules as L11a grass, so the two can share the near field | SC-04; L11a contract | Planned |
| SC-17 | **Flower borders and bushes** around the clubhouse, the pilot line and the car park | Counters. Captures. Offered as the delivery of **L11b** if the landscape owner agrees (decision O-2); otherwise L11b stays theirs and SC-17 covers the club area only | SC-08 | Planned |

### Phase SC-E: Life (each step behind its own gate)

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-18 | **Motion from the clocks.** Flags, a wind pump, turbine rotors, canopy flutter and grazing heads move in the vertex shader from `sim_clock` and `wind_vec` (zero until M5). Consumer only | Same sim time gives the same pixels. Pause freezes everything. Every frequency is a multiple of 1/1024 Hz, so the 1024 s wrap is seamless (the L0d rule). Bounds cover the motion (VQ §10) | SC-08, SC-15; L15c contract for flags | Planned |
| SC-19 | **Ambient sound.** Countryside birds and distant voices near the clubhouse; synthesized or CC0 (Freesound CC0) | A unit test on the generated samples, as for `engine_sound.gd`. Pause mutes. Volume follows UI-08 when it exists | Menu track (UI-08) | Planned |
| SC-20 | **Birds** (optional; L19 already lists birds off by default): a small distant flock on a deterministic path from `sim_clock`. Never closer than 150 m and never the airplane's size on screen | Off in every test and capture. Readability unchanged with the flock on | L19 owner agrees | Optional |
| SC-21 | **Animated people** (optional): idle loops for 2–4 spectators | Redistributable license for each animation. A cost table | SC-10 | Optional |

### Phase SC-F: Presentation and variety

| ID | Step | Proof | Depends on | Status |
| --- | --- | --- | --- | --- |
| SC-22 | **Home postcards.** 3–5 fixed Home backdrop compositions (the pits at golden hour… within today's sun), offered to the menu track | Captures in English and Spanish. No second camera or environment left alive in flight (`app_root.gd` contract) | Menu track (UI-06) | Planned |
| SC-23 | **Field themes.** Palette variants of the scenery atlas: green spring, dry Mediterranean summer, autumn. The grass tint is requested from the landscape track | One atlas swap per theme. Readability measured for each theme | SC-16; landscape track for the ground | Planned |
| SC-24 | **Quality tiers.** Each instance is tagged `landmark` (always shown), `standard` or `ornament`, as a deterministic subset, and plugs into the VQ-06 presets | Low keeps every landmark position. Applying the same preset twice changes nothing (idempotent). Traces identical | VQ-06a/b | Planned |
| **Gate SC** | **"Is the field more beautiful and alive, and does flying stay as readable and as fast?"** The owner flies the Gate 2 maneuvers with scenery on. Measured: blinded L6c kit still ≥ 22/24, frame time p95 on the owner's machine, draws, memory, download. The owner decides whether scenery becomes **on by default** | Notes and ratings in this plan; the decision in DECISIONS | SC-06…SC-16 | Open |

**Suggested order:** SC-01 → 02 → 03 → 04 → 06 (proves the pipeline at low risk) → 07 → 08 (the Home postcard: the biggest visible win) → 05 → 11 → 12 → 16 → 13 → 15 → 09 → 10 → 14 → Gate SC. SC-17…24 after the gate, or when their dependencies land.

## Interfaces with other tracks (requests, not edits)

| Track | What we need | What we promise |
| --- | --- | --- |
| Visual quality / landscape | (1) The SC-02 one-line hook in `field.gd`. (2) Our sub-budget inside theirs. (3) **O-1:** L10 keeps the pilot-cue objects (pilot stations, safety fence, windsock, flag pole); the cars and pit tables/canopy listed in L10 move to SC-06/07. (4) **O-2:** L11b delivered by SC-17 or kept. (5) A gravel/parking surface type in L9c, later; for O-6, an asphalt runway look with centreline, end X and start-up pads (no decals until 4.8, so shader or geometry), plus a fence with gaps at the pads in L10. (6) One treeline gap for SC-13. (7) Presets consume the SC-24 tiers | No change to `render/`, the field file, `capture.sh` or their thresholds. Scenery off by default until Gate SC; after that, one agreed re-baseline |
| Physics (main line) | Nothing for scenery. Only if the owner chooses a paved field (O-6): an `asphalt` surface type in `surface_friction.json` | Never reads or writes `sim/`/`physics/`. Proof of identical traces in every step. Any future `collides=true` goes through L14 and the contact work (E3d), never directly |
| Menus (UI) | Home postcards (SC-22); a "Scenery" toggle in preferences (UI-07) after Gate SC; ambient volume (UI-08) | The `app_root.gd` scene-lifecycle contract is respected |
| Model teams | Read-only use of the public builders for the parked fleet | No node, hinge or appearance file touched |
| Crash and damage | Later: scenery collisions as impact causes (after L14) | Prefab dimensions and materials published in the catalog |
| Wind (M5) | `wind_vec` | Consumer only; never invents wind in a shader |

## Ideas parking lot (only through a step and a gate)

Each of these would need its own step and gate first:
- Fun-fly event day: more cars, banners, a food van.
- Dusk flying with warm clubhouse lights (after L19).
- A pond with ducks (the water shader uses `TIME`: needs adapting).
- A combine harvester working the next field, or a distant train, on deterministic `sim_clock` schedules.
- A dog chasing along the fence.
- Another pilot's airplane parked on the runway edge waiting for its turn.
- Seasonal events (autumn leaves, snow).
- The owner's own club, rebuilt from photos (pairs with L17).

## Risks

- **Pretty but harder to fly.** This is mitigated by rules 1 and 2 and by the readability check in every step. If a step fails it, the step tones down before anything is added.
- **Draw-call creep from many small props.** Mitigated by one palette material and merging per zone; we count surfaces and passes.
- **Style clash** between photoreal and low-poly assets. Mitigated by one family chosen in SC-01, with no mixing because of availability.
- **License drift** (Quaternius and Poly Pizza vary per file). Mitigated by evidence for the exact archive (VQ §6.1).
- **Floating props** without engine shadows (L3 kept engine shadows off). Mitigated by SC-05 contact shadows.
- **Ownership collisions** in shared files. Only `field.gd` is touched, once, by agreement. Run `git status` before editing any shared document.

## Open decisions for the owner

| # | Question | Proposal |
| --- | --- | --- |
| O-1 | Who builds the cars and pit furniture listed in L10? | SC (SC-06/07); L10 keeps the flight-cue objects |
| O-2 | Who delivers L11b (bushes and flowers)? | SC-17, if the landscape owner agrees |
| O-3 | Art family | Decided by the SC-01 bake-off; Kenney/KayKit low-poly is the likely fit next to the L6a trees |
| O-4 | Scenery in the Home backdrop before Gate SC? | Yes, behind `OPENRC_SCENERY=on` for previews only |
| O-5 | Field theme to start with | Green temperate (matches today's grass and the photo); Mediterranean summer next |
| O-6 | Paved runway like the photo (asphalt, dashed centreline, yellow end X, start-up pads)? This is ground, not scenery: the look is L9c (landscape track) and the friction is the physics line's `app/data/ground/surface_friction.json`, where dry asphalt is the 1.0 reference (FlightGear) and the runway is grass today | Keep the grass runway in `default.json`. Ask both tracks for an `asphalt` surface type and a second field file (`paved.json`) that copies the photo. Scenery fits either field |
| O-7 | South-side depths: the photo's compact layout (cars about 30–45 m behind the pilot) or BMFA (car park ≥ 100 m)? | The photo for the default field, because it is the owner's reference and follows AMA's zone order. The loader's distance rules become per-field values with their source, not fixed BMFA numbers |
