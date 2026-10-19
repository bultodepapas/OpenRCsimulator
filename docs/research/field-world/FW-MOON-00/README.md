# FW-MOON-00: moon audit, accuracy measurement and source research

**Status:** research record, 2026-10-19. No runtime change. It informs the [moon plan](../../../plans/moon.md). Sources: [sources.json](sources.json) (`openrc-reference-manifest v1`); local copies live in the gitignored `references/moon/`. Scripts: [research/field-world/fw-moon-00/](../../../../research/field-world/fw-moon-00/).

Numbers marked *derived* were computed here from the cited formulas. "UNVERIFIED" means only secondary sources were found.

## 1. What the moon is today

These findings come from the code at HEAD d055b780 plus the working tree on 2026-10-19.

| Area | Current behaviour | Defect or limit |
| --- | --- | --- |
| Ephemeris | [ephemeris.gd](../../../../app/render/world/ephemeris.gd) uses Schlyter elements (12+5+2 perturbation terms), topocentric parallax, Bennett refraction and phase from elongation. | Accurate enough for the disc (§2). Not accurate enough for eclipse contact times. |
| Lighting paths | The FW path is `Conditions → Ephemeris.sky → SkyState.state → Atmosphere`. | The TOD astronomical path has no moon at all. `time_of_day_lighting.gd:71` records `moon = "not-modelled"`, and a TOD snapshot forces `conditions = {time_of_day = false}` (`world.gd:219-220`). The Conditions "Time of day" tab, the pause "Sky and lighting" editor and "View at night" therefore all show a moonless night. "View at night" selects the moonless TOD Night preset. |
| Presets | "Night, full moon" is 2026-06-29 at solar midnight. "Night, no moon" is 2026-06-15 (`conditions.gd:32-33`). | The full moon is at azimuth 165°, elevation 20°: behind the pilot, who stands at the origin facing the east–west runway 15 m north. It is also near apogee (63.5 Earth radii). The FW-84 captures confirm that the disc stays off-camera. |
| Disc | Analytic 0.52° disc (`sky.gdshader:71-82`) with a smoothstep terminator lit from the true sun direction. Colour is constant (0.98, 0.96, 0.92). | No texture, maria or orientation. The disc size is fixed, although the topocentric size ranges from 0.49° to 0.56°. There is no horizon reddening or flattening. The disc is also drawn in the radiance cubemap pass (line 99, before any `AT_CUBEMAP_PASS` test). |
| Disc brightness | Every lit pixel = `MOON_DISC × zenith × phase_flux(α)` (`sky_state.gd:214`). | Disc-integrated flux is applied per pixel. A crescent at α = 150° comes out about 15× too dim per pixel: 0.0043 instead of 0.064 of the full-moon surface brightness (*derived*). |
| Earthshine | A constant 2 % of the lit value (`sky.gdshader:81`). | Physical earthshine is 3.6·10⁻⁴…3.6·10⁻⁶ of the full-moon surface brightness, and it fades as the Earth wanes toward full moon. Relative to the lit limb, the current value is about 4× too bright at a thin crescent and about 18× too bright at quarter (*derived*). |
| Moonlight | One DirectionalLight carries the brighter of sun and moon (`sky_state.gd:157`). Moonlight has physical luminance (2.5·10⁻⁶ × Allen phase law) and a fixed cool colour `#b4c8ff`. | Colour does not change with altitude. The light switches between sun and moon by `max()`, so at twilight it can jump direction (shadow flip). PSSM shadows stay on at any phase, and the planar pilot shadow has full strength at any phase (`main.gd:2096-2100`). |
| Night clouds | Layered decks, relief and the silver edge read `sun_dir` (`sky.gdshader:132, 191`). In field-world mode that uniform is the active light's direction (`atmosphere.gd:384` → `state.light_dir`), so they already follow the moon at night. `storm_bank.gd` has no light direction by day or night. | Correct for the moon. *Corrected 2026-10-19 (FW-MOON-02 review): the first version of this row wrongly said the clouds were lit from the below-horizon sun, and the Moonlight row wrongly said the light pops on at −1°: the sky table ramps the direct beam from −0.5° to 0°.* |
| Thin cloud and haze | The moon is painted under clouds and hidden by their alpha. | No transmission through thin cloud, aureole, corona or 22° halo. |
| Stars | Dimmed only through the global exposure (`stars.gd:17-24`). | No washout near the moon. |
| Glare | `sun_glare.gd` handles the sun only and hides when `sun_disc = 0`. | No moon glare. |
| Lake | The GGX highlight from the directional light (`water.gdshader`). | The moon road on rippled water has never been checked. |
| Eclipses | Not modelled. | A full moon on an eclipse date renders at full brightness. |
| Options | Home shows only the labels "Full moon" / "New moon" (`home.gd:1190-1194`). | No moon controls, preferences or CLI. |

## 2. Accuracy of the current ephemeris

[compare_svs.py](../../../../research/field-world/fw-moon-00/compare_svs.py) compares the Python port of `ephemeris.gd` with the hourly NASA SVS 5587 table for 2026, using 1252 samples. Output: [svs-comparison-2026.txt](svs-comparison-2026.txt).

| Quantity | Residual |
| --- | --- |
| Illuminated fraction | mean −0.07, max 0.17 percentage points |
| Distance | p95 651 km, max 979 km (≤ 0.26 % of the apparent size) |
| Position (precession removed) | median 1.6′, p95 3.7′, max 6.7′ |

**Conclusion:** phase and size are already right. The position error is at most 0.2 disc diameters, which is invisible at a normal field of view and acceptable for the disc. An eclipse needs about 1′; with 6.7′, contact times can be off by about 13 minutes (*derived*).

## 3. Where the pilot can see the moon

[showcase_survey.py](../../../../research/field-world/fw-moon-00/showcase_survey.py) uses the reference place (40° N, 3.7° W) and treats "forward" as within 100° of north. Output: [showcase-survey-2026.txt](showcase-survey-2026.txt).

- At 40° N the moon culminates in the south, behind the pilot. It enters the forward half only near rising (E/NE) or setting (W/NW), and only when its declination is northern. Full moons do this from September to March.
- **Harvest Moon, 2026-09-26.** At 20:00 CEST the moon rises at azimuth 86° while the sun sets at 268°. At 20:25 the moon is at 4° with the sun at −2.7°; at 21:00 the moon is at 12.6° with the sun at −11.3°. It rises inside the twilight's Earth-shadow band, ahead and to the right of the pilot.
- **Near-perigee full moon, 2026-12-23 19:40 CET.** Azimuth 74°, elevation 24°, illumination 99.7 %. The distance is 56.0 Earth radii, close to the largest full moon of 2026 (Dec 24, 01:28 UT).
- **Eclipses seen from the field:**
  - 2026-08-28 at 04:14 UT, partial: the moon is at 242°, 15°, with the sun at −16° (dawn, behind-left).
  - 2028-12-31, total: the totally eclipsed moon rises at 58–64° between 17:53 and 18:30 CET.
  - 2026-03-03 total: not visible from the field (daytime).
  - Verify these with Horizons before using them as presets.

## 4. Research findings

| Topic | Finding (source) | Use |
| --- | --- | --- |
| Texture | NASA SVS 4720 CGI Moon Kit. 2025 LROC colour `lroc_color_2k.jpg` (2048×1024, 0.45 MB), 4k/8k/16k TIFF and EXR. LOLA LDEM at 4–64 px/deg (float km, 1737.4 km sphere). No normal map. The colour is Hapke-normalised, so it is albedo without lighting; the page says "optimized for aesthetics". Credit "NASA's Scientific Visualization Studio". Godot imports no TIFF. | Default albedo; build the normal map from the LDEM with a recorded script. |
| Texture size | A texture width of π × disc pixels matches the disc. At 1080p and 60° FOV the disc is about 9 px; at 1° FOV, about 560 px (*derived*). | 2k covers every current camera; 4k only for a telescope view. |
| Constants | Geometric albedo 0.12, Bond 0.11, V₀ −12.74, perigee 363,300 km, apogee 405,500 km (NSSDC). | Fixtures. |
| Phase law | KS91: m = −12.73 + 0.026\|α\| + 4·10⁻⁹α⁴. Full moon 0.313 lux at mean distance outside the atmosphere; 0.0285 lux at α = 90° (*derived*). Perigee/apogee ratio 1.246. The existing 2.5·10⁻⁶ moon/sun ratio agrees (Agrawal zero point: 2.49·10⁻⁶). Do not add the 1.35 opposition surge on top: −12.73 already contains it. | Disc-integrated flux and moonlight. |
| Measured moonlight | Typically 0.05–0.1 lux; the 2016-11-14 supermoon at 55.5° gave 0.26 lux horizontal (Kyba et al. 2017, abstract). | Plausibility band. |
| Surface photometry | Lommel–Seeliger gives a flat full disc. McEwen lunar-Lambert: r = 2L·μ₀/(μ₀+μ) + (1−L)·μ₀, with L(α) = 1 − 0.019α + 2.42·10⁻⁴α² − 1.46·10⁻⁶α³, clamped ≥ 0 (ISIS, public domain). Alternatives: Akimov (parameter-free) and the Jensen 2001 Hapke–Lommel–Seeliger B·S form. | Per-pixel shading; the terminator comes from μ₀ and the normal map, not from a smoothstep. |
| Earthshine | Palle 2016 eq. 1: E_earth/E_sun = (2/3)·p*·f_L(β)·(R_E/d)², with p* ≈ 0.3 and f_L(β) = [(π−β)cos β + sin β]/π. Gives 5.5·10⁻⁵ at full Earth and 1.7·10⁻⁵ at β = 90° (*derived*). The earthlit side is 0.15 mag bluer in B−V (Thejll 2014). | Dark-side brightness and tint. |
| Orientation | Bright-limb angle χ (Meeus ch. 48) and parallactic angle q (Meeus 14.1); tilt relative to the zenith = χ − q. The full Moon-fixed → horizon rotation comes from the IAU WGCCRE 2009 pole and W (in astronomy-engine `RotationAxis`, MIT). SunCalc v2 returns degrees, v1 radians. | Texture orientation, libration, and the "man in the moon" turning through the night. |
| Extinction | Kasten–Young airmass X = 1/[cos z + 0.50572·(96.07995° − z)^−1.6364], with X(90°) = 37.9. Typical k: B 0.33, V 0.20, R 0.12 mag/airmass; a high site has less (La Palma V 0.13). | RGB reddening and dimming near the horizon. The k values are site estimates; label them. |
| Flattening | Vertical/horizontal diameter ratio ≈ 0.855 with the centre on the horizon, 0.93 at 2°, 0.975 at 5° (Bennett, *derived*; A. T. Young). | Map disc pixels through refraction. |
| Moon illusion | Perceptual (Kaufman & Rock 1962). | Do not enlarge the real disc near the horizon. |
| Halo and corona | 22° halo at minimum deviation 21.84° for n = 1.31 (*derived*), only in thin ice cloud. Corona red rings at θ ≈ 16/r, 31/r, 47/r degrees (r in µm; Laven 2015), from thin water cloud. Aureole: KS91 Mie term 6.2·10⁷/ρ² for 0.25° < ρ < 10°. Halo colour order is UNVERIFIED in a primary source. | Drive by sky profile, not always on. |
| Night look | Moonlight is redder than sunlight (Jensen 2000); 4100 K is UNVERIFIED. The eye's mesopic shift (Krawczyk): σ(Y) = 0.04/(0.04+Y); RGB' = RGB·L(1−σ)/Y + (1.05, 0.97, 1.27)·L·σ. Jensen 2000 blue shift toward (0.25, 0.25). | "Eye" night look, applied to moonlit quantities only so lamps keep their colour. |
| Moonlit sky | KS91 B_moon = f(ρ)·I*·10^(−0.4k·X_m)·[1 − 10^(−0.4k·X)], with f(ρ) = 10^5.36·(1.06 + cos²ρ) + Mie. Accuracy 8–23 %. The NELM formula's origin is UNVERIFIED. | Validate sky ratios; drive star washout near the moon. |
| Eclipses | Shadow geometry: Earth radius enlarged to 6371 + 88 km (astronomy-engine `CalcShadow`). Danjon scale L0–L4. Espenak 2026–2028: 2026-03-03 total, 2026-08-28 partial 0.930, 2028-01-12 partial 0.066, 2028-07-06 partial 0.389, 2028-12-31 total 1.246. | Umbra/penumbra shading and fixtures. |
| Validation | SVS 5587 hourly table (all 8760 hours of 2026: phase, diameter, distance, sub-Earth and subsolar points, axis angle). SVS frames are celestial-north-up. JPL Horizons API (DE441) works from this VM; rise/set at Madrid 2026-03-02…04 is saved. | Fixtures and overlay checks. |

## 5. Godot 4.7 Compatibility constraints

- The sky pass applies exposure, tonemapping and the sRGB transform itself. The radiance cubemap is RGB10_A2.
- Half- and quarter-resolution sky passes are parsed but not rendered in GLES3.
- Any sky-material uniform change invalidates the radiance cubemap (Godot docs). The world currently throttles sky updates to one per 30 s of sky time. At 20× that moves the moon 0.125° per step, about 2 px at 60° FOV and much more in a close-up (*derived*). Smooth motion and cubemap cost therefore conflict. FW-MOON-01 measures this before any render-path choice.
- Glow exists in Compatibility since 4.3, but the project disables it (L1b). A bright disc clips at the 10-bit target.
- Sky3D (MIT) is the main Godot reference. It shades its moon with Lambert N·L, which limb-darkens the disc (wrong for the Moon). Its texture has weak provenance. Do not reuse its photometry.

## 6. Dead ends and corrections

- The USNO API and timeanddate were unreachable (SSL reset / 403). The KS91 PDF mirror was overloaded. The Kyba 2017 and PNAS pages returned 403, and Montañés-Rodríguez 2007 returned 404.
- A subagent summary called thorsky "BSD-2". Its header says **GPL-3.0**. Like Stellarium (GPL), it is reference only.
- The Wikipedia "0.32 lux maximum" is unsourced. NSSDC's Earth geometric albedo (0.434) is not the earthshine p* (≈ 0.3).
- The godot-gles3 files come from the master branch, not the pinned 4.7.2 tag. Re-check any conclusion against 4.7.2 in FW-MOON-01.
