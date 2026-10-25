# Field people: crew, pilots and spectators

2026-10-24 · Revision 4 · **Active plan** · Step prefix: **SC-HUM** (Scenery subtrack, [registered](../README.md#tracks-plans-and-step-ids)) · Gate: **SC**

**Status (2026-10-24):** all software steps are delivered and verified. The pilots hold the owner's draft transmitter. The owner's part remains.

| Delivered | Evidence |
| --- | --- |
| Head aim for every person; pilots fly the AI companions; crash glance | [SC-HUM-03](../research/scenery-implementation/SC-HUM-03/README.md), [-04](../research/scenery-implementation/SC-HUM-04/README.md), [-05](../research/scenery-implementation/SC-HUM-05/README.md) |
| One mesh and atlas per outfit and pose; six CC0 club members; members preparing models at the pit tables | [SC-HUM-02](../research/scenery-implementation/SC-HUM-02/README.md), [-07](../research/scenery-implementation/SC-HUM-07/README.md), [-06](../research/scenery-implementation/SC-HUM-06/README.md) |
| Shirts in the wind; skin, brows and eyes | [SC-HUM-08](../research/scenery-implementation/SC-HUM-08/README.md) |
| Pilots hold the owner's Radiolink T12D (draft), thumbs on the sticks | [SC-HUM-01](../research/scenery-implementation/SC-HUM-01/README.md) |
| Natural hands and relaxed arms for everyone (relaxed, grip, seated on the thighs), the logo removed from the veteran's T-shirt, readable faces (hat hair, beard colour, eyebrows tinted from the hair, natural irises), varied standing stances (the two pilots included) and a licence audit | [SC-HUM-07-R1…R6](../research/scenery-implementation/SC-HUM-07-R1/README.md) |
| Toolchain reproduction, camera census, scene budget (13 people in 11 draws, all limits pass) | [SC-HUM-00](../research/scenery-implementation/SC-HUM-00/README.md) |

Open:
- **SC-HUM-01:** the final T12D model and its licence. Regenerate the two pilots when it arrives.
- **SC-HUM-09:** the owner's review at Medium Scene detail or above.
- Decisions D3–D10.
- Baseball caps (D9).
- The reference photo board.
- The conditional advanced options SC-HUM-10…13.

**Revision 3** follows an independent Good Enemy review (2026-10-24, read-only, no shared context). The lead verified its main claims against the source:

- The scene budget baseline was stale.
- Most people sit behind the pilot.
- A stateless shader cannot hold per-person head behavior.
- New person placements change collision and companion admission.
- Layer B needs a manual skeleton advance as well as a manual animation advance.
- The step order delayed what the owner asked for.

The plan now delivers the visible parts first in small steps. Skeletons and vertex animation are later, conditional work.

**Owner:** Scenery and field life ([SCENERY-PLAN](../SCENERY-PLAN.md)), which owns today's LU-21 population. Coordination: LU/VQ (scene budget, Scene detail preset), AFC (companion pilots, person airspace exclusions), collision world (person capsules, flight-log identity), CR (crash events), SC-BIRD (shared field-event signal), FW/TOD (lighting).

**Proposed ownership:** `app/scenery/population*.gd|gdshader` (existing), new `app/scenery/crew/`, `app/assets/scenery/population/` (runtime), `assets/scenery/population/` (sources and manifests), `tools/scenery/population/`, `app/tests/test_field_people_*.gd`, evidence in `docs/research/scenery-implementation/SC-HUM-*/`. Shared hooks stay with their owners.

## 1. Goal

Make the people at the club field read as real RC modelers. Improve their models, faces and textures. Pilots should hold real transmitters. Heads should follow the aircraft the way real watchers do. Some club members should sit or kneel in the pits preparing their aircraft. All of this must stay cheap at 1080p, deterministic, and never compete with the aircraft for the pilot's attention.

Source characters, clothing and animation from free, redistributable packs. Do not model or animate by hand what can be downloaded. Procedural motion is limited to head aim, hand IK, cloth flutter and timing.

Non-goals: walking or pathfinding, crowds, lip sync and facial expressions, cloth simulation, voices, a player avatar. Any change to person placements or envelopes is a **collision-world change** (§4.5), not a render-only change.

## 2. Baseline before SC-HUM (LU-21)

This table records the starting point the plan was written against; the status table above links what changed.


| Fact | Where |
| --- | --- |
| 13 people in 3 static poses: 2 pilots on the flight line (north ≈0, east −13 and +16), 5 standing in the pits, 3 seated on benches, 3 on the veranda (north −16.5…−19) | [default.json](../../app/data/scenery/default.json) (`pilots`, `pits-people`, `seated`, `veranda-people`) |
| The pilot looks north into the flight box. Pits, benches and veranda are **behind** the pilot line ([AMA depth bands](../research/scenery-investigations/03-rc-field-layout-references.md)) | same, `zones` |
| MakeHuman CC0 assets posed by Blender 5.2.2 + MPFB 2.0.18 into static glTF meshes (`standing`, `sitting`, `pilot`). The authoring-only GPL tool is not shipped | [generate_people.py](../../tools/scenery/population/generate_people.py), [HUMAN_SOURCES.json](../../assets/scenery/population/HUMAN_SOURCES.json) |
| Each pose GLB has 6–7 mesh parts. Each part is its own MultiMesh with per-instance shirt tint and skin tone. No skeletons, no per-actor callbacks | [population.gd](../../app/scenery/population.gd) |
| Motion is sub-centimeter vertex sway driven by `sim_clock` (k/1024 Hz). `INSTANCE_CUSTOM` = (phase, moving, skin tone, **unused**) | [population_person.gdshader](../../app/scenery/population_person.gdshader), [shader_clock.gd](../../app/render/shader_clock.gd) |
| `wind_vec` reaches every shader but is **zero in scripted runs** | [main.gd](../../app/main.gd) `_render_wind` |
| Render-only motion with state already exists: fixed 1/120 s steps on simulation time, `update_to`/`reset`, no process callback | [windsock_motion.gd](../../app/render/windsock_motion.gd) |
| **Scene budget (current guard):** pilot class max 360 draws / 1,307,000 primitives; High measured 350 / 1,295,621 in the pilot worst view, and "the pilot growth reserve is spent". `scenery_Population` is capped at 54 draws per view class | [scene_budget.json](../../tools/scenery/scene_budget.json), [VQ-06b](../research/visual-quality-implementation/VQ-06b-scene-detail/README.md) |
| LU-21 textures used 23.59 of 32 MiB. One more 1K RGBA8 skin with mips is ≈5.3 MiB, so roughly one new 1K skin fits | [LU-21](../research/landscape-upgrade/LU-21/README.md#measured-budgets) |
| Every `person_*` placement creates a person collision proxy. Companion admission refuses circuits within a **30 m exclusion** of any person or shelter proxy. The collision world belongs to the flight-log identity | [collision_world.gd](../../app/scenery/collision_world.gd), [airspace.gd](../../app/ai/companions/airspace.gd), [AI-FLIGHT-COMPANIONS](../AI-FLIGHT-COMPANIONS.md) |
| Companion aircraft (1–3 Ugly Stiks, off by default) have **no pilot figures**; their `render()` exposes the interpolated pose and commands | [agent.gd](../../app/ai/companions/agent.gd) |
| Pits contain 13 parked aircraft on tables (0.90 m), foam stands and grass bays | [SC-09-R1](../research/scenery-implementation/SC-09-R1/README.md) |
| Characters cast no engine shadows. Custom projected shadows use cached CPU instance transforms | [field_projected_shadows.gd](../../app/render/field_projected_shadows.gd) |

Hard constraints: Godot 4.7.2 **Compatibility** (OpenGL 3.3, no compute, no screen-space SSS), shaders never read `TIME`, captures repeat byte for byte, pause/reset/replay follow simulation time, and the [display priorities](../../AGENTS.md#display-resolution-priorities) apply. Scene budget numbers are measured at the 1280×720 qualification viewport; draws and primitives are resolution-independent gates. Frame time is judged at 1080p on the owner's machine.

## 3. Who sees whom

From the pilot station looking into the flight box, only the two **flight-line pilots** are regularly in frame, when the aircraft is along the runway. The pits, benches and veranda are behind the pilot. Pits and spectator work is seen in the chase, orbit and ground cameras, Home postcards, the trailer and taxiing on the ground.

At the default 50° vertical FOV, `px ≈ 1158 · size / d` (same law as [the birds plan](birds-sky-life.md#3-how-big-a-bird-is-on-screen-1080p-first)):

| Subject | Size | Distance | px 1080p | px 1440p | px 2160p |
| --- | --- | --- | --- | --- | --- |
| Flight-line pilot, body | 1.75 m | 13–16 m from pilot | 127–156 | 169–208 | 254–312 |
| Same pilot, head | 0.23 m | 13–16 m | 17–20 | 22–27 | 33–41 |
| Transmitter width (TX16S class, F3) | 0.287 m | 13 m | 26 | 34 | 51 |
| Transmitter stick | 0.02 m | 13 m | 1.8 | 2.4 | 3.6 |
| Any person's head in a chase/orbit view | 0.23 m | 5–40 m from that camera | 7–53 | 9–71 | 13–107 |

**Measured (SC-HUM-00 camera census, 2026-10-24):** over a reference sortie the pilot view shows the flight-line pilots 19 % of the time with heads of 32 px median (52 px max) because the auto zoom narrows the view near the runway; pits members, workers and spectators appear in the pilot view at most 1 % of the time, and in the chase, orbit and close-up views at 2–4 px median ([census](../research/scenery-implementation/SC-HUM-00/README.md#camera-census-2026-10-24)).

Consequences:

1. **The flight-line pilots and the owner's transmitters come first.** They are the people the player sees while flying.
2. Silhouette, posture, head direction and motion carry realism at these sizes (H8). Eyes are invisible, so the head carries slightly more of each gaze shift than a real head does (H1).
3. Pits and spectator detail is sized against the cameras that actually show it. SC-HUM-00 measures this instead of assuming it.
4. Caps and sunglasses are common at real RC fields. They also hide the weakest part of a game face (H7).

## 4. Behavior design

### 4.1 Head tracking

Two modes, from gaze research:

- **Coupled (pilots, spotters):** the head stays locked to the aircraft direction, as batters' heads rotate with the ball (H2). Aim at a predicted point `p + v·τ` with τ 0.1–0.3 s [est] (H3).
- **Step-and-hold (everyone else):** the head holds still while the target stays inside a dead zone of 10–20° [est] (H1). Beyond it, the head turns, follows with a critically damped lag of 0.25–0.4 s [est], and holds again once it settles.

Step-and-hold needs memory, so **each person's head is a small CPU state**, advanced in fixed 1/120 s steps of simulation time with `update_to`/`reset`, as in [windsock_motion.gd](../../app/render/windsock_motion.gd). Pause holds the state; reset and replay rebuild it exactly.

Shared rules:

- **Distribution:** neck ~35 %, head ~65 % [est] on the MultiMesh. A chest share (10–15 %, H10) exists only on skinned actors. Feet and hips never turn.
- **Limits:** yaw ±70°, pitch −15°…+50° [est]. Rotate yaw first, then pitch (H4). A rear gate returns the head to rest instead of snapping across (H10).
- **Per-person variation:** seeded "head mover" factor (H1), dead zone, lag, limits and rest offset. Heads must not move in sync; the acceptance test compares head-yaw time series across people.

### 4.2 Attention

Keep it small: each person gets a seeded interest level and a role focus. Distance, low height and a **crash** are the only interrupts. A low pass draws nearly every head at a real field, so crowd contagion (H6) is deferred; it is optional polish after the owner review.

| Role | Default focus | Interrupts |
| --- | --- | --- |
| Flight-line pilot (companion) | Their own aircraft, coupled | None |
| Flight-line pilot (no companion) | Per D4 | Low player pass, crash |
| Spotter (optional, F1; collision change) | Same aircraft as its pilot | Crash |
| Seated spectator | Player aircraft within range, else rest | Low pass, crash |
| Veranda pair | Each other | Low pass, crash |
| Pits member | Their aircraft on the table | Low pass over the pits, crash |

Crash and low-pass events come from one shared **field-event signal**, also usable by the birds plan's startle model. Schedules derive from `hash(seed, floor(sim_clock / period))`, never from random-number state.

### 4.3 Idle life

- **No lockstep:** per-person rhythm scale 0.85–1.15 [est] on every loop (H9).
- **Role pools and scheduled variations** (look around, stretch, sip, adjust cap) on skinned or vertex-animated actors only (H9).
- **Blinks** only on close skinned actors without sunglasses: 12–26 per minute (H5), from CC0 face units (A1).
- **Cloth flutter** from `wind_vec`, masked so shoulders and collars stay pinned (E11). Verify it in a wind-enabled interactive or bridge-driven run, because scripted runs force wind to zero.

### 4.4 Pits activity

Start with **static work poses** at the existing pits placements: seated at a table, kneeling at a parked aircraft, standing with a radio checking control throws. Generate them with the existing recipe from CC0 Poses 01/03 or a single frame of a downloaded clip. Moving hands (vertex animation or skinned IK) come later and only if the owner wants them after seeing the static poses.

### 4.5 Placements, collision and companions

Every person placement or envelope change alters person collision proxies, the flight-log collision identity and companion admission. Therefore:

- First reuse the **existing placements and person envelopes**. A new pose must fit the existing prefab envelope, or it becomes a reviewed collision change.
- A third companion pilot, a spotter or a kneeling prefab is a **collision-world change**, owned with the collision and AFC owners. Its acceptance includes the companion admission matrix and the collision identity.
- Placements only change through `tools/scenery/place.py`. People stay behind the pilot line except pilots and spotters; nobody stands on the runway (F1).

## 5. Technical approach

### 5.1 Layer A — static meshes, per-person head state

- **One mesh, one material per base and pose.** Merge the 6–7 parts and atlas their textures in the generator. Variety otherwise multiplies MultiMeshes (6 bases × 3 poses × ~8 parts ≈ 144, mostly single-instance) and breaks the 54-draw population cap.
- The generator writes a **head weight** per vertex (from MPFB's head/neck weights, including hair, cap and glasses) into a free vertex channel, plus the neck pivot per asset. Verify that glTF `TEXCOORD_2` or a custom attribute reaches `CUSTOM0`/`UV2` in Godot 4.7.2.
- The shader rotates each vertex by **angle × weight** around the pivot, and rotates `NORMAL` the same way. Do not `mix()` rest and fully rotated positions: at 70° yaw and weight 0.5 that shrinks the neck radius to about 0.82.
- The CPU head state (§4.1) writes yaw and pitch per instance into `INSTANCE_CUSTOM.w` (packed) or a second custom channel. That is at most ~18 small writes per frame after mesh merging. Verify custom-data precision in Compatibility.
- Projected contact shadows do not turn with the head. That is acceptable at these sizes.

### 5.2 Layer A2 — baked vertex animation (conditional)

Play baked clips on the MultiMesh with a per-instance phase (E7). Use **OpenVAT as an offline authoring tool**, like MPFB today. Ship only its texture outputs and record the tool and licence in the manifest (E6). Spike first: vertex texture fetch and precision in Compatibility, loop seams and texture memory.

### 5.3 Layer B — skinned crew actors (conditional)

A `CrewActor` has one `Skeleton3D` with one merged mesh and atlas material. It also has:

- An `AnimationPlayer` with `callback_mode_process = MANUAL`.
- `LookAtModifier3D` on chest, neck and head, in parent-to-child order, with `relative = true` and angle limits. Avoid overshooting transitions (E1).
- `TwoBoneIK3D` for hands (E2).
- `BoneAttachment3D` for the transmitter and props.
- Clips retargeted at import with `BoneMap` + `SkeletonProfileHumanoid` (E3).

**Timing:** one `CrewDirector` advances the animation mixer, then the skeleton modifiers, with the same simulation delta each frame. The skeleton uses `Skeleton3D.modifier_callback_mode_process = MANUAL` and `Skeleton3D.advance(delta)`; otherwise look-at easing follows render time and keeps moving while paused (E4). `AnimationMixer.deterministic` controls blend-weight normalization; it is not a reproducibility switch. There are no per-actor `_process` callbacks.

### 5.4 Materials

- **Skin without SSS:** per-channel wrap lighting with red widest and a warm terminator tint (E10). MakeHuman skins have no normal maps (A2).
- **Eyes:** CC0 eye materials with a small specular highlight; they matter only in close cameras.
- **glTF export:** plain PBR materials, applied modifiers, exported textures (A3).
- **Variety before new bases:** tints, caps, sunglasses and beards first. New skins must fit the remaining texture budget.

### 5.5 Quality tiers

Connect to the Scene detail preset ([VQ-06b](../research/visual-quality-implementation/VQ-06b-scene-detail/README.md)). Draw and primitive costs must fit the per-tier budget; at High the pilot view has about 10 draws left, so any increase there needs a matching reduction or an owner decision (D3).

| Preset | People |
| --- | --- |
| Low | Static merged meshes, no head motion |
| Medium and above | Head state, cloth flutter |
| Advanced option (off by default) | Vertex-animated pits, skinned crew, blinks and stick motion, each only after its measurement step passes |

Owner direction (2026-10-24): anything that needs more CPU/GPU than the head state becomes an explicit **advanced option** in Settings, off by default and independent of the preset, so players with strong machines can opt in. Its label states the cost. The preset never enables it implicitly.

## 6. Sources (download, do not model)

Details and evidence marks are in [the survey](../research/scenery-investigations/07-field-people-survey.md). Re-verify every licence against the downloaded archive and record SHA-256 in the source manifests.

| Need | Recommended | Alternatives | Rejected |
| --- | --- | --- | --- |
| Bodies, faces, skins | **MakeHuman/MPFB CC0**: system assets, Skins 01/02, Eyebrows 01, Eyelashes 01, eye materials 01, deformation targets (A1) | CharMorph CC-BY (A10); Quaternius Universal Base Characters, stylized (A5) | MB-Lab (AGPL); Renderpeople (redistribution unclear, 8K textures); MetaHuman |
| Clothing and accessories | CC0: Hats 01 (caps), Glasses 01, Shirts 01 (t-shirts, sweaters, tops), Pants 01, Shoes 01, Bodyparts 05 (beards) | CC-BY (D9): Hats 03, Shirts 03, Pants 03 (shorts), Shoes 02 (sneakers), Glasses 02 | Unlicensed Sketchfab items |
| Static poses | CC0 Poses 01 (sitting), Poses 03 (standing); single frames of A4 clips | — | Hand-posed figures |
| Blinks (Layer B only) | CC0 Faceunits 01 | — | Hand-made blend shapes |
| Animation clips (conditional) | **Quaternius UAL Standard, OpenGameArt CC0 listing** (posted 2025-04-16) (A4) | CMU mocap inside packaged GLBs with credit (A6) | Mixamo raw files; quaternius.com copies under QAL v1.0 |
| Vertex animation baking (conditional) | OpenVAT as an authoring tool (E6) | — | A home-made baker |
| Transmitters | **Owner-supplied models** (§7) | — | The current box transmitter after replacement |
| Pits props | Existing scenery library first ([01](../research/scenery-investigations/01-prop-asset-sources.md)), then Poly Haven CC0 | MakeHuman Equipment 03 (CC-BY) | Stylized Kenney props |

## 7. Transmitter intake (owner models)

Please provide, per radio:

1. File: `.glb`/`.gltf` preferred; `.blend` or `.fbx` accepted.
2. License or permission that allows redistribution in this public repository, plus author and source URL.
3. Real dimensions (width × height × depth) and units. For scale, a RadioMaster TX16S Mk II measures 287 × 129 × 184 mm and 750 g (F3).
4. Separate nodes, if available, for both gimbal sticks, switches, antenna and the neck-strap lug. Pivots at the gimbal centers.
5. Any textures as separate PNG/JPEG files.
6. Optionally a transmitter tray, for a pinch-grip variant (F2).

Intake: keep the delivery in `assets/source-deliveries/<radio>/` and record licence and SHA-256 in `assets/scenery/population/HUMAN_SOURCES.json`. The pilot recipe reduces the model to about 1.1k triangles with Godot auto LOD and bakes it into the merged pilot pose. Grip points are derived from the two stick shafts and fixed offsets in the radio frame instead of authored markers ([SC-HUM-01](../research/scenery-implementation/SC-HUM-01/README.md)). Default grip: thumbs and neck strap (F2). The pose must stay inside the existing `person_pilot` envelope (§4.5).

## 8. Steps

Each step is one reviewable change. Steps 01–07 need no skeletons, no vertex animation and no collision change.

| ID | Scope | Acceptance evidence |
| --- | --- | --- |
| SC-HUM-00 | **Done except the photo board, 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-00/README.md)): toolchain and recipe reproduction, CC0 intake, camera census (flight-line pilots are the only people seen at readable size in flight) and scene budget (population 49 → 40 draws, all limits pass). | Remaining: reference photo board for the owner's silhouette overlay. |
| SC-HUM-01 | **Done 2026-10-24 with the owner's draft T12D** ([evidence](../research/scenery-implementation/SC-HUM-01/README.md)): owner transmitter baked into both pilot outfits, thumbs on the gimbals. The pilot envelope depth went from 0.45 to 0.47 m; the collision capsule is unchanged. | Met in software: native captures, rigid-transmitter and triangle checks (1,200-triangle pilot allowance), envelope fit at natural height. Open: final model, licence, owner review. |
| SC-HUM-02 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-02/README.md)). One mesh and one atlas material per pose: people draw surfaces 19 → 3 with unchanged triangles; textures now VRAM-compressed with mipmaps. | Met: structural draw count, image diff within tolerance, population/scenery/shadow tests and native captures. Open: a `budget.sh` re-measure. |
| SC-HUM-03 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-03/README.md)). Head state for all 13 people: pilots coupled to the player aircraft, others step-and-hold (§4.1, §5.1). The neck pivot and weight come from each posed mesh, so no asset was regenerated. | Met in software: unit/behaviour test headless and native, MultiMesh read-back, five existing regressions, rendered poses and a running-app close-up at 1080p; zero draw delta; scripted routes unchanged. Open: owner review on real hardware. |
| SC-HUM-04 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-04/README.md)). The two existing flight-line pilots fly companion slots 0 and 1; an empty, faulted or removed slot returns its pilot to the player. | Met in software: behaviour tests, live two-companion run (on a disposable copy, because the current companion profile pin refuses admission), no placement or collision change. Open: owner review; third pilot via SC-HUM-13. |
| SC-HUM-05 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-05/README.md)). Step-and-hold shipped with SC-HUM-03; the crash glance runs on the crash presentation clock because a crash pauses the simulation. Remaining: generalize the crash flag into the shared field-event signal when the birds plan needs it. | Met in software: behaviour test and a live crash run. Open: owner review. |
| SC-HUM-06 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-06/README.md)): three pits members work at the tables with hands on the models (`person_working`, capsule +1.5 cm, layout regenerated by `place.py`); workers keep their eyes on the work unless a low pass or crash. | Met in software: gaze/population/collision/companion tests, live 1080p captures. Open: owner review; animated hands stay an advanced option. |
| SC-HUM-07 | **Done 2026-10-24 except caps** ([evidence](../research/scenery-implementation/SC-HUM-07/README.md), [faces](../research/scenery-implementation/SC-HUM-08/README.md)): six CC0 club members in one shared atlas (age, gender, ethnicity, clothing, glasses, fedora, beard); warm skin backlight, visible brows, wet eyes. Baseball caps wait for D9 (CC-BY). | Met in software: population/gaze tests, outfit guards, native A/B face captures. Open: owner review. |
| SC-HUM-08 | **Done 2026-10-24** ([evidence](../research/scenery-implementation/SC-HUM-08/README.md)): shirt hems move with the field wind (1.5 mm per m/s, ≤12 mm); zero wind is exact rest. | Met: native capture wind instants for all 11 variants (moves, repeats, calm restores); no draw change. Open: owner judgement of the amplitude. |
| SC-HUM-09 | **Owner review and decision point.** The owner flies with steps 01–08 at 1080p (then 1440p/4K, 720p last) and decides whether moving hands, idle animation or close-camera faces are worth Layer A2/B. | Owner notes; frame p95 on the owner's machine in paired runs; draws/primitives per tier. |
| SC-HUM-10 | (Conditional) Animation bake-off from the UAL archive's real clip list; retarget to the MPFB rig. | Clip list with licence, retarget notes. |
| SC-HUM-11 | (Conditional) Layer A2 spike with OpenVAT on one pits clip. | Compatibility vertex fetch works natively, seams, memory, pause/wrap hashes. |
| SC-HUM-12 | (Conditional) `CrewActor` prototype outside `app/` with manual mixer and skeleton advance. | Cost per actor at 1080p for 1, 8 and 20 actors; frames N and N+60 identical while paused mid-transition; go/no-go. |
| SC-HUM-13 | (Conditional) Further collision-world changes: third companion pilot, spotter or kneeling prefab, with collision and AFC owners. SC-HUM-06 already moved three pits members and added `person_working` with this verification. | Admission matrix, collision identity change recorded and explained. |

Verification rules for every step: scripts parse under `app/test.sh`; drafts live outside `app/` until they parse; the population tests and captures in [the population README](../../tools/scenery/population/README.md#validation) pass; use the [debug bridge](../../tools/debug/README.md) for low passes, wind-enabled runs and screenshots. No physics or golden-flight change is allowed. Frame-time deltas below workstation noise (LU-21 measured +0.5 to +1.7 ms run-to-run) are not used as gates; draws and primitives are.

## 9. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Stop after SC-HUM-09 unless the owner asks for moving hands or close-camera faces? | **Answered 2026-10-24:** continue; heavier features ship as advanced options (§5.5) |
| D2 | Realistic MPFB characters or stylized Quaternius characters? | MPFB, consistent with today's field (used for SC-HUM-07) |
| D3 | May High/Extreme exceed today's pilot-view budget, or must people pay for themselves? | People pay for themselves through mesh merging (SC-HUM-02) |
| D4 | Flight-line pilots when companions are off: idle with radio, watching the player, or removed? | Watching the player with the radio on a strap |
| D5 | Which transmitters, Mode 1 or Mode 2, and which grips? | Owner models, Mode 2, thumbs. **Applied:** Radiolink T12D draft, thumbs; neck strap not modelled yet |
| D6 | Animate transmitter sticks from companion commands? | Only if SC-HUM-09 approves Layer B |
| D7 | Crash reaction: heads only, or also a standing-up / pointing clip? | Heads only until SC-HUM-09 |
| D8 | Regional look and climate (clothing, hats, skin tones) | Owner to describe the home field |
| D9 | Licenses: CC0 only, or also CC-BY (men's shorts, baseball caps) and CMU with credits? | Start with CC0 (shipped in SC-HUM-07); CC0 lacks men's shorts and baseball caps, so add CC-BY only for those |
| D10 | A third companion pilot needs a new placement (collision and admission change). Accept that, or show at most two companion pilots? | Two pilots first; the third through SC-HUM-13 |

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| Effort spent on people the pilot never sees | Camera census in SC-HUM-00; flight-line pilots first |
| Scene budget exceeded | Mesh merging before variety; draws and primitives in every acceptance |
| Heads move in sync | Per-person CPU state with seeded parameters; time-series acceptance test |
| Uncanny faces at close range | Caps, sunglasses, restrained skin shader; priority on silhouette and motion (H7) |
| Render-only work silently changes collision or companion admission | Existing placements and envelopes only; collision changes isolated in SC-HUM-13 |
| Skeleton easing follows render time | Manual mixer and skeleton advance by simulation delta; paused-frame test |
| Licence drift (Quaternius QAL change, CMU wording, mixed MakeHuman packs) | Dated CC0 copies with archived page and licence hashes; packaged GLBs only for CMU |
| Distraction from the aircraft | Subtle amplitude; owner review in SC-HUM-09; Low preset keeps people static |
