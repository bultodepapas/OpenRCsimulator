# Field people: crew, pilots and spectators

2026-10-24 · Revision 2 · **Planning draft** · Step prefix: **SC-HUM** (Scenery subtrack; not yet in the [registry](../README.md#tracks-plans-and-step-ids)) · Gate: **SC**

**Status:** proposal only. Nothing is implemented. Owner decisions D1–D10 (§9) are open. This plan expands the parked [SC-21 "Animated spectators"](../SCENERY-PLAN.md#remaining-work). Revision 2 adds the [web survey](../research/scenery-investigations/07-field-people-survey.md) (25 searches, 6 page reads). It brings in measured gaze behavior, attention contagion, exact MakeHuman pack licenses, the Quaternius licence change, a vertex-animation option for the pits, a skin shader and transmitter scale. Survey row IDs (H1, E1, A1, F1…) are cited inline.

**Owner:** Scenery and field life ([SCENERY-PLAN](../SCENERY-PLAN.md)), which owns today's LU-21 population. Coordination: LU/VQ (scene budget, Scene detail preset), AFC (companion aircraft and pilots, person airspace proxies), collision world (person capsules), CR (crash events), FW/TOD (lighting).

**Proposed ownership:** `app/scenery/population*.gd|gdshader` (existing), new `app/scenery/crew/`, `app/assets/scenery/population/` (runtime), `assets/scenery/population/` (sources and manifests), `tools/scenery/population/`, `app/tests/test_field_people_*.gd`, evidence in `docs/research/scenery-implementation/SC-HUM-*/`. Shared hooks stay with their owners.

## 1. Goal

Make the people at the club field read as real RC modelers. Improve their models, faces and textures. Pilots should hold real transmitters. Heads should follow the aircraft the way real watchers do. Some club members should sit or kneel in the pits preparing their aircraft. All of this must stay cheap at 1080p, deterministic, and never compete with the aircraft for the pilot's attention.

Source characters, clothing and animation from free, redistributable packs. Do not model or animate by hand what can be downloaded. Procedural motion is limited to head aim, hand IK, cloth flutter and timing.

Non-goals: walking or pathfinding, crowds, lip sync and facial expressions, cloth simulation, voices, changing collision behavior, a player avatar.

## 2. Current baseline (LU-21)

| Fact | Where |
| --- | --- |
| 13 people in 3 static poses: 2 pilots on the flight line, 5 standing in the pits, 3 seated on benches, 3 on the veranda | [default.json](../../app/data/scenery/default.json) (`pilots`, `pits-people`, `seated`, `veranda-people`) |
| MakeHuman CC0 assets posed by Blender 5.2.2 + MPFB 2.0.18 into static glTF meshes (`standing`, `sitting`, `pilot`) | [generate_people.py](../../tools/scenery/population/generate_people.py), [HUMAN_SOURCES.json](../../assets/scenery/population/HUMAN_SOURCES.json) |
| One MultiMesh per mesh part, with per-instance shirt tint and skin tone. No skeletons and no per-actor process callbacks | [population.gd](../../app/scenery/population.gd) |
| Motion is sub-centimeter vertex sway driven by `sim_clock` (k/1024 Hz). `INSTANCE_CUSTOM` = (phase, moving, skin tone, **unused**) | [population_person.gdshader](../../app/scenery/population_person.gdshader), [shader_clock.gd](../../app/render/shader_clock.gd) |
| The global `wind_vec` uniform already reaches every shader | [shader_clock.gd](../../app/render/shader_clock.gd) |
| The pilot holds a "simple original transmitter" baked into the mesh | [LU-21](../research/landscape-upgrade/LU-21/README.md) |
| Close person ≤8k triangles (7.3–7.9k); auto LOD 7,150→890 at 5→120 m; 1K/512/256 shared textures | [LU-21 budgets](../research/landscape-upgrade/LU-21/README.md#measured-budgets) |
| Whole-scene headroom on the LU-21 measurement: 246/300 draws, 539k/600k triangles, frame p95 4.07 ms (RTX 3090, 1080p) | same |
| Characters cast no engine shadows. Custom projected/contact shadows use cached CPU instance transforms | [field_projected_shadows.gd](../../app/render/field_projected_shadows.gd) |
| Companion aircraft exist (1–3 Ugly Stiks, off by default) but have **no pilot figures**. Their `render()` already exposes the interpolated pose and commands | [agent.gd](../../app/ai/companions/agent.gd) |
| Pits already contain 13 parked aircraft on tables (0.90 m), foam stands and grass bays | [SC-09-R1](../research/scenery-implementation/SC-09-R1/README.md) |
| Legacy procedural `people.gd` remains for old checks only | [people.gd](../../app/scenery/people.gd) |

Hard constraints: Godot 4.7.2 **Compatibility** (OpenGL 3.3, no compute, no screen-space SSS), shaders never read `TIME`, captures repeat byte for byte, pause/reset/replay follow simulation time, simulation state is unchanged (render-only work), and the [display priorities](../../AGENTS.md#display-resolution-priorities) apply.

## 3. How big a person is on screen (1080p first)

At the default 50° vertical FOV: `px ≈ 1158 · size / d` (same law as [the birds plan](birds-sky-life.md#3-how-big-a-bird-is-on-screen-1080p-first)). The auto zoom narrows the FOV toward the aircraft, so people are usually seen at 50°.

| Subject | Size | Distance from pilot | px 1080p | px 1440p | px 2160p |
| --- | --- | --- | --- | --- | --- |
| Flight-line pilot, body | 1.75 m | 13–16 m | 127–156 | 169–208 | 254–312 |
| Same pilot, head | 0.23 m | 13–16 m | 17–20 | 22–27 | 33–41 |
| Transmitter, width (TX16S class, F3) | 0.287 m | 13 m | 26 | 34 | 51 |
| Transmitter stick | 0.02 m | 13 m | 1.8 | 2.4 | 3.6 |
| Seated spectator, head | 0.23 m | 20–22 m | 12–13 | 16–18 | 24–27 |
| Pits member, body | 1.75 m | 31–43 m | 47–65 | 63–87 | 94–131 |
| Pits member, head | 0.23 m | 31–43 m | 6–9 | 8–11 | 12–17 |

Consequences:

1. From the pilot view, **silhouette, posture, head direction and motion** carry realism. People recognise human action from a dozen moving joints but not from a still frame (H8). A 30° head turn on a 17–20 px head is clearly readable; pore detail is not.
2. Eyes are invisible at these sizes, so the head must carry slightly more of each gaze shift than a real person's head does (H1).
3. Face and texture quality matter for close cameras (pits, orbit, chase near the ground, trailer) and higher resolutions. They are the second priority.
4. Stick motion on a transmitter is visible only in close cameras. It is optional.
5. Caps and sunglasses are common at real RC fields. They also hide the weakest part of a game face. Mid-realism faces are rated least appealing, and faces without blinks or gaze look unpleasant (H7).

## 4. Behavior design

All behavior is render-only and stateless with respect to the simulation. It reads interpolated aircraft poses, `sim_clock` and `wind_vec`. It never writes simulation state.

### 4.1 Head tracking

Two modes, from gaze research:

- **Coupled (pilots, spotters):** the head stays locked to the aircraft direction, as batters' heads rotate with the ball (H2). Aim at a predicted point `p + v·τ` with τ 0.1–0.3 s [est]. Observers anticipate (H3), and the lead partly cancels the follower lag.
- **Step-and-hold (everyone else):** the head holds still while the target stays inside a dead zone of 10–20° [est], because small shifts are done by the eyes (H1). Beyond it, the head turns and follows with a critically damped lag of 0.25–0.4 s [est] until the target settles.

Shared rules:

- **Distribution:** chest 10–15 %, neck ~30 %, head 55–60 % [est] (H10). Layer A rotates neck and head only. Feet and hips never turn.
- **Limits:** yaw ±70°, pitch −15°…+50° [est]. Rotate yaw first, then pitch (H4). A rear gate (dot-product test) sends the head back to rest instead of snapping across (H10).
- **Per-person variation:** a seeded "head mover" factor (H1), plus limits, lag, dead zone and a small rest offset. Heads must never move in sync.

### 4.2 Attention

One shared, deterministic **attention director** scores candidate targets per person. Inputs are distance, a loudness proxy (engine power / r²), low height and novelty. A crash is the strongest novelty event.

**Contagion:** a person is more likely to look when neighbors already look. The probability grows with the number of lookers but has no tipping point (H6). Cap contagion so some people always keep doing their own thing (around one in four follows a group, H6).

| Role | Default focus | Interrupts |
| --- | --- | --- |
| Flight-line pilot (companion) | Their own aircraft, coupled | None |
| Spotter (optional, F1) | The same aircraft as its pilot; brief glance to the runway on approach | Crash |
| Flight-line pilot (no companion) | Per D4: idle with radio, or watching the player | Low/loud player pass |
| Seated spectator | Player aircraft when within range, else neighbor or rest | Crash, low pass, contagion |
| Veranda pair | Each other (conversation) | Low pass, crash, contagion |
| Pits member | Their aircraft on the table | Low pass over the pits, crash, a companion takeoff |
| Photographer variant (F4) | Player aircraft, phone or camera raised during low passes | — |

Glance and variation schedules derive from `hash(seed, floor(sim_clock / period))`, not from a random-number state, so captures and replays repeat exactly.

### 4.3 Idle life

- **No lockstep:** each person gets a rhythm scale of 0.85–1.15 [est] on every loop. A single looping idle is noticed within about 90 s (H9).
- **Role pools:** pilots, spotters, spectators and pits members use separate clip pools. Scheduled variations (look around, stretch, sip from a bottle, adjust cap) break long loops (H9).
- **Blinks** only on close skinned actors without sunglasses: seeded 12–26 per minute, more while chatting (H5), from CC0 ARKit-style face units (A1).
- **Cloth flutter:** shirt hems and sleeves move with `wind_vec`, masked so shoulders and collars stay pinned (E11). Use a vertex channel separate from the head weight.

### 4.4 Pits activity

Seated or kneeling members work beside the parked aircraft: hands moving over the airframe, a radio on a neck strap or on the table checking control throws, a field box, a glow starter or a fuel pump. Use downloaded looping clips plus hand IK to points on the parked aircraft (Layer B), or the same clips baked to vertex animation (Layer A2). Do not hand-key animation.

### 4.5 Field rules

Follow the AMA layout already used for the field ([03](../research/scenery-investigations/03-rc-field-layout-references.md)). Only pilots and spotters stand at or in front of the pilot line. Spectators stay behind it. Pits members never stand on the runway or taxiway (F1).

## 5. Technical approach

Layers are delivered in order. Each is useful alone and remains the fallback for the next.

### 5.1 Layer A — head aim on the existing MultiMesh

- The generator writes a **head weight** per vertex (from MPFB's head/neck skin weights, including hair, cap and glasses proxies) into a free vertex channel (`CUSTOM0` or `UV2`), plus the neck pivot per asset.
- The person shader rotates weighted vertices around the pivot and blends with `mix()` between rest and rotated positions. Multiplying by the mask would shrink the head (E5).
- A small CPU publisher writes smoothed, lead-corrected targets as **global shader parameters** (`look_target_0…3`: player plus up to three companions), next to the existing `ShaderClock.update` call in [main.gd](../../app/main.gd). The lag of §4.1 is applied once per target on the CPU. The dead zone and per-person factors are evaluated in the shader from the seed.
- `INSTANCE_CUSTOM.w` (currently unused) packs the target index, mode (coupled/step) and attention class.
- Cost: no new draws, no per-instance CPU work, four uniform writes per frame. Limits: no true per-person lag history, and contagion is approximated by clock-hashed schedules. The contact-shadow silhouettes do not turn with the head; that is acceptable at these sizes.

### 5.2 Layer A2 — baked vertex animation for pits workers (option)

Bake selected clips (work at table, kneel and inspect, chat) offline to vertex animation textures and play them on the MultiMesh with a per-instance phase. This is the standard pattern for many animated people without skeletons (E7). Write a small baker in the existing Blender recipe instead of adopting the GPL OpenVAT tool (E6). Spike first: vertex texture fetch and precision in Compatibility, texture size per clip, and loop seams.

### 5.3 Layer B — skinned crew actors

A `CrewActor` is one `Skeleton3D` with one merged mesh (one material, atlas texture) and:

- An `AnimationPlayer` with `callback_mode_process = MANUAL`, advanced by simulation delta from one director (E4). It pauses, steps and replays with the simulation. Test the `deterministic` flag explicitly.
- `LookAtModifier3D` on chest, neck and head, in parent-to-child order, with `relative = true` over the idle clip, angle limits and damp thresholds from §4.1. Do not use overshooting transitions (`BACK`, `ELASTIC`, `SPRING`) (E1).
- `TwoBoneIK3D` (Godot 4.6+ IK family) to put hands on transmitter grips or aircraft points (E2).
- `BoneAttachment3D` for the transmitter, cap and props.
- Clips retargeted at import with `BoneMap` + `SkeletonProfileHumanoid` and the rest fixer; options recorded in the manifest (E3).

One `CrewDirector` updates all actors in one loop. There are no per-actor `_process` callbacks. Actors outside the frustum or beyond a range skip modifier and animation updates. Mesh LOD and `visibility_range` handle distance. Compatibility has no public skinning benchmark (E8), so SC-HUM-05 is a hard measurement gate. Octahedral impostors are rejected (E9).

**One person is never drawn twice:** an actor uses exactly one layer at a time.

### 5.4 Materials

- **Skin without SSS:** per-channel wrap lighting with red wrapping widest, and a warm tint at the light/shadow terminator (E10). Keep `diffuse_burley`. Roughness varies by face region. MakeHuman skins have no normal maps (A2); use shader detail first.
- **Eyes:** CC0 eye materials with a small specular highlight (A1). They only matter for close cameras.
- **glTF export:** switch MPFB materials to plain PBR, apply modifiers and export textures. Otherwise materials come out white or grey (A3).
- One atlas material per character on Layer B. Layer A keeps today's shared materials and tints.

### 5.5 Quality tiers

Connect to the existing Scene detail preset ([VQ-06b](../research/visual-quality-implementation/VQ-06b-scene-detail/README.md)):

| Preset | People |
| --- | --- |
| Low | Static MultiMesh, today's behavior |
| Medium | Layer A head aim and cloth flutter |
| High | Layer A + A2 (animated pits) |
| Extreme | Layer B crew near the pilot, Layer A beyond |

## 6. Sources (download, do not model)

Details, licenses and evidence marks are in [the survey](../research/scenery-investigations/07-field-people-survey.md). Re-verify every licence against the downloaded archive and record SHA-256 in the source manifests.

| Need | Recommended | Alternatives | Rejected |
| --- | --- | --- | --- |
| Realistic bodies, faces, skins | **MakeHuman/MPFB CC0**: system assets, Skins 01/02, Eyebrows 01 and Eyelashes 01, eye materials 01, realistic deformation targets (A1) | CharMorph CC-BY bases (A10); Quaternius Universal Base Characters as a stylized fallback (A5) | MB-Lab (AGPL, A10); Renderpeople scans (redistribution unclear, 8K textures, A9); MetaHuman |
| Clothing and accessories | CC0: Hats 01 (caps), Glasses 01, Shirts 01, Pants 01, Shoes 01, Bodyparts 05 (beards) | **CC-BY** (needs D9): Hats 03 caps, Shirts 03 short sleeves, Pants 03 shorts, Shoes 02 sneakers, Glasses 02 | Unlicensed Sketchfab items |
| Blinks | CC0 Faceunits 01 (ARKit-style) | — | Hand-made blend shapes |
| Animation clips | **Quaternius UAL Standard from the OpenGameArt CC0 listing** (posted 2025-04-16), plus UAL 2 if needed (A4) | CMU mocap, shipped only inside packaged GLBs with credit (A6); MakeHuman CC0 Poses 01/03 (static) | Mixamo raw files (A7); quaternius.com copies under QAL v1.0 (A4) |
| Transmitters | **Owner-supplied models** (§7) | — | Today's original box transmitter after replacement |
| Pits props | Existing scenery library ([01](../research/scenery-investigations/01-prop-asset-sources.md) already lists CC0 gas cans), then Poly Haven CC0 | MakeHuman Equipment 03 bags and tools (CC-BY) | Stylized Kenney props (style clash) |

## 7. Transmitter intake (owner models)

Please provide, per radio:

1. File: `.glb`/`.gltf` preferred; `.blend` or `.fbx` accepted.
2. License or permission that allows redistribution in this public repository, plus author and source URL.
3. Real dimensions (width × height × depth) and units. For scale, a RadioMaster TX16S Mk II measures 287 × 129 × 184 mm and 750 g (F3).
4. Separate nodes, if available, for both gimbal sticks, switches, antenna and the neck-strap lug. Pivots at the gimbal centers.
5. Any textures as separate PNG/JPEG files.
6. Optionally a transmitter tray, for the pinch-grip variant (F2).

Intake steps: record license/SHA-256 in `assets/scenery/population/` manifests; normalize scale and axes in the existing Blender recipe; budget ≤3k triangles close, with Godot auto LOD; add grip markers (`grip_L`, `grip_R`, `thumb_L`, `thumb_R`, `strap`). Layer A bakes the radio into the pilot pose. Layer B attaches it to a hand bone and uses IK for the second hand. Default grip: thumbs with a neck strap; tray/pinch as a seeded minority if a tray exists (F2).

## 8. Steps

| ID | Scope | Acceptance evidence |
| --- | --- | --- |
| SC-HUM-00 | Baseline and intake. Native 1080p captures of today's people at 5/15/40 m and from the pilot view (1440p/4K secondary). Build an RC-field reference photo board for the owner's silhouette overlay. Download candidate packs into isolated folders and verify each licence file. | Capture set, licence table with hashes, budget table. Keep only the images needed for review in the repository. |
| SC-HUM-01 | Layer A head aim (§5.1) for pilots and spectators, with coupled and step-and-hold modes and the player as the only target. | Shader/generator tests. Captures of a scripted low pass showing heads following at 1080p. Pause, step, reset and 1024 s wrap hashes match. Zero draw delta. Frame p95 delta ≤0.1 ms at 1080p. Golden flights unchanged. |
| SC-HUM-02 | Owner transmitters (§7) baked into the pilot pose. Grip variants per D5. | Intake manifest, close captures at 1080p, fitted grip check against real dimensions, triangle budget. |
| SC-HUM-03 | Regenerated characters: 6–8 bases (age, sex, build, skin), CC0 skins, eyebrows/lashes, eyes with a specular highlight, caps, sunglasses and field clothing (D9). Skin shader (§5.4) and cloth flutter (§4.3). | Before/after captures at 5/15/40 m and pilot view, owner silhouette overlay, ≤8k triangles close, texture budget within LU-21 limits, fresh-import test, flutter frozen when paused. |
| SC-HUM-04 | Animation bake-off: inspect the UAL archive's real clip list against CMU and MakeHuman poses for idle-stand, idle-sit, work-at-table, kneel, chat, holding a transmitter and phone-photo. Retarget to the MPFB rig (E3). | Clip list with licence, retarget notes and short loops viewed on the target rig. |
| SC-HUM-04b | Layer A2 spike (§5.2): one baked pits clip on the MultiMesh. | Compatibility vertex texture fetch works natively, loop seams, texture memory, phase variety, pause/wrap hashes. |
| SC-HUM-05 | `CrewActor` prototype outside `app/` (§5.3): one pilot with look-at, hand IK on the radio and manual animation advance. Verify every Godot class in 4.7.2 Compatibility. | Cost per actor (CPU and GPU) at 1080p for 1, 8 and 20 actors. Identical frames across two runs and across pause/step. Go/no-go for Layer B. |
| SC-HUM-06 | Flight-line pilots bound to AI companions: one pilot per companion, coupled to its own aircraft; optional spotter; behavior without companions per D4. Optional stick motion from companion commands (D6). | Companion flight captures, roster add/remove/restart, no change to companion admission or airspace results. |
| SC-HUM-07 | Pits members preparing aircraft (§4.4) beside existing parked aircraft. New placements go through `tools/scenery/place.py`, with person capsules and companion person proxies updated with their owners. | Close pits captures, collision and airspace regression, glances during low passes. |
| SC-HUM-08 | Attention director (§4.2) with contagion, crash reaction, idle variations (§4.3) and the photographer variant. | Scripted pass and crash captures; share of people looking stays within the designed cap; schedule hashes repeat across runs. |
| SC-HUM-09 | Quality tiers (§5.5), skinned range and the population budget entry. | Scene budget test per tier, preset switching, no double drawing. |
| SC-HUM-10 | Acceptance: 1080p primary, then 1440p/4K, 720p last. The owner flies the Gate 2 maneuvers and judges realism and distraction. | Owner review notes, frame p95/draws/memory per tier on the owner's machine. |

Order: 00 → 01 and 02 (independent) → 03 → 04 → 04b and 05 (independent) → 06/07/08 → 09 → 10. Layer A (01–03) is useful even if A2 and B are rejected.

Verification rules for every step: scripts parse under `app/test.sh`; drafts live outside `app/` until they parse; the population tests and captures in [the population README](../../tools/scenery/population/README.md#validation) pass; use the [debug bridge](../../tools/debug/README.md) to drive low passes and screenshots; no physics or golden-flight change is expected or allowed.

## 9. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Layer A first, then A2/B; or skinned actors directly? | Layer A first: it is visible quickly and remains the fallback |
| D2 | Realistic MPFB characters or stylized Quaternius characters? | MPFB, consistent with today's field |
| D3 | How many people and where? May the scene budget rise (draws/triangles) for High/Extreme? | Keep 13–18 people; allow up to +20 draws on Extreme only |
| D4 | Flight-line pilots when companions are off: idle with radio, watching the player, or removed? | Watching the player with the radio on a strap |
| D5 | Which transmitters, Mode 1 or Mode 2, and which grips (thumbs, pinch with tray, hybrid)? | Owner models, Mode 2, thumbs and neck strap by default |
| D6 | Animate transmitter sticks from companion commands? | Later; visible only in close cameras |
| D7 | Crash reaction: heads only, or also a standing-up / pointing clip? | Heads first; clips after SC-HUM-04 |
| D8 | Regional look and climate (clothing, hats, skin tones) | Owner to describe the home field |
| D9 | Licenses: CC0 only, or also CC-BY (short sleeves, shorts, sneakers, more caps) and CMU with credits? | Allow CC-BY and CMU with exported credits; CC0 alone dresses the field in long sleeves and trousers |
| D10 | Animated pits by baked vertex animation (A2) or only by skinned actors (B)? | Spike A2 first; it costs no skeletons and fits the existing batches |

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| Uncanny faces at close range | Caps, sunglasses, restrained skin shader, blinks only where faces are readable; priority on silhouette and motion (H7) |
| Heads turning in sync look robotic | Dead zones, seeded mover factors, lags and rest offsets; contagion capped (H1, H6) |
| Idle loops become noticeable | Rhythm scale per person, role pools, scheduled variations (H9) |
| Skinned actors exceed the CPU/draw budget | SC-HUM-05 measurement gate; Layer A/A2 fallback; range culling; one material per actor |
| Vertex animation fails in Compatibility | SC-HUM-04b spike before any production use; Layer A remains |
| Distraction from the aircraft | Subtle amplitude; owner review in SC-HUM-10; quality tier off switch |
| Licence drift (Quaternius QAL change, CMU wording, mixed MakeHuman packs) | Take the dated CC0 copy, archive its page and licence file with hashes; ship only packaged GLBs for CMU; per-pack licence check |
| Contact shadows do not follow animated poses | Accept for Layer A; for Layer B, measure a pose-aware shadow footprint only if the owner sees the mismatch |
| Placement changes break collision or companion airspace | Placements only through the generator; regression with collision and AFC owners |
