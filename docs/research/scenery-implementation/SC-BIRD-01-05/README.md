# SC-BIRD-01…05 · First bird slice: vulture kettle, red kite, barn swallows

2026-10-24 · Evidence for the [birds plan](../../../plans/birds-sky-life.md) (first slice). **Correction:** the colour tables of this slice never reached the shader, so these birds rendered black (fog-tinted); fixed and tested in [SC-BIRD-08](../SC-BIRD-08/README.md#correction-to-sc-bird-0105). The second slice also replaced the per-group atlas mesh and the shader-side activity threshold described below. Software evidence on the Linux VM's llvmpipe; not target-hardware performance and not the owner's Gate SC judgement.

## What was built

| Part | Where | Notes |
| --- | --- | --- |
| Data `openrc-birds v1` | [birds.json](../../../../app/data/scenery/birds/birds.json) | 3 species, 3 flocks; physical numbers carry `{value, unit, kind, source}` from [SC-BIRD-00](../../scenery-investigations/SC-BIRD-00/README.md) |
| Validator | [bird_data.gd](../../../../app/scenery/birds/bird_data.gd) | Units, kinds, sources, ranges, tail shapes, 1024 s divisibility, shader slot limits; invalid data builds no birds |
| Circuits | [bird_tracks.gd](../../../../app/scenery/birds/bird_tracks.gd) | Arc-line motifs repeated with rotational symmetry, so they close exactly; tangent joints; period rescaled (≤ 8 %) to 1024/k s; float64 reference and float32 shader tables |
| Silhouettes | [bird_planform.gd](../../../../app/scenery/birds/bird_planform.gd) | True-size planforms with fingers, forked/square tails, a keel and a leading-edge strip; rig weights in vertex colour. 34 / 31 / 19 triangles |
| Shader | [sky_birds.gdshader](../../../../app/scenery/birds/sky_birds.gdshader) | Track evaluation, heading and bank from finite differences (bank = atan(a_lat/g), ~1 s roll-in), arm/hand flap with lag and upstroke fold, tail twist with bank, two-tone underside, daylight activity |
| Scene | [birds.gd](../../../../app/scenery/birds.gd), hooks in [scenery.gd](../../../../app/scenery/scenery.gd) | Two MultiMeshes (`Birds_soaring`, `Birds_small`); activity updated on every committed lighting change |

The flocks:

| Flock | Birds | Circuit (period) | Measured basis |
| --- | --- | --- | --- |
| Griffon vulture kettle, thermal A 800 m NW (`birds_watch` view) | 9 | 5.5 turns of 12.8 s at radius 17/22/27 m climbing 0.81 m/s, glide 788 m at 13.7 m/s to thermal B, and back (256 s) | 578 CC0 GPS turns: 22 m (16–30), 12.9 s, 0.81 m/s; glides 13–14 m/s |
| Red kite, east paddock outside the flight box | 2 | 3 × (glides, 2 circling turns at r 11 m, 6.4 m/s, climb 19 m) (204.8 s) | 2,169 CC0 GPS circles: 11 m, 11 s, 6.4 m/s, 0.92 m/s |
| Barn swallows, mown grass west of the flight line | 10 | 5 × (straights and 5–12 m turns at 8–10 m/s, 0.35–3.3 m high) (32 s); rotated and mirrored per bird | 47 CC0 3D tracks: 9.5 ± 2.7 m/s, turn radius 5.1 ± 3.0 m, height 0.43 ± 0.78 m, max 4.1 m |

## Checks

| Check | Result |
| --- | --- |
| [test_birds.gd](../../../../app/tests/test_birds.gd) | 167 checks pass: 20 rejected mutations; every circuit closes, is tangent at every joint (sampled on both sides in float64) and repeats every 1024 s; speed, circling bank, radius, time per turn and climb inside the measured limits; every bird's world height (instance offsets included) inside its limits; no bird within 30 m of the pilot; soaring birds outside the flight box; swallows ≥ 30 m from the runway centreline and short of the hedge; half-float-exact offsets and hashes; silhouettes true-span and symmetric, and the shader's wing rig moves exactly the wing; the groups' float32 shader tables within 5 cm of the float64 tracks over 0–2048 s; 905 primitives and 2 draws (budget 1,000 / 2); culling boxes hold every bird; activity from real time-of-day snapshots (night, dawn: none; noon: all); byte-identical rebuild including every shader table |
| [check_birds.py](../../../../tools/scenery/check_birds.py) at 1920×1080, Compatibility, `sim_clock` 20 s | For the earliest and latest bird of each flock, the bird is drawn 2.1–4.9 px from the CPU prediction at a 60 px requested span (blob extents 28–51 px: oblique and banked). In-process repeat and a second process are byte-identical |
| Regressions | `test_time_of_day_scenery_update`, `test_scenery_build`, `test_landscape_scenery_grass_mask`, `test_soundscape`, `test_wildlife` pass; a 3 s headless flight with birds on runs |
| GDScript warnings | No errors; no warnings in the new bird scripts |

Reproduce: `"$(app/tests/visual-env.sh)" tools/scenery/check_birds.py --app app --godot "$(app/get-godot.sh)" --out tmp/<new>` (about 3 min) and `python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_birds.gd`. The capture writes `summary.json` with image and source hashes; images stay in `tmp/`.

## Independent review

A read-only review (Good Enemy role) confirmed the track, attitude, mirroring and rig math and found these defects, all fixed before this record:

| Finding | Fix | Check |
| --- | --- | --- |
| Time-of-day snapshots clamp `sun_elevation_deg` to ≥ 0.05° for the sky, so 2 of 10 swallows flew at night | Read `solar.elevation_deg`, as flight audio does | Real `night`/`dawn`/`noon` preset snapshots |
| A spread tail wider than the shoulders was flapped by the wing rig | Wing rig only where `COLOR.b == 0` | Planform part labels: the rig moves exactly the wing |
| A non-boolean instance flag crashed the validator | Type-checked | Mutation |
| A segment given as a duration bypassed the speed limit; a non-numeric duration crashed | One speed/duration/climb-rate check for both forms | Three mutations |
| Heights ignored the per-bird height spread (kite minimum 31.8 m < 33 m) | Heights checked per instance; kite base 37 m | Per-bird height checks |
| Shader-table test packed per flock, below 1024 s; joint and determinism checks proved less than their labels | Group packing, 0–2048 s; joints sampled on both sides; signature includes every uniform | — |
| Suspected: 16-bit MultiMesh custom data in Compatibility would round large offsets | Offsets are whole half-seconds and hashes multiples of 1/1024 (exact in a half float) | Half-float check; capture of each flock's latest bird |

The reviewer's numpy float32 emulation of `track_pos()` and the bank differences over 0–2048 s gave at most 1.7 mm and 0.009°; that script was not kept, so it is recorded here as review evidence only.

## Observations

- From the pilot's eye the soaring birds are seen 5–10° from below, so level wings are often edge-on: a thin line with the dihedral and tip curl, as distant soaring birds look. As they circle and bank they show their upper or lower surface in turn. MSAA 2× breaks a sub-pixel edge-on wing into dashes; the keel and the leading-edge strip keep a body visible.
- Through the 20.7° `birds_watch` lens the kettle reads as seven vultures wheeling at different heights over the hazy ridges.
- The first 3 s headless flight with birds printed "4 ObjectDB instances were leaked at exit"; the eleven later flights (six with birds, five without) printed none. Later identified as Ogg audio playback alive at exit (the menu accept cue), not the birds ([SC-BIRD-08](../SC-BIRD-08/README.md#observations-and-limits)).

## Limits and open work

- Not checked: the web export (vertex texture fetch is not used in this slice), Windows native, target hardware cost, the owner's readability judgement, sun-veil interaction.
- Kettles do not yet drift with the mean wind; no exclusion cone around the model's line of sight (SC-BIRD-09); no seasons (SC-BIRD-08); no audio coupling (SC-BIRD-10).
- Placements are for the default field; other fields use the same origins.
