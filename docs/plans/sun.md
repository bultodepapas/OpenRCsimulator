# Sun: realistic disc, glare and dazzle

2026-10-19 · Revision 1 · **Implementation plan** · Step prefix: **SUN**

**Status:** 2026-10-19: SUN-00…05 delivered (software and native capture evidence on llvmpipe); SUN-06 eyewear, SUN-07 moon glare hand-off and SUN-08 owner flight acceptance are open. Evidence: [SUN-00 audit and sources](../research/sun/SUN-00/README.md), [SUN-01…05 results](../research/sun/SUN-01-05/README.md).

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
| Aureole | Krisciunas & Schaefer (1991) aerosol term anchored to the sun's illuminance (B/E in sr⁻¹), flat inside 1°, only above its 45° value, compressed against the LDR disc | `sky.gdshader` `sun_aureole`; `SunOptics.aureole_*` |
| Eye veil | CIE 146:2002 general disability-glare equation (age 40, pigment 0.5) above its 45° value, over the luminance behind the model (sky plus aureole): r = Ψ·S/(1 + S·g). S = E/B, the sun's illuminance over the sky's luminance around it, read from the live sky (≈ 9 on the calibrated day, 1–3 for a low sun, < 0.5 at the horizon). Overlay alpha q/(1+q), q = κ·r, so displayed contrast falls by 1/(1 + r) | `sun_glare.gdshader` pass 0; `SunOptics.veil_*`; `SkyMirror.background_luminance` |
| Visibility | Clouds from the CPU mirror of the sky's own decks (classic and layered); the disc's visible fraction from 9 depth samples on screen (the flown aircraft included), a 3° skyline prior off screen | `SkyMirror.transmission`; pass 0 |
| Ciliary corona | Fine radial needles near the source, drifting slowly on the shader clock | pass 0, eye |
| Bleaching | Up to three retinal patches fixed to the view; dD/dt = e(1−D)/0.25 s − D/8 s on simulation time, exact per step, with e the sun's absolute illuminance relative to the day sun. A patch shows no detail (masking up to 0.85): the veil's colour while the sun is on it, dark violet-grey after | `SunOptics.afterimage_*`; pass 1, eye |
| Lens | 0.2 × the eye's veil, six-blade starburst, five ghosts through the frame centre; no bleaching | passes 0 and 1, `openrc_optics = "lens"` |

## 3. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| SUN-00 | Audit of the LU-04 glare and the sky's disc; physiology, optics and prior-art research. | Delivered: [SUN-00](../research/sun/SUN-00/README.md). |
| SUN-01 | Disc limb darkening and refraction flattening; sun aureole (background pass only, so the calibrated radiance cubemap is unchanged). | Delivered: unit checks, native captures noon/sunset ([SUN-01…05](../research/sun/SUN-01-05/README.md)). |
| SUN-02 | Eye veil (CIE over sky plus aureole, E/B from the live sky), display mapping, per-camera projection in the shader (no frame lag, any FOV), CPU mirror of the sky (fixes LU-04's glare under layered weather), horizon prior. | Delivered: `test_sun_optics.gd`; `glare_offset_*` captures measured by `glare_contrast.py`. |
| SUN-03 | Bleaching and afterimage on simulation time (pause and replay hold it; a jump rests the eye). | Delivered: exact-integration and patch checks; `glare_crossing*` and `glare_afterimage` captures. |
| SUN-04 | Optics per view: eye (pilot) vs lens (chase, orbit, close-up): starburst and ghosts. | Delivered: `glare_lens` capture. |
| SUN-05 | Regression: LU glare checks updated for the new physics, full suite, cost. | Delivered with the limits in the evidence. |
| SUN-06 | Pilot eyewear: cap brim (blocks a sun high above the gaze) and sunglasses (lower bleaching, same veil ratio). Needs UI owner for a preference. | Open. |
| SUN-07 | Moon glare as a second source of the same overlay (FW-MOON-08 owns it). | Open; API in `SunGlare.source()`. |
| SUN-08 | Owner flight acceptance: fly across the sun on Day, golden hour and sunset; judge how long the model is lost, the afterimage, the veil and the lens flare. Tune `AFTER_BLEACH_S`, `AFTER_RECOVER_S`, `AFTER_MAX_ALPHA` and the `--sun-glare` default from it. | Open (Gate). |

## 4. Controls

`--sun-glare=0..2` (or `off`) and `OPENRC_SUN_GLARE` scale the whole effect (veil and bleaching dose); `--landscape-upgrade=off` removes it. The camera rig marks its view (`openrc_optics` metadata). Commands: [tools/landscape](../../tools/landscape/README.md).

## 5. Limits

- The bleaching dose sees clouds and the skyline prior, not trees, buildings or the aircraft: a low sun hidden behind a near tree can still mark the eye. The on-screen veil uses the real depth buffer.
- Patches are blobs: a fast sweep of the sun across the view leaves up to three merged patches, not an exact streak; the minutes-long faint tail of a real afterimage is not drawn.
- E/B comes from the sky table's gradient; near the horizon that sky is bright, so a low sun veils little (as observed), but the absolute numbers carry the table's and KS91's 2–4× uncertainty.
- Transparent canopies do not write depth; nine depth samples can step during a small-object transit (LU-04 limits).
- One source at a time; the moon is FW-MOON-08's.
- Constants marked estimate in `sun_optics.gd` wait for SUN-08.
