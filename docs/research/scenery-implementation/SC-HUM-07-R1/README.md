# SC-HUM-07-R1 — Natural hands and a logo-free shirt

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
