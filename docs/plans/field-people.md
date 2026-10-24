# Field people: crew, pilots and spectators

2026-10-24 · Revision 1 · **Planning draft** · Step prefix: **SC-HUM** (Scenery subtrack; not yet in the [registry](../README.md#tracks-plans-and-step-ids)) · Gate: **SC**

**Status:** proposal only. Nothing is implemented. Owner decisions D1–D9 (§9) are open. This plan expands the parked [SC-21 "Animated spectators"](../SCENERY-PLAN.md#remaining-work).

**Owner:** Scenery and field life ([SCENERY-PLAN](../SCENERY-PLAN.md)), which owns today's LU-21 population. Coordination: LU/VQ (scene budget, Scene detail preset), AFC (companion aircraft and pilots, person airspace proxies), collision world (person capsules), CR (crash events), FW/TOD (lighting).

**Proposed ownership:** `app/scenery/population*.gd|gdshader` (existing), new `app/scenery/crew/`, `app/assets/scenery/population/` (runtime), `assets/scenery/population/` (sources and manifests), `tools/scenery/population/`, `app/tests/test_field_people_*.gd`, evidence in `docs/research/scenery-implementation/SC-HUM-*/`. Shared hooks stay with their owners.

## 1. Goal

Make the people at the club field read as real RC modelers. Improve their models, faces and textures. Pilots should hold real transmitters. Heads should follow the aircraft with a subtle, human lag. Some club members should sit or kneel in the pits preparing their aircraft. All of this must stay cheap at 1080p, deterministic, and never compete with the aircraft for the pilot's attention.

Source characters, clothing and animation from free, redistributable packs. Do not model or animate by hand what can be downloaded. Procedural motion is limited to head aim, hand IK and timing.

Non-goals: walking or pathfinding, crowds, facial animation and lip sync, cloth simulation, voices, changing collision behavior, a player avatar.

## 2. Current baseline (LU-21)

| Fact | Where |
| --- | --- |
| 13 people in 3 static poses: 2 pilots on the flight line, 5 standing in the pits, 3 seated on benches, 3 on the veranda | [default.json](../../app/data/scenery/default.json) (`pilots`, `pits-people`, `seated`, `veranda-people`) |
| MakeHuman CC0 assets posed by Blender 5.2.2 + MPFB 2.0.18 into static glTF meshes (`standing`, `sitting`, `pilot`) | [generate_people.py](../../tools/scenery/population/generate_people.py), [HUMAN_SOURCES.json](../../assets/scenery/population/HUMAN_SOURCES.json) |
| One MultiMesh per mesh part, with per-instance shirt tint and skin tone. No skeletons and no per-actor process callbacks | [population.gd](../../app/scenery/population.gd) |
| Motion is sub-centimeter vertex sway driven by `sim_clock` (k/1024 Hz). `INSTANCE_CUSTOM` = (phase, moving, skin tone, **unused**) | [population_person.gdshader](../../app/scenery/population_person.gdshader), [shader_clock.gd](../../app/render/shader_clock.gd) |
| The pilot holds a "simple original transmitter" baked into the mesh | [LU-21](../research/landscape-upgrade/LU-21/README.md) |
| Close person ≤8k triangles (7.3–7.9k); auto LOD 7,150→890 at 5→120 m; 1K/512/256 shared textures | [LU-21 budgets](../research/landscape-upgrade/LU-21/README.md#measured-budgets) |
| Whole-scene headroom on the LU-21 measurement: 246/300 draws, 539k/600k triangles, frame p95 4.07 ms (RTX 3090, 1080p) | same |
| Characters cast no engine shadows. Custom projected/contact shadows use cached CPU instance transforms | [field_projected_shadows.gd](../../app/render/field_projected_shadows.gd) |
| Companion aircraft exist (1–3 Ugly Stiks, off by default) but have **no pilot figures**. Their `render()` already exposes the interpolated pose and commands | [agent.gd](../../app/ai/companions/agent.gd) |
| Pits already contain 13 parked aircraft on tables (0.90 m), foam stands and grass bays | [SC-09-R1](../research/scenery-implementation/SC-09-R1/README.md) |
| Legacy procedural `people.gd` remains for old checks only | [people.gd](../../app/scenery/people.gd) |

Hard constraints: Godot 4.7.2 **Compatibility** (OpenGL 3.3, no compute), shaders never read `TIME`, captures repeat byte for byte, pause/reset/replay follow simulation time, simulation state is unchanged (render-only work), and the [display priorities](../../AGENTS.md#display-resolution-priorities) apply.

## 3. How big a person is on screen (1080p first)

At the default 50° vertical FOV: `px ≈ 1158 · size / d` (same law as [the birds plan](birds-sky-life.md#3-how-big-a-bird-is-on-screen-1080p-first)). The auto zoom narrows the FOV toward the aircraft, so people are usually seen at 50°.

| Subject | Size | Distance from pilot | px 1080p | px 1440p | px 2160p |
| --- | --- | --- | --- | --- | --- |
| Flight-line pilot, body | 1.75 m | 13–16 m | 127–156 | 169–208 | 254–312 |
| Same pilot, head | 0.23 m | 13–16 m | 17–20 | 22–27 | 33–41 |
| Transmitter | 0.20 m | 13 m | 18 | 24 | 36 |
| Transmitter stick | 0.02 m | 13 m | 1.8 | 2.4 | 3.6 |
| Seated spectator, head | 0.23 m | 20–22 m | 12–13 | 16–18 | 24–27 |
| Pits member, body | 1.75 m | 31–43 m | 47–65 | 63–87 | 94–131 |
| Pits member, head | 0.23 m | 31–43 m | 6–9 | 8–11 | 12–17 |

Consequences:

1. From the pilot view, **silhouette, posture, head direction and motion** carry realism. A 30° head turn on a 17–20 px head is clearly readable; pore detail is not.
2. Face and texture quality matter for close cameras (pits, orbit, chase near the ground, trailer) and higher resolutions. They are the second priority.
3. Stick motion on a transmitter is visible only in close cameras. It is optional.
4. Caps and sunglasses are common at real RC fields. They also hide the weakest part of a low-poly game face.

## 4. Behavior design

All behavior is render-only and stateless with respect to the simulation. It reads interpolated aircraft poses and `sim_clock`. It never writes simulation state.

### 4.1 Head tracking

- **Pivot chain:** head 60–70% and neck 30–40% of the rotation. Upper spine joins only on skinned actors (≤15%). The feet and hips never turn.
- **Limits** [est, tune with owner]: yaw ±70°, pitch −15°…+50°. Beyond the limit the head eases back to rest instead of snapping.
- **Lag:** a critically damped follower on the target direction with a 0.25–0.4 s time constant [est]. Fast passes produce a visible catch-up, as real watchers show.
- **Per-person variation:** seed-hashed limits, lag and a small rest offset, so heads are never perfectly synchronized.

### 4.2 Attention

One shared, deterministic **attention director** scores candidate targets per person. Inputs are distance, a loudness proxy (engine power / r²), low height and novelty. A crash is the strongest novelty event.

| Role | Default focus | Interrupts |
| --- | --- | --- |
| Flight-line pilot (companion) | Their own aircraft, always | None |
| Flight-line pilot (no companion) | Per D4: idle with radio, or watching the player | Low/loud player pass |
| Seated spectator | Player aircraft when within range, else neighbor or rest | Crash, low pass |
| Veranda pair | Each other (conversation) | Low pass, crash |
| Pits member | Their aircraft on the table | Low pass over the pits, crash, a companion takeoff |

Glance schedules derive from `hash(seed, floor(sim_clock / period))`, not from a random-number state, so captures and replays repeat exactly.

### 4.3 Pits activity

Seated or kneeling members work beside the parked aircraft: hands moving over the airframe, a radio on a neck strap or on the table checking control throws, a field box, a glow starter or a fuel pump. Use downloaded looping clips (for example "interact" or "work at table") plus hand IK to points on the parked aircraft. Do not hand-key animation.

## 5. Technical approach

Two layers, delivered in order. Layer A is cheap and lands first; Layer B replaces it near the pilot when the budget allows.

### 5.1 Layer A — head aim on the existing MultiMesh

- The generator writes a **head weight** per vertex (from MPFB's head/neck skin weights, including hair, cap and glasses proxies) into a free vertex channel (`CUSTOM0` or `UV2`), plus the neck pivot per asset.
- The person shader rotates weighted vertices around the pivot. The yaw and pitch come from the instance's world position and a target.
- A small CPU publisher writes smoothed targets as **global shader parameters** (`look_target_0…3`: player plus up to three companions), next to the existing `ShaderClock.update` call in [main.gd](../../app/main.gd). Lag (§4.1) is applied once per target on the CPU.
- `INSTANCE_CUSTOM.w` (currently unused) packs the target index and attention class.
- Cost: no new draws, no per-instance CPU work, four uniform writes per frame. Limits: no per-person lag and no attention switching beyond what the shader can derive from the clock. The contact-shadow silhouettes do not turn with the head; that is acceptable at these sizes.

### 5.2 Layer B — skinned crew actors

A `CrewActor` is one `Skeleton3D` with one merged mesh (one material, atlas texture) and:

- `AnimationPlayer` with **manual callback mode**, advanced by simulation delta. It pauses, steps and replays with the simulation.
- `LookAtModifier3D` on neck and head (Godot 4.4+, angle limits and `duration` smoothing).
- `TwoBoneIK3D` (Godot 4.6+ IK family) to put hands on transmitter grips or aircraft points.
- `BoneAttachment3D` for the transmitter, cap and props.

One `CrewDirector` updates all actors in one loop. There are no per-actor `_process` callbacks. Actors outside the frustum or beyond a range skip modifier and animation updates. Mesh LOD and `visibility_range` handle distance. The class names and behavior above must be verified in Godot 4.7.2 by SC-HUM-05 before they are relied on.

**Far fallback:** keep Layer A's MultiMesh for actors beyond the skinned range or on lower quality tiers. One person is never drawn twice.

### 5.3 Quality tiers

Connect to the existing Scene detail preset ([VQ-06b](../research/visual-quality-implementation/VQ-06b-scene-detail/README.md)):

| Preset | People |
| --- | --- |
| Low | Static MultiMesh, today's behavior |
| Medium | Layer A head aim |
| High / Extreme | Layer B crew near the pilot, Layer A beyond |

## 6. Sources (download, do not model)

Survey 2026-10-24; licenses must be verified against the downloaded files in SC-HUM-00 and recorded with SHA-256 in the source manifests.

| Need | Recommended | Alternatives | Rejected |
| --- | --- | --- | --- |
| Realistic bodies, faces, skins | **MakeHuman/MPFB CC0 system assets** (current pipeline), CC0 natural male/female skin packs, CC0 realistic face-deformation targets ([asset packs](https://static.makehumancommunity.org/assets/assetpacks.html)) | CharMorph CC-BY base models ([announcement](https://www.blendernation.com/2025/03/19/charmorph-v0-4-0-character-creator-released/)) | MB-Lab output (AGPL-3 by default, [ref](https://en.wikipedia.org/wiki/MB-Lab)); MetaHuman (Unreal-only terms) |
| Caps, glasses, clothing | MakeHuman Hats 01–04 and Glasses 01–02 packs (license to verify per pack) | OpenGameArt CC0 items | Unlicensed Sketchfab items |
| Skin normal/detail maps | Not in MakeHuman ([contributor note](https://static.makehumancommunity.org/mpfb/contributing/art.html)); search CC0 detail maps in SC-HUM-00 | Shader-only wrap lighting and roughness variation | Hand-painted maps |
| Animation clips | **Quaternius Universal Animation Library**, CC0, humanoid rig ready for Godot retargeting ([pack](https://quaternius.com/packs/universalanimationlibrary.html), [UAL 2](https://opengameart.org/content/universal-animation-library-2)) | CMU Motion Capture Database (free use, attribution requested; verify on mocap.cs.cmu.edu); MakeHuman CC0 pose packs (static); Mesh2Motion CC0 clips (licenses vary per asset) | Mixamo raw files in a public repository (redistribution restriction, [Adobe forum](https://community.adobe.com/questions-696/mixamo-animations-licence-game-mods-589976)) |
| Stylized fallback | Quaternius Universal Base Characters, CC0, same skeleton as UAL ([pack](https://quaternius.itch.io/universal-base-characters)) | — | — |
| Transmitters | **Owner-supplied models** (§7) | — | Today's original box transmitter after replacement |
| Pits props | Existing scenery library first, then CC0 packs (field box, starter, fuel jug) | — | — |

Retarget clips with Godot's import-time `BoneMap` and `SkeletonProfileHumanoid`, or in the existing Blender authoring step. No runtime plugin.

Engine references: [LookAtModifier3D (4.7)](https://docs.godotengine.org/en/4.7/classes/class_lookatmodifier3d.html), [IK returns in 4.6](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/).

## 7. Transmitter intake (owner models)

Please provide, per radio:

1. File: `.glb`/`.gltf` preferred; `.blend` or `.fbx` accepted.
2. License or permission that allows redistribution in this public repository, plus author and source URL.
3. Real dimensions (width × height × depth) and units.
4. Separate nodes, if available, for both gimbal sticks, switches, antenna and the neck-strap lug. Pivots at the gimbal centers.
5. Any textures as separate PNG/JPEG files.

Intake steps: record license/SHA-256 in `assets/scenery/population/` manifests; normalize scale and axes in the existing Blender recipe; budget ≤3k triangles close, with Godot auto LOD; add grip markers (`grip_L`, `grip_R`, `thumb_L`, `thumb_R`, `strap`). Layer A bakes the radio into the pilot pose. Layer B attaches it to a hand bone and uses IK for the second hand.

## 8. Steps

| ID | Scope | Acceptance evidence |
| --- | --- | --- |
| SC-HUM-00 | Baseline and survey. Native 1080p captures of today's people at 5/15/40 m and from the pilot view (1440p/4K secondary). Build an RC-field reference photo board for the owner's silhouette overlay. Verify licenses and record them in `docs/research/scenery-investigations/`. Measure free draw/triangle/texture headroom. | Capture set, license table with hashes, budget table. Keep only the images needed for review in the repository. |
| SC-HUM-01 | Layer A head aim for pilots and spectators (§5.1), with the player as the only target. | Shader/generator tests. Captures of a scripted low pass with 1080p frames showing heads following. Pause, step, reset and 1024 s wrap hashes match. Zero draw delta. Frame p95 delta ≤0.1 ms at 1080p. Golden flights unchanged. |
| SC-HUM-02 | Owner transmitters (§7) baked into the pilot pose. Mode/strap variants per D5. | Intake manifest, close captures at 1080p, fitted grip check, triangle budget. |
| SC-HUM-03 | Regenerated characters: 6–8 bases (age, sex, build, skin), CC0 skins, eyebrows/lashes, eyes with a specular highlight, hair, caps, sunglasses and field clothing. One atlas material per character. A shader pass for skin without SSS (wrap diffuse, roughness variation). | Before/after captures at 5/15/40 m and pilot view, owner silhouette overlay, ≤8k triangles close, texture budget within LU-21 limits, fresh-import test. |
| SC-HUM-04 | Animation bake-off: UAL vs CMU vs MakeHuman poses for idle-stand, idle-sit, work-at-table, kneel, chat, holding a transmitter. Retarget to the MPFB game-engine rig. | Clip list with license, retarget error notes and short loops viewed on the target rig. |
| SC-HUM-05 | `CrewActor` prototype outside `app/` (§5.2): one pilot with look-at, hand IK on the radio and manual animation advance. Verify every Godot class in 4.7.2 Compatibility. | Cost per actor (CPU and GPU) at 1080p for 1, 8 and 20 actors. Determinism: identical frames across two runs and across pause/step. |
| SC-HUM-06 | Flight-line pilots bound to AI companions: one pilot per companion, tracking its own aircraft; behavior without companions per D4. Optional stick motion from companion commands (D6). | Companion flight captures, roster add/remove/restart, no change to companion admission or airspace results. |
| SC-HUM-07 | Pits members preparing aircraft (§4.3) beside existing parked aircraft. New placements go through `tools/scenery/place.py`, with person capsules and companion person proxies updated with their owners. | Close pits captures, collision and airspace regression, attention glances during low passes. |
| SC-HUM-08 | Spectator and veranda behaviors with the attention director (§4.2), including crash reaction. | Scripted pass and crash captures; schedule hashes repeat across runs. |
| SC-HUM-09 | Quality tiers (§5.3), skinned range, far fallback and the population budget entry. | Scene budget test per tier, preset switching, no double drawing. |
| SC-HUM-10 | Acceptance: 1080p primary, then 1440p/4K, 720p last. The owner flies the Gate 2 maneuvers and judges realism and distraction. | Owner review notes, frame p95/draws/memory per tier on the owner's machine. |

Order: 00 → 01 and 02 (independent) → 03 → 04 → 05 → 06/07/08 → 09 → 10. Layer A (01–03) is useful even if Layer B is rejected after SC-HUM-05.

Verification rules for every step: scripts parse under `app/test.sh`; drafts live outside `app/` until they parse; the population tests and captures in [the population README](../../tools/scenery/population/README.md#validation) pass; use the [debug bridge](../../tools/debug/README.md) to drive low passes and screenshots; no physics or golden-flight change is expected or allowed.

## 9. Owner decisions

| ID | Question | Recommendation |
| --- | --- | --- |
| D1 | Layer A first, then Layer B; or skinned actors directly? | Layer A first: it is visible quickly and remains the fallback |
| D2 | Realistic MPFB characters or stylized Quaternius characters? | MPFB, consistent with today's field |
| D3 | How many people and where? May the scene budget rise (draws/triangles) for High/Extreme? | Keep 13–18 people; allow up to +20 draws on High/Extreme only |
| D4 | Flight-line pilots when companions are off: idle with radio, watching the player, or removed? | Watching the player with the radio on a strap |
| D5 | Which transmitters, Mode 1 or Mode 2, and how they are held (thumbs, pinch, tray, strap)? | Owner models, Mode 2, thumbs and neck strap |
| D6 | Animate transmitter sticks from companion commands? | Later; visible only in close cameras |
| D7 | Crash reaction: heads only, or also a standing-up / pointing clip? | Heads first; clips after SC-HUM-04 |
| D8 | Regional look and climate (clothing, hats, skin tones) | Owner to describe the home field |
| D9 | Licenses: CC0 only, or also attribution licenses (CMU, CC-BY) with credits? | Allow attribution licenses with exported credits |

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| Uncanny faces at close range | Caps, sunglasses, restrained skin shader, priority on silhouette and motion |
| Heads turning in sync look robotic | Seeded limits, lags and rest offsets; attention variety |
| Skinned actors exceed the CPU/draw budget | SC-HUM-05 measurement gate; Layer A fallback; range culling; one material per actor |
| Distraction from the aircraft | Subtle amplitude; owner review in SC-HUM-10; quality tier off switch |
| License ambiguity in mixed packs | Per-file license and hash records; reject any asset without a verifiable redistributable license |
| Contact shadows do not follow animated poses | Accept for Layer A; for Layer B, measure a pose-aware shadow footprint only if the owner sees the mismatch |
| Placement changes break collision or companion airspace | Placements only through the generator; regression with collision and AFC owners |
