# SC-HUM-07-R1…R6 — Natural hands and arms, natural eyes and brows, varied stances, a logo-free shirt

Status: **implemented and software-verified, 2026-10-25.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). Revises [SC-HUM-07](../SC-HUM-07/README.md) (outfits), [SC-HUM-06](../SC-HUM-06/README.md) (work pose) and the hand part of [SC-HUM-01](../SC-HUM-01/README.md).

Work was done through the [Blender MCP](../../../../tools/blender/README.md) with the `openrc-blender`, `qa-review` and `character-artist` skills. Changes went into the generator, never into the shipped files.

## Review findings (all 11 people, Blender renders of the shipped GLBs)

| People | Defect | Cause |
| --- | --- | --- |
| Standing (4) and workers (3) | Claw hands: knuckles straight, tips bent, fingers spread | The CC0 `standing02` BVH flexes only the outer finger joints |
| Seated veteran | Right hand raised beside the head (a frozen wave) | The CC0 `anrico_sitting03` pose |
| Veteran (pilot and seated) | "MAKE HUMAN" logo on the chest, back and sleeve | The CC0 `male_casualsuit06` texture |
| Pilots | Fingers bent about the wrong axis | SC-HUM-01 curled about local X |

A Blender preview of the merged atlas shows shredded, see-through clothing. This is an artefact, not a defect: Blender blends the atlas alpha, while the game shader cuts alpha only on strand classes. Previews link no alpha.

## Measured rig facts (MPFB 2.0.18 default rig)

The MCP measured these on posed rigs by moving each bone and checking which way the fingertip went relative to the thumb and the wrist:
- A finger flexes about its **local Z** axis: positive on the left hand, negative on the right.
- The thumb tucks toward the index about **local −X** on both hands.
- Rotation about X does not close a finger.

## Changes ([generate_people.py](../../../../tools/scenery/population/generate_people.py), outfit people only; the LU-21 default recipe is unchanged)

| Pose | Hands |
| --- | --- |
| All | `FINGERS_RELAXED` (flexion grows from the index to the little finger) and thumb tucked 15° |
| Pilot | `FINGERS_GRIP` around the transmitter grips; the thumb's first joint keeps its aim at the stick |
| Working | `FINGERS_GRIP`; each wrist aimed 0.16 m ahead of and 0.07 m below where the IK left it, so the palms face the model |
| Seated | Both hands on the thighs: IK to 55 % of the hip-to-knee line, 0.10 m up, with the fingers aimed past the knee |

- **Logo patch.** Outfit option `texture_patches` (in [veteran_cap.json](../../../../tools/scenery/population/outfits/veteran_cap.json)) copies plain fabric from just below each logo box, feathered at the edges, before the texture is resized.
- **Review hook.** `--save-posed <file.blend>` saves the posed rig and meshes before the static bake, so the hands can be reviewed and tuned through the MCP.

All 11 people were regenerated, merged and packaged:
- **Diffuse atlas:** 2720 × 4064 (`1490c907…`), replacing `aa996a41…`.
- **Normal atlas:** unchanged.
- **Triangles:** unchanged (pilots 8,180 and 8,413 exported).

## Verification

| Check | Result |
| --- | --- |
| Blender lineup through MCP (front, hands close-ups, before and after) | No claw hands. Seated hands rest on the thighs. No logo |
| Worker on a table and model stand-in (0.80 m top, model to 1.02 m) | Grip, relaxed and flat presets compared; with the grip, the fingers hold the fuselage sides |
| `capture_population_assets`, native: veteran seated, mechanic working, shirt standing | In the game renderer, hands on thighs, logo-free tee and relaxed standing hands. Motion, pause, reset, wrap and wind pass; overalls have no wind, by design |
| `test_landscape_population_assets`, `test_field_people_gaze`, `test_landscape_population`, `test_scenery_build`, `test_field_projected_shadows` | Pass (disposable app copy, same files as installed) |
| `test_outfits.py` | Pass after the fix below |

**Import regression found and fixed.** Commit `914ba567` ("Add audio assets…") had re-created the people normal atlas `66c9f49e….png.import` with Godot defaults: no VRAM compression, no mipmaps, not a normal map. `test_outfits.py` caught it. The settings from `1335b79d` are restored, with the current uid kept.

## Limits

- Fingers are posed, not contact-solved; tips may touch or enter the model or thigh by a few millimetres.
- Isolated captures show the workers' hands in the air; the table and model are in the field scene.
- The final T12D (another team) needs only the pilot regeneration in [SC-HUM-01](../SC-HUM-01/README.md#limits-and-open-items); the hand presets apply automatically.

## SC-HUM-07-R2 — Faces and licence audit (2026-10-25)

Faces were reviewed in the game renderer: a scratch close-up capture at 1920×1080 of every variant, before and after. Blender previews hide alpha-cut hair, beards and brows, so they are not used to judge faces.

| Person | Defect | Change ([outfits](../../../../tools/scenery/population/outfits/)) |
| --- | --- | --- |
| Veteran (pilot, seated) | A `short03` fringe came out under the fedora and covered one eye | `short01` stays under the hat |
| Bearded spectator | A jet-black beard on light-brown hair, with harsh spikes | Brown CC0 `culturalibre_faun_beard`, decimated to 0.1 (7,681 triangles, below the previous 7,743) |
| Bearded spectator, woman | Eyebrows read as thin pen lines | `eyebrow012` and `eyebrow010` (fuller, textured CC0) |

Rejected: `mindfront_eyebrows_*`. They are untextured strand geometry, so the merge would class them as rigid (class 4) and they would not turn with the head.

**Licence audit of every outfit asset.**
- The `.mhclo` headers of `wdg_scruffy_beard`, `frankyaye_glasses_library_male` and `kwnet_at_optical_glasses` say AGPL3. `cortu_cargo_pants` has no licence line.
- The official asset-pack catalogs (`bodyparts05`, `glasses01`, `pants01`) list all four as CC0. The packs were released as `*_cc0.zip`, so the catalog is the licence of record.
- `HUMAN_SOURCES.json` claimed "'license CC0' in each used .mhclo"; it now records the discrepancy.
- The AGPL-headed beard is no longer used.

**Install check.** While installing, the two new atlas `.import` files were first assigned the wrong roles: the diffuse atlas got normal-map settings, and the skin rendered yellow in the face capture. That was fixed before installing. `test_outfits.py` now reads each GLB's material roles and requires the normal atlas to import as a normal map and the diffuse atlas not to (checked by mutation).

**Verification.** All 11 people were regenerated, merged and packaged.
- Atlases: diffuse `64ff2b45…`, normal `2bf58ece…`.
- Game face captures, before and after: both eyes are visible under the fedora, the beard matches the hair, and the eyebrows are fuller.
- The same five Godot tests pass, and `test_outfits.py` passes 7 of 7.

## SC-HUM-07-R3 — Varied standing stances (2026-10-25)

All four standing spectators used the CC0 `standing02` pose, and read as clones. Through the MCP, the CC0 MakeHuman poses (`standing01`–`06`, sitting variants) were rendered on the real outfits:

| Pose | Verdict |
| --- | --- |
| `standing04`, hand on hip | **Bearded spectator** (`casual_shirt`) |
| `standing03`, weight on one leg | **Woman** (`woman_tee`) |
| `standing02` | Kept for the jacket and overalls spectators |
| `standing01` | Rejected: frozen mid-stride |
| `standing05` | Rejected: pointing arm |
| `standing06` | Rejected: foot raised on a missing prop |
| `callharvey3d_sittinglegscrossed` | Rejected: leans back on a backrest the field seats lack |

The poses are set by the outfit option `pose_files`; the work pose stays on `standing02`.

**Envelope.** A foot forward makes these two people 0.50–0.51 m deep.
- `person_standing` depth goes from 0.36 to 0.52 m. The collision capsule radius stays 0.325 m (the larger of the 0.65 m width and the depth, halved).
- `test_scenery_build`'s lower bound on the drawn size had required every variant to fill 75 % of the envelope on each axis. It now requires 75 % in height and 60 % in plan, because the envelope is the largest variant and slim standing people are 0.32–0.33 m deep.

**Verification.**
- The pipeline is deterministic: only the two changed GLBs differ, and both atlases are byte-identical.
- `capture_population_assets` (native) for three standing variants: motion, pause, reset, wrap and wind pass.
- `test_landscape_population(_assets)`, `test_field_people_gaze`, `test_scenery_build`, `test_field_projected_shadows`, `test_landscape_collision_support`, `test_outfits.py` and `place.py --check` pass.

## SC-HUM-07-R4 — Relaxed arms in `standing02` (2026-10-25)

The MCP measured the jacket and overalls spectators. The CC0 `standing02` pose holds the arms out in an A: wrists 0.29–0.32 m from the centre, against shoulders at 0.17 m, and 0.07–0.10 m ahead of the body.

**Change.** [generate_people.py](../../../../tools/scenery/population/generate_people.py) adds an IK for outfit people in `standing02`:
- each wrist goes `ARM_HANG_OUT_M` (0.055 m) outside its shoulder joint and `ARM_HANG_AHEAD_M` (0.03 m) ahead of the hip, at the wrist's own height;
- the pole sits 0.60 m behind the shoulder.

A first pole at 0.10 m out and 0.45 m behind flared the overalls' elbows outward, so it was moved directly behind the shoulder. The working pose, which also starts from `standing02`, keeps its own IK.

**Verification.**
- Only the two `standing02` GLBs change; both atlases are byte-identical.
- Native `capture_population_assets` of all four standing variants: arms hang beside the thighs, and motion, pause, reset, wrap and wind pass (the overalls have no wind, by design).
- The six scenery and people tests and `test_outfits.py` pass.

## SC-HUM-07-R5 — Natural eyes and eyebrows; relaxed arms in `standing03` (2026-10-25)

**Defects at 1080p close-ups (game renderer).**
- Every person had the default MakeHuman `brown_eye` iris, which reads blood-red.
- The eyebrows were solid black strokes for any hair colour: their textures are near black in RGB (7–15 of 255), and only the alpha carries the shape.

**Changes ([generate_people.py](../../../../tools/scenery/population/generate_people.py), outfit people only).**
- Eyebrow textures take the mean colour of the person's hair texture × `EYEBROW_FROM_HAIR` (0.8), keeping their alpha: brown brows for brown hair, near-black for black hair.
- The outfit option `eye_texture` names a CC0 iris from `eyes/materials` (all "explicitly released as CC0 in September 2020"):

| Outfit | Iris |
| --- | --- |
| Pilot, polo shirt | Light brown |
| Veteran | Grey |
| Bearded spectator | Green |
| Jacket and mechanic | `mindfront_brown_eye_02` |
| Woman | Blue |

- **Arms.** The MCP measured the woman's `standing03` wrists at 0.13–0.15 m outside the shoulders. `ARM_HANG_POSES` now covers `standing02` and `standing03`. `standing04` keeps its hand on the hip.

**Verification.**
- Diffuse atlas `f40b9e60…`; the normal atlas is unchanged. A GLB-role check confirms each atlas imports in its role.
- Game face captures, before and after: natural iris colours and brows that match the hair.
- Native `capture_population_assets` for the woman (standing), the veteran (seated) and the polo pilot: the woman's arms hang beside her hips; motion, pause, reset, wrap and wind pass.
- `test_landscape_population(_assets)`, `test_field_people_gaze`, `test_scenery_build`, `test_field_projected_shadows` and `test_outfits.py` pass.

## SC-HUM-07-R6 — The two flight-line pilots stand differently (2026-10-25)

The flight-line pilots are the people seen most in flight ([SC-HUM-00 census](../SC-HUM-00/README.md)), and both stood on the same `standing02` legs.

**Change.** The veteran now uses the CC0 `standing03` pose (weight on one leg) under the unchanged transmitter hold, set by outfit `pose_files: {"pilot": "standing03"}`. The two candidates were compared through MCP renders; the radio grip is kept.

**Envelope.** The veteran is 0.556 m deep, so `person_pilot` depth goes from 0.47 to 0.57 m. The collision capsule radius stays 0.335 m (the larger of the 0.67 m width and the depth, halved).

**Verification.**
- Only `veteran_cap_pilot.glb` changes; the atlases are identical.
- Native capture: both pilots grip the radio, and motion, pause, reset, wrap and wind pass.
- The six scenery and people tests and `test_outfits.py` pass.

**Tried and not shipped: alpha-to-coverage hairlines.** `render_mode alpha_to_coverage` with `ALPHA_ANTIALIASING_EDGE` changed 0 pixels in the 1080p face captures on this VM (llvmpipe under Xvfb). Whether MSAA or Compatibility ignores it here is unknown, so the change cannot be verified and was not kept. The hard hairline edge is visible only at about 1 m.
