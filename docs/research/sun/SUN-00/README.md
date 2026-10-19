# SUN-00: audit of the sun, glare research and prior art

2026-10-19. Scope: the solar disc in `app/render/sky.gdshader`, the LU-04 glare overlay (`app/render/landscape_upgrade/sun_glare.*`) and what physiology, optics and other simulators say a pilot sees near the sun. Plan: [sun.md](../../../plans/sun.md). Results of the implementation: [SUN-01…05](../SUN-01-05/README.md).

## 1. What existed (HEAD 8b52fc28)

| Part | Behaviour | Finding |
| --- | --- | --- |
| Disc | Flat disc 4·sun_lin/π, 0.53°, edge ramp 0.9–1.1 r; halo (sun_lin/π)·0.35·e^(−18θ) in every pass | No limb darkening; no refraction flattening (the moon has it since FW-MOON-05); the halo is ~0.6× the haze 1° from the sun, so the sky around the sun is far darker than a real aureole. |
| Glare (LU-04) | Full-screen alpha quad: 0.015 + two exponential halos + an 8-ray starburst + one ghost, × exposure/(exposure + 0.5), alpha capped at **0.30** "bounded for aircraft visibility" | By design it cannot blind: the [baseline capture](before-grid.png) shows the Stik 1.6° from the sun as a crisp red silhouette. LU-06 measured mean RGB difference glare-on vs off of 1.19/255. |
| Glare optics | Starburst and ghost in the pilot view | Camera artefacts in a view that stands for the eye (the [L-investigation 09](../../landscape-investigations/09-lighting-color-lookdev.md#e-sun-glare-and-lens-flare-in-compatibility) already noted the eye has no ghosts). |
| Glare clouds | Vertex shader repeats the **classic** deck only | Bug: with a layered weather profile (overcast, storm) the sky hides the disc but the glare still shines. |
| Glare geometry | Sun position from `unproject_position` on the CPU; hidden when forward·sun < 0.15; fades 2 % outside the frame | A sun just outside the frame gives nothing (the eye still gets straylight); ortho and keep-width need special cases. |
| Time | None | No afterimage or recovery. |

Engine facts that constrain the design (Godot 4.7.2, Compatibility):

- The renderer is LDR (RGBA8); auto-exposure is Forward+ only, so adaptation is scripted (FW-23).
- An unshaded material's ALBEDO is multiplied by the Environment exposure and tonemapped, transparent passes included ([FW-84](../../field-world/FW-84/README.md)). Overlay colours must therefore be given pre-exposure.
- Blending happens in the 8-bit framebuffer: mixes of two colours in one pass are not display-linear after the tonemapper. An afterimage (dark) and a veil (bright) need separate passes (measured: one combined pass drew a warm ring instead of a dark patch).
- Writing sky uniforms every frame re-renders the radiance cubemap in the calibrated day and the TOD snapshots (FW-MOON-01: +69 ms on llvmpipe). Sun uniforms are written only at build and on sky steps; the overlay never writes the sky except LU-04's one-time `disc_cloud_occlusion`.
- `hint_depth_texture` works in the transparent pass; flat varyings and the `sim_clock` global uniform work in the glare shader (native captures, this step).

## 2. What the research says

Full tagged notes with every URL: [research snapshot](research-2026-10-19.md); the tables come from [calc.py](../../../../research/sun/sun-00/calc.py) and [calc2.py](../../../../research/sun/sun-00/calc2.py).

- **Straylight.** CIE 146:2002's general disability-glare equation, valid 0.1–100°: Ψ(θ) = 10/θ³ + (5/θ² + 0.1p/θ)·[1 + (A/62.5)⁴] + 0.0025p sr⁻¹ (Bará & Bao-Varela 2023 quoting CIE; Vos & van den Berg). At age 40 with brown eyes: Ψ(1°) = 15.9, Ψ(10°) = 0.0755. For a 100 klx sun that is a veil of 1.6·10⁶ cd/m² at 1° and 7.5·10³ cd/m² at 10°.
- **The steady veil does not lose the model.** The luminance behind a model near the sun includes the aerosol aureole (Krisciunas & Schaefer 1991: 6.2·10⁷·ρ⁻² nL per fc within 10°, validated on daytime sun data; ≈2.9·10⁵ cd/m² at 1°). The silhouette keeps ×0.16 of its contrast at 1°, ×0.30 at 5°, ×0.44 at 10°. With Blackwell/Crumey thresholds that is still 24–75 times above detection at 150–300 m.
- **Photobleaching does.** The sun's retinal irradiance is ~58 times the 1 s afterimage threshold of Ho et al. (2011, Sandia), so a 0.15 s glance leaves an afterimage. Clinical photostress recovery is under 30 s (35 s to age 50, 70 s over 70); acuity after laser dazzle returns in 30–60 s while a faint afterimage lasts minutes. Ritschel & Eisemann (2012) model it as ṙ = c·L·(1 − r) − c·r. A dazzling white source leaves a purple to blue-violet negative afterimage. Pilots describe "losing orientation" in the sun: the model turns into a colourless silhouette, then disappears behind the afterimage.
- **Disc.** Quadratic limb darkening near 550 nm: I/I₀ = 0.30 + 0.93μ − 0.23μ² (Allen/Cox); the power law μ^0.508 (Hestroffer & Magnan) agrees within 1 % at μ = 0.5. Refraction flattens the setting disc to 0.84 with its lower limb on the horizon, 0.93 at 2°, 0.98 at 5° (Bennett/Sæmundsson).
- **RC practice.** BMFA flightlines normally face north; F3N pilots asked for a perspex sun disc on a pole. Model Aviation (1995) recommends light brown, non-polarized sunglasses (polarized lenses can black out LCD transmitters). Clubs take off away from the sun.
- **Other simulators.** None of FlightGear, CRRCsim or PicaSim models dazzle; X-Plane relaxes its auto-exposure "to avoid being blinded". IL-2's oversized glare is widely read as fake. FlightGear's HDR sun uses the same power-law limb darkening. Sky3D's single Henyey–Greenstein lobe (g = 0.8) cannot form an aureole (2× fall from 1° to 10°, against 100× for ρ⁻²). The CC0 TranquilMarmot lens flare (canvas_item, additive) works in Compatibility.
- **Engine.** Compatibility's glow has four half-size levels (largest ≈ 1/16 of the screen), far too narrow for a 10–20° veil, so the veil is analytic. Depth NDC is [−1, 1] without reverse-Z; screen and depth textures are a single blit after the opaque pass and the sky.

## 3. Adopted, adjusted, rejected

| Item | Decision | Why |
| --- | --- | --- |
| CIE Ψ per pixel from the angle to the sun | Adopted (age 40, p 0.5), above its 45° value | Analytic; no convolution or glow needed. |
| Local background = sky + aureole | Adopted | Textbook adaptation luminance; gives the measured ×0.3–0.7 band instead of a white-out. |
| Hiding by photobleaching, screen-fixed in the pilot view | Adopted as up to three CPU-tracked patches (not a ping-pong SubViewport buffer) | Cheaper; needs no render target; deterministic on simulation time. Limit: patches are blobs, not exact streaks. |
| Bleach 0.25 s, recover 8 s, masking α ≤ 0.85 | Adopted, labelled estimates | 0.15 s glance must mark the eye; acuity back well before 30 s. The minutes-long faint tail is not drawn. |
| Positive afterimage (~1 s) and flight of colours | Rejected for now | Brief, and mostly seen with eyes closed. |
| Disc limb darkening, quadratic law; refraction flattening | Adopted | Matches the research gates (I(0.5) ≈ 0.70; 0.84 on the horizon). |
| KS91 aureole in the sky, core regularised | Adopted, anchored to the sun's illuminance and compressed against the LDR disc | Anchoring to the zenith (the moon's way) made the aureole 13× brighter than this sky's dim disc. |
| Lens flare for chase, orbit and close-up | Adopted, own shader (starburst + ghosts) | Same pass and occlusion as the eye; the CC0 shader would need its own occlusion. |
| Pupil hippus, eye-adaptation lag toward the sun | Not adopted | Adaptation would darken the scene and *raise* a dark silhouette's contrast; hippus is subtle. |

## 4. Ideas not yet implemented

1. Cap brim and sunglasses (SUN-06): a brim clips the sun ≳30° above the gaze; light-brown sunglasses scale the bleaching dose (~×0.2) but not the veil ratio.
2. A field "sun disc on a pole" prop the pilot can raise (BMFA F3N practice).
3. Moon glare through the same overlay (SUN-07, FW-MOON-08).
4. Silhouette mode: fade a model's colour and shading cues inside the veil (the orientation loss pilots report) before it disappears.
5. A sun-position cue for flight planning on Home (where the sun will be relative to the flightline).
