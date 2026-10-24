# SC-HUM-01 — Pilots hold the owner's transmitter

Status: **implemented with the owner's draft Radiolink T12D, 2026-10-24.** Owner: Scenery and field life. Plan: [field people plan](../../../plans/field-people.md). The final model replaces the draft in place and needs only a regeneration.

## What changed

| Item | Before | Now |
| --- | --- | --- |
| Transmitter | Project-made dark box with two cylinder sticks (548 triangles) | Owner's [Radiolink T12D](../../../../assets/source-deliveries/radiolink-t12d/README.md), reduced to 1,139 triangles in 13 colour parts plus its screen image |
| Hold | Box at the waist; open hands below it | Face up 35° toward the eyes; wrists outside the rear grips; hands aimed up the grips; fingers curled behind; thumbs aimed at the stick tips |
| Pilot depth | 0.452 m (polo), 0.458 m (cap) | 0.465 m for both |
| `person_pilot` envelope | 0.67 × 1.78 × 0.45 m | 0.67 × 1.78 × **0.47** m, so the pilots keep their natural height (1.72 and 1.75 m) instead of shrinking 3 % |
| Draws per pilot | 1 | 1. The radio is part of the merged mesh and shared atlas |

The collision capsule radius comes from the larger of width and depth (0.67 m), so it is unchanged. Scenery footprint checks, collision tests and companion admission tests pass.

## Recipe

[generate_people.py](../../../../tools/scenery/population/generate_people.py), `--pose pilot`, function `import_transmitter`. The default model is the delivery; `--transmitter` overrides it.

1. Append the parts under `T12D_root` from the `.blend`. Drop parts under 10 mm (screws, LEDs, printed marks), text objects and the studio. Remove bevel and weighted-normal modifiers.
2. Merge coplanar faces of each part (5°, materials kept). Share an 800-triangle budget by surface area, with at least 8 triangles per part. Then collapse. A single collapse of the joined radio tore the face panel; the area split keeps the housing outline (Blender A/B close-ups).
3. Rename the materials `RC_Transmitter_*` and separate them by material. [merge_people_atlas.py](../../../../tools/scenery/population/merge_people_atlas.py) gives the radio's colours swatches in the shared atlas and the screen its own region. Every part, screen included, is class 4: rigid, never in the head rig.
4. Derive the hold from the model: the reference is the midpoint of `Stick_Izq_eje` and `Stick_Der_eje`. The hand targets are fixed points in the radio frame (`TRANSMITTER_*` constants). Keep those three names in the final model.

The diffuse atlas stays 2720 × 4064 (`aa996a41…`, which replaces `1d43206c…`). The normal atlas is unchanged (`66c9f49e…`). All 11 people GLBs were re-merged because their atlas UVs moved. The nine non-pilot sources were not regenerated.

## Verification

Native and headless runs used a disposable app copy with the new files, then the same files were installed byte for byte.

| Check | Result |
| --- | --- |
| `capture_population_assets` (native, both pilots) | 1 draw at 5/15/40/120 m. Automatic LOD 8,040 → 4,020 → 2,008 primitives (polo). Motion, pause, reset, wrap, wind change, wind repeat and calm restore all pass. At 5 m the white T12D reads clearly between the hands. |
| `test_landscape_population_assets` | Pass. Pilots carry a 1,200-triangle transmitter allowance over the 8,000-triangle person cap (polo 8,062, cap 8,296 counted) |
| `test_field_people_gaze` | Pass. Now requires every pilot to hold transmitter vertices that never move with the head |
| `test_landscape_population`, `test_scenery_build`, `test_landscape_collision_support`, `test_field_projected_shadows` | Pass. Population source triangles 372,246 of the 380,000 budget |
| `test_outfits.py` | Pass. The runtime manifest matches the shipped files |

Blender reviews (side, front, hands and over-the-shoulder close-ups) were checked during tuning. Per the repository image rule, they are not committed.

## Limits and open items

- **Draft model.** Regenerate when the final T12D arrives: two pilot generations, then the shared merge and packaging (see [the tool README](../../../../tools/scenery/population/README.md)).
- **Licence.** The model is owner-authored; the owner still has to confirm its redistribution terms (recorded in `HUMAN_SOURCES.json`).
- **Grip.** Thumbs are aimed at the sticks, not placed by contact, and finger tips are approximate. Fine at field range; visible in a close-up.
- **Not modelled.** No neck strap. No stick or switch motion; the pilots are static poses (moving sticks is Layer B or SC-HUM-12 territory). No LED emission, chrome or metal: the merged material is matte, roughness at least 0.6.
- **Owner review (SC-HUM-09).** The hold angle, the radio size in hand and the hand pose.
