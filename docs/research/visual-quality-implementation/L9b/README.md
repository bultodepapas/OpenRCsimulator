# L9b — Club grass airfield surface review

2026-10-20. Native Godot 4.7.2 Compatibility/OpenGL captures at 1280 × 720 on an RTX 3090. This record covers presentation only; it does not qualify ground physics or owner flight readability.

## Field references and asset choice

- [FLYRC's field description](https://flyrc.org/home/field-description/) documents a 100 × 300 ft grass runway, four pilot boxes, safety fences and a maintained grass field. This is the closest layout precedent for the existing Club field's 100 × 12 m grass runway and pit-side barrier.
- [AMOS field](https://amosrc.com/amos-field/) documents a separate 15 ft parallel taxiway beside a 60 × 725 ft main runway, with gravel parking and a separate helicopter pad. Its taxiway relationship informs two short pilot-side grass strips, interrupted at the Club field's existing rotor pad.
- The [SCCMAS training manual](https://www.sccmas.org/pdf/Training/trainingManual.pdf) describes a 520 × 60 ft runway with mown grass overflow and paved taxiway connections. Its operating rules distinguish runway/taxiway movement from walking to pilot stations. The Club implementation keeps the existing pedestrian routes behind the flightline and does not draw a pedestrian crossing on the runway.
- The existing bundled [ambientCG Grass001 maps](../../../../app/assets/landscape/rc-ground/manifest.json) now provide close-view colour, normal and roughness detail in Club Home and flight. They were already sourced as CC0; no duplicate grass asset was downloaded. [Poly Haven's CC0 license](https://polyhaven.com/license) and its [Dirt texture](https://polyhaven.com/a/dirt) were reviewed for the initial grass pass.

Club and manual imagery was used as visual reference, not copied into the project. The mowing colours and widths below are art estimates adapted to the existing validated field, not measurements or club safety standards.

## Render change

`app/render/field.gd` enables the Club-only ground detail and binds the retained grass maps. `app/render/ground.gdshader` brings the previously luminous runway/rotor pad closer to the surrounding turf, narrows their mowing contrast, and adds a soft maintained-grass collar. Two approximately 2.5 m grass taxi strips sit on the pilot side, break around the rotor pad, and have short runway-side end links. The existing worn pedestrian tracks use smaller irregular sections and a grass-toned surface in `app/scenery/ground_features.gd`.

The shader changes colour and close-view normals only. The default field JSON, validated surface rectangles, ground contact, obstacle proxies and flight laws are unchanged. Green paradise and other fields do not enable the Club detail.

## Visual evidence

| View | Before | After |
| --- | --- | --- |
| Pilot, facing flight area | [baseline](before-pilot.png) | [current](after-pilot.png) |
| Runway threshold | [baseline](before-threshold.png) | [close grass/taxi view](after-close.png) |
| Raised inspection | — | [runway and taxi overview](after-aerial.png) |
| Scripted aircraft takeoff, idle | — | [ground close-up](after-aircraft-close.png), [wide flightline](after-runway-wide.png) |

The pilot and close views retain visible grass grain; the aerial view shows the runway, pilot-side maintained band, fence and pad as a coherent layout. The final taxi tone was reduced after an intermediate capture read as a dark trench.

## Checks and limits

`test_field_surfaces.gd` passed 19 checks; `test_scenery_loader.gd`, `test_scenery_build.gd`, `test_field_integration.gd`, and `test_landscapes.gd` passed (the last reported 49 checks). The native scene capture completed for pilot, close, threshold and aerial views without shader errors. A subsequent scripted runway scenario completed 51 frames across five views after a transient `flight_session.gd` preload error during concurrent edits. The known unsupported maple wind-material warning appeared in captures. These software checks do not establish owner flight readability or physical realism.

## Stone, flower and floor follow-up

The [asset manifest](../../../../app/assets/landscape/airfield_detail/manifest.json) records exact source URLs, CC0 evidence and checksums. `tools/ground/import_airfield_detail.py` re-downloads unmodified [Poly Haven Empodium flowers](https://polyhaven.com/a/flower_empodium), [river pebbles](https://polyhaven.com/a/river_small_rocks) and [sparse grass](https://polyhaven.com/a/sparse_grass), and extracts three unmodified rock meshes from the existing CC0 [Quaternius Nature MegaKit](https://quaternius.itch.io/stylized-nature-megakit). No new meshes were modelled. The flower shader binds Poly Haven's separate alpha map because its supplied JPEG glTF material does not contain an alpha channel.

Four source rocks and four scanned wildflower accents sit in the pavilion's existing planted verge. MultiMesh keeps them to five batches and 4,482 source triangles at high quality; balanced and low reduce the instance count. Flower and stone visibility ends at 85 and 110 m respectively. The gravel parking strip uses a tiled river-pebble scan; the worn walking tread uses the sparse-grass scan. Both textures blend into the existing colour geometry and use mip filtering. All nodes are visual, with no bodies, collision shapes or changes to field data.

Native captures: [pavilion and trail](detail-club-close.png), [flowers](detail-flower-close.png), [gravel parking](detail-carpark-close.png), and [runway aerial](detail-runway-aerial.png). [View counters](detail-views.json) show the unchanged pilot-facing runway at 101 draws and 259,719 primitives versus the prior capture; the pavilion-facing view rises from 161 to 168 draws and 311,820 to 314,825 primitives, including other concurrently updated scenery. The separate runway aerial remains at 102 draws and 239,936 primitives. Capture command: `Godot_v4.7.2-stable_win64_console.exe --path app --rendering-driver opengl3 --resolution 1280x720 --script res://scenery/capture_views.gd -- --out=<empty-directory> --views=pilot_north,pilot_south,club_close,flower_close,carpark_close,runway_aerial`.

`test_field_surfaces.gd` passed 19 checks; `test_landscapes.gd` passed 49; `test_field_integration.gd` passed. `test_scenery_build.gd` passed the 725,000 triangle gate (723,213 in the latest run), but its cold-build time gate remained over 800 ms (1,076.5 ms). The airfield detail stage measured 0.15 ms in that run; the shared scene build includes other active scenery changes. The known maple tree wind-material warning remains.
