# L9b — Club grass airfield surface review

## L9b-R1: finer Club turf

2026-11-09. The [supplied ground-realism audit](ground-audit-2026-11-09.md)
and concept image suggested finer turf and coordinated ground treatments. A
matched native comparison isolated an oversized base pattern: disabling macro
variation left the small pale patches; reducing the generated texture's world
tile from 6 m to 1.5 m made that pattern finer. This is an art estimate, not a
measured grass dimension. The audit's reported C-shaped mark was not localized
and is not claimed fixed.

The Club-only override lives in `field.gd`, before surface and RC-track material
clones are created. Fallback grass already inherits it; the lake bank now copies
the same scale. Shared defaults, photographic map scale, macro/dry variation,
mowing, surface geometry, contact data and flight physics retain their previous
behavior. No assets, texture reads, meshes or instances were added.

Native evidence used Godot `4.8.beta2.official.cafc17a19`, Windows NVIDIA RTX 3090,
Compatibility/OpenGL, 1920 × 1080 and High detail. Seven matched views cover the
normal pilot, reverse runway, threshold, path, lake, 200 m target diagnostic and
raised ground; all retain identical draw/primitive counts. A separate close bank
pair checks the sampling scale at the grass/soil transition. The existing dark
walking tread and broad mowing bands remain visible. The track's material-copy
contract is tested; these flight-world captures do not establish RC-verge visual
acceptance.

Two matched 48-frame camera translations cover the pilot and low threshold views.
An observational planar reprojection of 47 adjacent pairs per view measured RGB
RMS of 1.630 → 1.630 and 2.452 → 2.454 on a 0–255 scale. This shows no substantial
increase in that bounded residual; it is not perceptual shimmer acceptance. The
legacy 1280 × 720 surface fixture retains 30.1% runway-edge Weber contrast at
100 m, above its 5% floor; that fixture does not qualify 1080p by itself.

Checked tests passed: field surfaces (21), near grass (52), grass material (39),
lake world (53), and RC ground material (zero failures). Updated scripts parse.
The initial render failed on a concurrent countryside shader edit; comparisons
then used an isolated source snapshot based on `f7b58bd830d4a5eb78901d00514ce1fc18286477`
with this change, restoring unrelated dirty countryside sources to that commit.
One incomplete snapshot omitted the source `failures/` directory; the lake test
passed after restoring it. These failed attempts remain in the raw check logs.

[Source identities and reduced evidence](ground-scale-2026-11-09.json) identify
the successful runs. Raw images, reports, checked logs and the observational
reducer remain under ignored `tmp/ground-realism/`; no new images are committed.
[Capture instructions](../../../../tools/ground/README.md#l9b-r1-club-turf-scale-review)
own the commands. Independent owner review, other renderers/hardware, required CI
and the shared whole-flight frame-time/sim-rate gates remain open.

## L9b-R2: worn-path color and filtering

2026-11-09. The native `entry_path` control showed a dark tread with flat lane
and segment bands. Disabling only `use_photo_worn` isolated the scan's dark cast
from the underlying vertex-color steps. Worn tracks now share colors at lane
and segment joints, grading the existing shoulder toward the field palette.
Corner colors follow the mesh emitter's ordinary, mirrored and degenerate-face
ordering. This applies to authored worn tracks in custom fields as well as Club;
the photographic binding remains Club-only.

The retained sparse-grass photograph supplies scalar value variation around the
authored path color, using measured means in the active shader color domain.
Clamping means this does not guarantee equal average luminance. Scalar modulation
avoids amplifying the photograph's small blue-channel mean. The source JPEG is
unchanged. Its import now generates real mipmaps, checked on the bound texture;
the worn sampler also uses anisotropic mip filtering at low viewing angles.
The mip chain adds texture storage. No mesh, instance, batch or texture asset was
added.

Godot `4.8.beta2.official.cafc17a19`, Windows RTX 3090 Compatibility/OpenGL,
1920 × 1080, High detail: matched path, reverse pilot and parking views retain
identical draw/primitive counts. The path's dark cast and triangular bands are
reduced in sun and pavilion shade. Its opaque perimeter remains visibly distinct
from the finer surrounding turf; this is a softer tonal transition, not seamless
ground blending. Photo-disabled controls retain the continuous color profile.
Camera-translation sequences are retained for review; their PNG/readback timings
do not qualify performance or perceptual shimmer.

Focused tests passed: LU-18 routes/material boundaries (37), gravel (7, including
actual mipmaps), and LU-08 ground checks. Eight old/new geometry comparisons cover
the authored access/worn routes and a U-turn with ordinary/mirrored transforms:
positions/normals are byte-identical, and the dirt track's colors are unchanged.
The route tests retain the collision identity, low lift, existing cell surfaces
and obstacle clearances. A collapsed-corner regression guards corner identity
rather than inferring it from position.

[Source identities and results](worn-paths-2026-11-09.json) bind the successful
runs. Raw evidence is in ignored `tmp/path-integration/`, using the prior reviewed
ground snapshot plus this change; concurrent tractor/shadow edits were excluded.
Asset/import-cache inputs remain shared junctions, and the texture reimport was
serialized. [Capture controls](../../../../tools/ground/README.md#l9b-r2-worn-path-review)
own reproduction. Independent art/flight acceptance, required CI, other
renderers/hardware and shared whole-flight performance gates remain open.

## Original surface review

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
