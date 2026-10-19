# Sun: realistic disc, glare and dazzle

2026-10-19 · Revision 1 · **Implementation plan** · Step prefix: **SUN**

**Status:** 2026-10-19: SUN-00…05, -02b, -05b, -06 (command line) and -09 delivered (software and native capture evidence on llvmpipe); SUN-07 moon glare is FW-MOON-08's (built on `SunGlare.source()`); SUN-08 owner flight acceptance and the eyewear preference (SUN-D1) are open. Evidence: [SUN-00 audit and sources](../research/sun/SUN-00/README.md), [SUN-01…05 results](../research/sun/SUN-01-05/README.md), [SUN-02b, -05b, -06, -09](../research/sun/SUN-02b-06-09/README.md).

**Owner:** Visual quality and landscape (the sun's look), with LU (`sun_glare.*` began as LU-04) and Field world (shared `sky.gdshader`, `atmosphere.gd`; moon glare is FW-MOON-08). CAM sets the optics hint on its camera.

**Owns:**
- `app/render/sun/` (optics math, CPU cloud mirror)
- `app/render/landscape_upgrade/sun_glare.gd`, `sun_glare.gdshader` (taken over from LU-04 with LU's interface: node name `SunGlare`, `--sun-glare=0..2|off`, `OPENRC_SUN_GLARE`)
- `app/tests/test_sun_optics.gd`, the `glare_offset_*`, `glare_afterimage*` and `glare_lens*` cases of `app/tests/capture_landscape_upgrade.gd`
- `tools/landscape/glare_contrast.py`; evidence in `docs/research/sun/`

Hooks in shared files: the solar block and `sun_*` uniforms of `app/render/sky.gdshader`; `Atmosphere._set_sun_uniforms`; one metadata line in `app/render/camera/camera_rig.gd`.

## 1. Goal

The pilot stands at the field and follows the model. When it flies near or across the sun the pilot must lose it, as in real life, and the sun must look like the sun: a limb-darkened disc that flattens and reddens as it sets, inside a bright aerosol glow. Chase and orbit cameras are cameras, so they show a lens flare instead of an eye's glare.

Non-goals: HDR bloom (Compatibility is LDR), photometric calibration of the display, eye damage.

## 2. Model (what is implemented)

The physics, sources and rejected alternatives are in [SUN-00](../research/sun/SUN-00/README.md). In short: the eye's steady straylight dims a model near the sun but does not hide it; the sun's image bleaching the retina does, within a fraction of a second, for seconds.

| Part | Physics | Where |
| --- | --- | --- |
| Disc | Quadratic limb darkening near 550 nm, mean-preserving; refraction flattening (Sæmundsson, as the moon's; 0.84 on the horizon) | `sky.gdshader` `sun_disc_profile`; `SunOptics.limb`, `.squash` |
| Aureole | Krisciunas & Schaefer (1991) aerosol term anchored to the sun's illuminance (B/E in sr⁻¹), flat inside 1°, only above its 45° value, kept below 0.4 of the disc's mean radiance (under its limb) and faded out over the last 2° above the horizon (the sky must meet the ground's fog colour there) | `sky.gdshader` `sun_aureole`; `SunOptics.aureole_*` |
| Eye veil | CIE 146:2002 general disability-glare equation (age 40, pigment 0.5) above its 45° value, over the luminance behind the model (sky plus aureole): r = Ψ·S/(1 + S_b·g). S = E/B, the sun's illuminance over the sky's luminance around it, read from the live sky (≈ 9 on the calibrated day, 1–3 for a low sun, < 0.5 at the horizon), times the disc's visible fraction, clouds and strength; S_b = E/B times clouds only (the aureole is sky light). Overlay alpha q/(1+q), q = κ·r, so displayed contrast falls by 1/(1 + r) | `sun_glare.gdshader` pass 0; `SunOptics.veil_*`; `SkyMirror.background_luminance` |
| Visibility | Clouds from the CPU mirror of the sky's own decks (classic and layered), cached until they change; the disc's visible fraction from 9 depth samples on screen (the flown aircraft included); off screen and for bleaching, the field's skyline from the pilot's eye (SUN-09), else a 3° prior | `SkyMirror.transmission`; `Skyline`; pass 0 |
| Ciliary corona | Fine radial needles near the source, drifting slowly on the shader clock | pass 0, eye |
| Bleaching | Up to eight fixed retinal cells of 1.15° (disc plus its bleaching halo), fixed to the view; the sun's image feeds each by a Gaussian of its distance, dD/dt = e(1−D)/0.05 s − D/8 s on simulation time, exact per step, with e the sun's absolute illuminance relative to the day sun. A sweep leaves a streak, a stare one saturated cell. Drawn on a canvas layer under the interface: the image blurred over twice the cell's size (lost acuity) with masking up to 0.95, violet-dark once the sun has left the cell | `SunOptics.afterimage_*`, `bleach`; `sun_afterimage.gdshader` |
| Veil colour | The disc's, raised per channel to 1.1 × the sky around the source, so the mix only brightens (straylight adds light); no veil on sky pixels inside the source's own disc | `SunOptics.veil_colour`; pass 0 |
| Eyewear | Cap brim shades a source > 25° above the line of sight (veil and dose); light-brown sunglasses pass 25 % (dose only) | `SunOptics.eyewear_factors`; `--pilot-eyewear` |
| Lens | 0.2 × the eye's veil, six-blade starburst, five ghosts through the frame centre (pass 1); no bleaching | passes 0 and 1, `openrc_optics = "lens"` |

## 3. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| SUN-00 | Audit of the LU-04 glare and the sky's disc; physiology, optics and prior-art research. | Delivered: [SUN-00](../research/sun/SUN-00/README.md). |
| SUN-01 | Disc limb darkening and refraction flattening; sun aureole (background pass only, so the calibrated radiance cubemap is unchanged). | Delivered: unit checks, native captures noon/sunset ([SUN-01…05](../research/sun/SUN-01-05/README.md)). |
| SUN-02 | Eye veil (CIE over sky plus aureole, E/B from the live sky), display mapping, per-camera projection in the shader (no frame lag, any FOV), CPU mirror of the sky (fixes LU-04's glare under layered weather), horizon prior. | Delivered: `test_sun_optics.gd`; `glare_offset_*` captures measured by `glare_contrast.py`. |
| SUN-03 | Bleaching and afterimage on simulation time (pause and replay hold it; a jump rests the eye). | Delivered: exact-integration and patch checks; `glare_crossing*` and `glare_afterimage` captures. |
| SUN-04 | Optics per view: eye (pilot) vs lens (chase, orbit, close-up): starburst and ghosts. | Delivered: `glare_lens` capture. |
| SUN-05 | Regression: LU glare checks updated for the new physics (13/13), whole unit set, review fixes. | Delivered; 548/570 unit tests pass, the 22 failures traced to other tracks or parallel runs ([SUN-01…05](../research/sun/SUN-01-05/README.md#2-measurements)). Target-GPU cost belongs to SUN-08. |
| SUN-02b | The veil never darkens: target colour ≥ the sky around the source; disc exclusion and ALBEDO encoding (with FW-MOON-08). | Delivered: 0 darkened sky pixels at golden hour (was 195); Day unchanged ([SUN-02b…09](../research/sun/SUN-02b-06-09/README.md)). |
| SUN-05b | The optics inside the real flight scene (`main.gd`): layering, process order, bleaching, pause, lens, restart, strength, skyline, eyewear. | Delivered: `test_sun_flight.gd` 22/0. |
| SUN-06 | Pilot eyewear: cap brim and light-brown sunglasses, `--pilot-eyewear` / `OPENRC_PILOT_EYEWEAR` (default none). | Delivered as a command-line/environment option; an interface preference and the default need the UI owner and the owner (SUN-D1). |
| SUN-07 | Moon glare as a second source of the same overlay (FW-MOON-08 owns it). | Open; API in `SunGlare.source()`. |
| SUN-09 | The field's skyline from the pilot's eye for bleaching and the off-screen veil, built incrementally from the field's geometry. | Delivered: `test_sun_skyline.gd` 14/0 (opengl3), in-flight checks; default-field profile and cost in the evidence. |
| SUN-08 | Owner flight acceptance: fly across the sun on Day, golden hour and sunset; judge how long the model is lost, the afterimage streak, the veil and the lens flare. Tune `AFTER_RECOVER_S`, `AFTER_MAX_ALPHA`, the patch blur and the `--sun-glare` default from it. | Open (Gate). |

## 4. Controls

`--sun-glare=0..2` (or `off`) and `OPENRC_SUN_GLARE` scale the veil's straylight and the bleached patches' masking; `--pilot-eyewear=none|cap|sunglasses|cap+sunglasses` (or `OPENRC_PILOT_EYEWEAR`) sets what the pilot wears; `--landscape-upgrade=off` removes it. The camera rig marks its view (`openrc_optics` metadata). Commands: [tools/landscape](../../tools/landscape/README.md).

## 5. Limits

- The bleaching dose sees clouds and the field's static skyline (SUN-09), not the aircraft or other moving objects; lens views and other eye positions keep the constant 3° prior. The on-screen veil uses the real depth buffer.
- Bleaching is eight 1.15° cells, not a per-pixel retina: a sweep longer than eight cells stops leaving new ones until a cell fades; the minutes-long faint tail of a real afterimage is not drawn.
- The veil's display mapping assumes a background near 0.75 of the veil's displayed colour (a day sky near the sun, measured within 0.05); a forced dark exposure over-veils.
- E/B comes from the sky table's gradient; near the horizon that sky is bright, so a low sun veils little (as observed), but the absolute numbers carry the table's and KS91's 2–4× uncertainty.
- Transparent canopies do not write depth; nine depth samples can step during a small-object transit (LU-04 limits).
- One source at a time; the moon is FW-MOON-08's.
- Constants marked estimate in `sun_optics.gd` wait for SUN-08.

## 6. Owner decisions

| ID | Decision | Default until answered |
| --- | --- | --- |
| SUN-D1 | What the pilot wears by default (none, cap, sunglasses, both) and whether Settings offers it. RC pilots commonly wear a cap and light sunglasses; a cap removes glare from a high sun while flying low, never when looking at the sun. | none (the glare as measured in SUN-01…05) |
| SUN-D2 | The calibrated Day's disc and aureole changed within 45° of the sun ([DECISIONS](../DECISIONS.md), 2026-10-19). | accepted unless reverted |

