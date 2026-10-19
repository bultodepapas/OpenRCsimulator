# SUN-02b, SUN-05b, SUN-06, SUN-09: veil colour, real-flight checks, eyewear, skyline

2026-10-19. Plan: [sun.md](../../../plans/sun.md). Follows [SUN-01…05](../SUN-01-05/README.md); environment as there (Linux, Xvfb, Mesa llvmpipe, Godot 4.7.2 Compatibility). Software results were run on a clean copy of committed HEAD plus these files, because the shared tree held another track's uncommitted glow edits that fail to compile.

## SUN-02b: the veil never darkens

The veil is an alpha mix toward a target colour. Mixing toward the disc's colour darkened any sky brighter than the disc in some channel, as at golden hour: straylight only adds light. This was found by the moon track (FW-MOON-08).

The target colour is now the disc's, raised per channel to 1.1 × the sky the shader draws 1° from the sun (gradient, the L1a halo and the aureole core; `SunOptics.veil_colour`, `SkyMirror.background_radiance`). The moon track's ALBEDO encoding fix and its disc exclusion (no veil on sky pixels inside the source's own disc) went in at the same time.

| Golden hour, 3° fixture without the aircraft | Before | After |
| --- | ---: | ---: |
| Sky pixels darker with glare than without (> 2 levels) | 195 (max 9.1 levels) | 0 (max 1.4) |

Calibrated Day pixels are unchanged: the disc outshines its surroundings in every channel there, so retention is 0.349 / 0.519 at 1° / 3° and the crossing keeps 0.099, as in SUN-01…05. Golden hour at 3° keeps 0.759 (model 0.735). [Darkening](golden-veil-darkening.json), [golden hour](golden-glare-contrast.json), [Day](day-glare-contrast.json); `glare_contrast.py` now fails on any darkened pixel outside the crossing's patch.

## SUN-05b: inside the real flight scene

`app/tests/test_sun_flight.gd` drives `main.gd`, not the capture harness: **22 checks, 0 failed**, no engine errors.

- The glare node is built with the world, processed after Main (it sees each frame's `World.update`), and its afterimage layer sits under every interface layer.
- The pilot's eye on the sun bleaches it on simulation time; the patch stays on screen after looking away; a held clock holds it.
- Chase is a lens; the eye recovers meanwhile; a restart rests it; strength 0 draws and bleaches nothing.
- The skyline and the eyewear checks listed below.

## SUN-06: eyewear

`--pilot-eyewear=none|cap|sunglasses|cap+sunglasses` (or `OPENRC_PILOT_EYEWEAR`; default none; eye views only).

- **Cap.** A brim shades the eye from a source more than 25° above the line of sight (a 7 cm brim 3 cm above the eye gives about 23°) and moves with the head.
- **Sunglasses.** Light-brown lenses pass 25 %: the veil ratio is unchanged and the bleaching dose falls fourfold.

Real flight:
- A cap removes both veil and dose for a 45° sun while the pilot looks 35° below it.
- Looking at the sun, a cap does not help.
- Sunglasses cut the first frames' bleaching by more than half.

No interface preference yet (UI owner).

## SUN-09: the field's skyline

`app/render/sun/skyline.gd` gives the highest elevation that static scenery reaches per 0.5° of azimuth, as seen from the pilot's eye. Below it the sun neither bleaches nor veils off screen; on screen the depth buffer still decides, and the geometric horizon always applies. Its sources:
- Trees, people and cars: the crown tops of MultiMesh instances.
- Merged scenery cells and ridges: the triangle edges of meshes. Each edge raises the bins it spans to its lower end; with corners alone, flat walls left gaps.
- Skipped: SubViewport subtrees (separate worlds, such as the projected-shadow silhouettes) and the 40 km terrain sheet. Skipping the terrain lowers the default field's skyline by at most 1° at 45–60° and 300° azimuth: a little more glare there, never less.

It builds incrementally, 600 samples per frame, which is a fixed amount of work, so captures and replays finish it on the same frame.

**Default field** ([profile](skyline-default-field.json)):
- 351 of 360 degrees have scenery; median 2.4°, highest 20.2° (the clubhouse behind the pilot).
- 500 frames, 0.45–0.61 s of CPU in total on this VM, worst frame 8.7–15 ms (reading a merged cell's arrays once).

**Tests.**
- `test_sun_skyline.gd`: 14 checks under `opengl3`. Headless gives 11, because the dummy renderer keeps no MultiMesh data.
- In flight, a sun 10° up behind the clubhouse is hidden, one at 30° is clear, and lens views keep the constant 3° prior.

## Software

| Test | Result |
| --- | --- |
| `test_sun_optics.gd` | 112 checks, 0 failed |
| `test_sun_skyline.gd` | 14 (opengl3) / 11 (headless), 0 failed |
| `test_sun_flight.gd` | 22 checks, 0 failed |
| `test_world_moon_glare.gd` (moon track's guard of its hunks) | 20 checks, 0 failed |
| sky render, atmosphere, world sky, landscape lighting, moon sky and aureole, camera views | all pass |

## Limits

- The skyline is computed for the eye where the view is built (the pilot station). Lens views keep the constant prior.
- The aircraft and other moving objects are not part of the skyline. On screen the depth buffer covers them.
- Gaps between crowns are open: foliage that passes some light is treated as either fully blocking or open.
- The worst skyline frame (one array read, up to 15 ms on this VM) is not yet split.
