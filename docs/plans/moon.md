# Moon: realistic, configurable night sky

2026-10-19 · Revision 1 · **Implementation plan** · Step prefix: **FW-MOON** (Field world)

**Status:** 2026-10-19: FW-MOON-00…05 and -12 delivered, FW-MOON-13 partly; FW-MOON-01 chose the sky-shader disc (M-D2), FW-MOON-03b moves the moon every frame and FW-MOON-06 makes the twilight hand-off continuous; FW-MOON-08a adds the aureole; FW-MOON-10 adds lunar eclipses; FW-MOON-11's presets are in place. The textured, oriented, photometric moon renders on the field-world path (Home time choices); astronomical time in the Conditions dialog still has no moon (decision M-D7). The owner decisions in §9 are pending; the stated defaults apply until they are answered.

**Owner:** Field world. Coordinated with TOD (time paths and visual context), UI (dialogs, preferences, i18n), VQ/Landscape (shared `sky.gdshader`, `atmosphere.gd`, `sun_glare.gd`), LU (lake), CAM (close-up), HUD and NR/HELI (routes).

**Owns (proposed):**
- `app/render/world/lunar.gd`, `app/render/world/moon_*` (shader include, disc, halo)
- `app/environment/moon_config.gd`
- `assets/sky/moon/`, `app/assets/sky/moon/`
- `tools/world/moon_texture.py`, `tools/world/moon_fixtures.py`
- `app/tests/test_world_moon_*.gd`
- evidence in `docs/research/field-world/FW-MOON-*`, scripts in `research/field-world/`

Shared files stay with their owners, and this plan states each hook.

## 1. Goal

When the pilot flies at night, the moon must be **right**, **beautiful** and **under the pilot's control**:

- **Right.** Phase, position, size, orientation, libration, rise/set time and eclipses are correct for any date and place. Moonlight strength follows phase, distance, altitude and cloud.
- **Beautiful.**
  - A textured disc that looks flat at full moon, with a crisp terminator, real maria and faint bluish earthshine.
  - An orange, slightly squashed moonrise.
  - Moonlit cloud edges, a 22° halo in cirrostratus, a corona in thin cloud, stars fading near a bright moon, and a moon road on the lake.
- **Configurable without breaking realism.**
  - Real sky, a chosen phase, or no moon.
  - A night look.
  - Clearly labelled non-physical assists (larger disc, brighter moonlight).
  - Quick jumps to moonrise, moon high and moonset.

**The default** is the realistic, dynamic moon of the chosen date and place, which moves and changes while time passes. The night presets put that moon where the pilot actually looks: a Harvest-Moon rise over the field at dusk.

## 2. Starting point

The [FW-MOON-00 audit](../research/field-world/FW-MOON-00/README.md) has the details. In short:

- The FW path already computes the moon well. Against the hourly NASA SVS 2026 table, the illuminated fraction is within 0.17 percentage points and the position within 1.6′ median (6.7′ max).
- **Only the FW path has a moon.** The TOD astronomical time (Conditions → Time of day, pause → Sky and lighting) and "View at night" render a moonless night.
- **The current full-moon preset hides the moon behind the pilot.** It sits at azimuth 165°, elevation 20°; the pilot faces north toward the east–west runway. It is also near apogee.
- **The disc:**
  - It is a flat-coloured analytic disc of fixed size.
  - Its pixels use disc-integrated flux, so a crescent is about 15× too dim per pixel.
  - Earthshine is a constant 2 %, wrong in both level and phase dependence.
  - There is no horizon reddening or flattening.
- **Moonlight and clouds:**
  - Moonlight can flip direction at twilight (one light carries the brighter of sun and moon).
  - Shadows have full strength at any phase.
- **Missing entirely:** halo, corona, glare, star washout, eclipses and moon options.

## 3. Principles

1. **One lunar truth.** A float64 `Lunar` state computes from the same `when` on every route. Rendering converts at the boundary. The moon is visual only: `sim/` and `physics/` never read it, and it stays outside physical weather hashes and aircraft checkpoints. It is recorded in the visual context.
2. **Physics, then perception, then art.**
   - Layer (a), radiometry: phase law, distance, extinction, earthshine, eclipse.
   - Layer (b), the eye: exposure and night look.
   - Layer (c), labelled assists.
   - Defaults use (a) and (b) only.
3. **Options never break geometry.** Choosing a phase moves the calendar to the nearest night with that phase; the terminator is never faked. "No moon" removes the moon completely.
4. **Download, don't create.** Use the NASA SVS CGI Moon Kit for albedo and LOLA elevation, and NASA SVS / JPL Horizons tables for validation. No painted moon.
5. **Compatibility-first and bounded.** The moon's total cost is at most 0.15 ms p95 at 1080p on the target GPU, inside the shared +0.5 ms visual budget. llvmpipe numbers are relative only.
6. **Deterministic.** No `TIME` in shaders; motion follows simulation time. "Tonight" resolves the system clock once and records the resolved date.
7. **Byte-identical day.** The calibrated Day scene, golden flights and physics traces never change. Night visuals change only in steps that declare it and carry before/after captures.

## 4. Architecture

```
when (date, local time, UTC offset, lat, lon) ─► Ephemeris (sun, moon; existing)
                                                  │
moon config (openrc-moon-config v1) ────────────►├─► Lunar.state(when, config)    float64, no Vector3
                                                  │     apparent az/el, topocentric distance and radius, phase angle,
                                                  │     fraction, waxing, bright-limb χ, parallactic q, libration,
                                                  │     Moon-fixed→horizon rotation (9 floats), airmass, RGB extinction,
                                                  │     KS91 illuminance ×(d̄/d)², earthshine ratio, eclipse geometry,
                                                  │     next rise/transit/set
                                                  ▼
                                   SkyState.state()  moonlight, moonlit sky/lobe/clouds, exposure, night look
                                                  │
                     ─ ─ ─ ─ ─ ─ ─ ─ render boundary (float32) ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
         ┌──────────────┬───────────────┬─────────┴──────┬────────────────┬──────────────────┐
     moon disc     halo/corona/     DirectionalLight   stars washout   glare sprite      UI preview
   (FW-MOON-01     aureole (sky     (colour, energy,   (moon_dir,      (sun_glare        (same disc
    picks path)    shader, cloud-   shadow opacity      sky B(ρ))       reused)          include)
                   driven)          by phase)
```

### Shared pieces

- **`Lunar`** (`app/render/world/lunar.gd`): pure static functions next to `ephemeris.gd`.
  - `Ephemeris.sky()` keeps its output. Existing tests and captures do not move until a step says so.
  - An optional Meeus ch. 47 (ELP-2000/82 truncated, ~10″) moon is added only if eclipses need it (§9 M-D9).
- **`moon_disc.gdshaderinc`:** the one disc implementation. Used by the sky shader or disc mesh, and by a `canvas_item` preview in the menu, so the menu shows exactly the moon you will fly under.
- **`moon_config.gd`:** validation, defaults, CLI and environment parsing, digest. It sits in `app/environment/` like `sky_appearance_config.gd`.
- **Assets** (FW-MOON-04):
  - SVS `lroc_color_2k.jpg` (2048×1024, 0.45 MB) becomes the albedo.
  - A 1k normal map is built from LOLA `ldem_4`/`ldem_16`.
  - Immutable downloads live in `assets/sky/moon/source/` with `PROVENANCE.json`.
  - `tools/world/moon_texture.py --check` writes `app/assets/sky/moon/` and a credit file ("NASA's Scientific Visualization Studio").

### Disc rendering (both render paths)

1. **Sphere normal.** Compute the sphere normal under the pixel and rotate it into Moon-fixed coordinates with the libration/axis/parallactic rotation. Equirectangular UV; albedo is the texture (sRGB→linear); the LOLA normal map perturbs the normal.
2. **Brightness.** Lunar-Lambert (McEwen): r = A·[2L(α)·μ₀/(μ₀+μ) + (1−L)·μ₀], with L clamped ≥ 0.
   - A per-phase normalisation K(α) makes the disc-integrated flux equal KS91 × (d̄/d)². A table is built offline and tested.
   - The full moon is flat, and the terminator comes from μ₀ and relief.
3. **Earthshine.** Albedo × E_earth/E_sun(β) (Palle 2016), with a blue tint of ΔB−V = −0.15. It fades toward full moon as the Earth wanes.
4. **Atmosphere.**
   - Per-channel extinction T = 10^(−0.4·k_rgb·X), using Kasten–Young airmass with labelled site estimates.
   - Refraction flattening maps each pixel's elevation through Bennett.
   - The size comes from the topocentric distance: the moon is ~1.5 % larger high in the sky than at the horizon.
5. **Eclipse.** Compute each pixel's distance from the Earth's shadow axis. The umbra gets a Danjon-tinted transmission; the penumbra is smooth.
6. **Sampling.** Use `textureGrad` or an explicit LOD from the angular size: no seam at ±180° longitude, and no shimmer on a 9 px disc.

### Render-path choice (FW-MOON-01, measured, not assumed)

Any sky-material uniform change invalidates the radiance cubemap. Today the sky updates once per 30 s of sky time, so at 20× the moon steps 0.125° (about 2 px at 60° FOV; tens of px in a close-up).

**Candidate A: sky-shader disc, main pass only.**
- Skip the disc and halo when `AT_CUBEMAP_PASS`.
- Simplest, and clouds hide the moon automatically.
- Viable only if per-frame uniform changes do not re-render radiance while the ambient source is COLOR and reflections are disabled, or if that cost is negligible.

**Candidate B: `MoonDisc` mesh.**
- A camera-centred quad at a fixed angular size on a far sphere.
- Unshaded, fog disabled, depth-tested, no depth writes, drawn after the sky.
- Updated every frame from float64 interpolation between flow steps.
- Clouds hide it through the shared `cloud_field.gdshaderinc` and the same uniforms. Terrain, treeline and storm bank hide it by depth.
- The sky shader keeps only the slow, wide terms (aureole/halo).

**Decision rule:** pick A only if measurement shows no radiance re-render, or a cost below 0.05 ms. Otherwise pick B. Record the decision in DECISIONS.

**Result (FW-MOON-01, 2026-10-19):** A. Field-world mode never rebuilds the radiance, so the disc stays in the sky shader and moves every frame ([evidence](../research/field-world/FW-MOON-01/README.md)).

### Moonlight

- **Strength and colour.** Illuminance = KS91 × (d̄/d)² × T_V(X) × eclipse × cloud transmission. The physical colour is the solar spectrum × the lunar reddening ramp × atmospheric extinction. The night look (below) then maps it for display.
- **Moonrise.** The light fades in through the airmass, with no −1° pop.
- **Sun↔moon hand-off.** No direction flip. While both lights matter, the moon is a second, shadowless DirectionalLight; shadows hand over when the moon dominates. FW-MOON-01 checks Compatibility's directional-shadow limits; the fallback is a short crossfade with shadow opacity at zero.
- **Shadows.** Opacity = direct/(direct + ambient). Shadows switch off below a threshold, so a thin crescent casts none. The planar pilot shadow uses the same ratio.

### Night look (FW-MOON-07)

| Look | What it shows | Basis |
| --- | --- | --- |
| **Eye** | What a dark-adapted eye sees: moonlit things desaturate and shift blue, while lamps, the campfire and nav lights keep their colour. Applied on the CPU to moonlit quantities (moonlight, moonlit sky/lobe/cloud, ambient) with the Krawczyk σ(Y_adapt), so no post pass is needed in Compatibility. | Krawczyk 2005/2007; Jensen 2000 |
| **Cinematic** | Today's look: fixed cool moonlight `#b4c8ff` and sky tint. | FW-23 |
| **Camera** | Physical colour, like a long photographic exposure: warm moonlight, blue sky. | Jensen 2000 (moonlight redder than sunlight) |

### In the atmosphere (FW-MOON-08)

- **Aureole.** The KS91 Mie term around the moon, scaled by haze and humidity.
- **Thin cloud.** The disc shows through with exp(−τ). Thick cloud gives a diffuse bright patch.
- **Corona.** Rings from (J₁(x)/x)², with droplet radius set by the sky profile.
- **22° halo.** A ring at 21.84°, only with cirrostratus (High Cirrus and similar profiles), red inner edge, sky slightly darker inside.
- **Moonlit clouds.** Decks, relief and the silver edge already use the active light (the moon at night). The storm bank has no light direction at all; giving it one is a separate FW-84 item.
- **Stars.** A per-star threshold rises with the KS91 sky brightness near the moon.
- **Glare.** `sun_glare.gd` is generalised to the moon with its occlusion logic (LU owner).
- **Lake.** Check the moon road at low elevations; tune only the existing water parameters.

## 5. Options and menu

### Configuration: `openrc-moon-config v1`

Stored in preferences `[moon] config`. It is a new section with no schema bump, following the `[hud]` precedent, and is separate from `SkyConfig` so existing sky digests stay valid.

```json
{
  "format": "openrc-moon-config v1",
  "moon": "real",
  "phase": "full",
  "night_look": "eye",
  "size": "real",
  "moonlight": "real",
  "halo": "auto"
}
```

| Key | Values | Meaning |
| --- | --- | --- |
| `moon` | `real` · `phase` · `off` | Real sky from date/time/place. `phase`: nearest night (±15 days, same clock time) with the chosen phase; the resolved date is shown. `off`: no disc, moonlight, moonlit sky or halo. |
| `phase` | `new` `waxing_crescent` `first_quarter` `waxing_gibbous` `full` `waning_gibbous` `last_quarter` `waning_crescent` | Used when `moon = phase`. |
| `night_look` | `eye` · `cinematic` · `camera` | §4 night look. The default depends on decision M-D4. |
| `size` | `real` · `large` | `large` = 2× diameter, labelled "cinematic, not real". |
| `moonlight` | `real` · `bright` | `bright` = 3× moonlight, labelled "assist". |
| `halo` | `auto` · `off` | Aureole, corona, halo and glare follow the clouds, or are removed. |

**Precedence:** CLI, then environment, then preferences, then defaults. Direct `--` routes never read preferences.

**CLI:** `--moon=real|off|phase:<name>`, `--night-look=`, `--moon-size=`, `--moonlight=`, `--moon-halo=`, plus `OPENRC_MOON*` twins. Invalid values warn and fall back to defaults; invalid data never reaches the renderer.

### Where it appears

**1. Conditions → Time of day tab.** A **Moon** group below time and location (`app/ui/moon_controls.gd`). The same control appears in the pause **Sky and lighting** dialog, respecting its `night_only` rules.

```
┌ Moon ───────────────────────────────────────────────────────────┐
│ (●) Real sky   ( ) Choose phase [ Full moon      ▾]   ( ) No moon │
│  ╭───╮  Waxing gibbous · 87 % · 0.52° · 371,000 km                 │
│  │ ◐ │  Rises 18:42 · highest 00:31 (52°) · sets 06:10             │
│  ╰───╯  Below the horizon at 17:30   [Moonrise] [Moon high] [Moonset] │
│ Night look  [ Eye (realistic)  ▾]   Halo & glare  [ Auto ▾]       │
│ Moon size   [ Real ▾]               Moonlight     [ Real ▾]       │
│             cinematic options are marked and are not realistic   │
└───────────────────────────────────────────────────────────────────┘
```

- The preview is the real disc include (phase, libration, earthshine, eclipse).
- Jump buttons move the time draft to the next event computed by `Lunar` (±2 min against Horizons). A button is disabled with a reason when the event does not occur that day.

**2. Home time choice.**
- Add **"Moonrise, time passing"** (flowing ×20, §6).
- "Night, full moon" shows a phase icon and "Full moon 99 %".
- The Home brief names the moon state.

**3. Sky & clouds → "View at night".** It becomes the moonlit night, with a moonless alternative. It is no longer the moonless TOD preset.

**4. "Tonight".** A time-controls button (TOD/UI) that takes the system date, time and the configured place. It is resolved once and saved as an explicit date and time.

**5. Settings → Display.** "Moon texture: Standard / High" appears only if a 4k texture ships (M-D6).

All controls are navigable with keyboard and gamepad and translated in `app/i18n/es.po`. Non-physical choices carry their label in both languages.

## 6. The spectacular default

**Default moon: Real sky** (`moon = real`, `halo = auto`, `size = real`, `moonlight = real`). The moon changes with the chosen date and with time passing.

**Showcase solver.** A new Conditions event `moon_view` searches forward from a reference date for the first moment that meets constraints:
- illuminated fraction
- sun elevation
- moon elevation band
- azimuth within the pilot's forward cone, taken from field data

Presets therefore stay valid when the place changes, like today's sun-event presets. The search is deterministic and tested at the reference place.

**Moonrise, time passing (new).**
- The flow starts at golden hour on the first full-moon dusk with the moonrise in front of the pilot. At the reference place this is the **Harvest Moon, 2026-09-26**: the moon rises at azimuth 86° while the sun sets at 268°.
- Four minutes of flight bring the sunset glow on the left and an orange, squashed moon lifting through the Earth-shadow band on the right. The moon turns silver as it climbs, moonlight takes over the field, and stars appear around it.

**Night, full moon (retargeted, M-D3).**
- The first full moon 18–30° high in the forward cone with the sun ≤ −18°. Survey candidates: 2026-10-25 21:00 (azimuth 92.5°, elevation 25°, 99.7 %) and 2026-12-23 19:40 CET (azimuth 74°, elevation 24°, 99.7 %, near the largest full moon of 2026).
- The current date stays available through the CLI date arguments for evidence continuity.

**Night, no moon.** Unchanged (new moon).

**Event (FW-MOON-10/11).** Proposed: "Total lunar eclipse, 18 Oct 2032", 19:00 UT, the copper moon 17° up in the east in full darkness (45 min of totality inside the pilot's view). The first candidate, 31 Dec 2028, rises in totality but in civil twilight at 3.5°, and the moon barely shows ([FW-MOON-10 §3](../research/field-world/FW-MOON-10/README.md#3-at-the-reference-field-the-eclipse-event)); 2026–2033 has no other total eclipse in front of the pilot in darkness.

## 7. Steps

| ID | Work | Proof / status |
| --- | --- | --- |
| FW-MOON-00 | Audit, accuracy vs NASA SVS, pilot-view survey, sources and plan. | Delivered 2026-10-19: [evidence](../research/field-world/FW-MOON-00/README.md), [sources](../research/field-world/FW-MOON-00/sources.json). |
| FW-MOON-01 | Render-path spike on pinned 4.7.2: radiance re-render on per-frame sky uniform changes with ambient COLOR; stepping at ×1/×20 in the pilot and close-up cameras; cloud-occlusion parity across the nine sky profiles; directional-light/shadow limits for a second moon light; cost. | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-01/README.md), DECISIONS row): candidate A. No radiance rebuild in field-world mode (engine source + cost amplifier); per-frame moon −1.9 ms paired (noise); zoomed pilot sees 8–21 px steps; a second shadowless light is free in draw calls. |
| FW-MOON-02 | `Lunar` float64 state: size, orientation (IAU pole/W, χ, q, libration), airmass, extinction, KS91, earthshine, eclipse geometry, rise/transit/set. `tools/world/moon_fixtures.py` writes Horizons (Madrid, Buenos Aires, Tromsø) and SVS-2026 subset fixtures with queries and credit. | Delivered 2026-10-19: 1102/1102 checks ([evidence](../research/field-world/FW-MOON-02/README.md)); worst position 4.0′, rise/set 1.2 min, libration 0.09°, eclipse magnitude 0.031. Not yet wired to rendering. |
| FW-MOON-03 | Correctness fixes, no new assets: per-pixel lit brightness from surface brightness, physical earthshine, disc out of the cubemap pass, distance-based size, horizon colour from the sky table's direct beam, shadow opacity by phase, planar shadow fade. (Night clouds already follow the moon: the sky shader's `sun_dir` is the active light.) | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-03/README.md)): lunar-Lambert disc normalised to KS91 (±1 %), physical earthshine, sky-table horizon colour, eye adaptation of the disc, moon shadows by phase (full 1.0, crescent 0.11); `test_world_moon_sky` 62/62. Cubemap-pass removal moved to FW-MOON-03b |
| FW-MOON-03b | FW-MOON-01 outcome: the moon disc and the stars move every frame, interpolated between flow steps as a pure function of the simulation clock; per-frame writes only while the radiance is unused; the disc skips `AT_CUBEMAP_PASS`. | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-03b/README.md)): `test_world_moon_flow` 23/23; rendered 6° track: max per-frame motion 0.21 px (stepped: three 14.1 px jumps), identical at the steps. |
| FW-MOON-04 | Texture intake: SVS 2k colour plus LOLA-derived normal map, provenance, credit, reproducible `--check`. | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-04/README.md)): SVS 2k colour + LOLA 1k normal map, provenance, reproducible `--check`, `test_world_moon_assets` 21/21 |
| FW-MOON-05 | Textured, oriented, photometric disc with flattening and extinction colour; daytime moon at physical contrast. | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-05/README.md)): eight SVS overlays, orientation ±0.5°, albedo detail r 0.53–0.81, lit IoU 0.79–0.97; refraction squash 0.86 on the horizon; AgX-tuned display levels |
| FW-MOON-06 | Moonlight: physical colour and extinction, continuous rise/set, sun↔moon hand-off without flip, cloud and eclipse dimming. | Light-energy curve test across moonrise; no frame-to-frame jump above a bound; twilight capture strip. Delivered 2026-10-19 for continuity and hand-off ([evidence](../research/field-world/FW-MOON-06/README.md), DECISIONS row): 06a continuous refraction (removes a 0.65° sun/moon drop and a 26 % twilight jump), 06b sun shadows fade with the setting disc and flow steps drive engine shadow opacity, 06c the sky keeps both lobes and weights cloud shading by source; `test_world_moon_light` 33/33, four mutations caught; rendered Moonrise evening: worst sky jump 11.2× → 2.8× its neighbours, renders identical to the bit with the sun up. Extinction and cloud dimming already applied (sky table, profile `sun_intensity`). 06d (2026-10-19) the slow sky terms follow per frame between steps in twilight and under a low light, so no frame jumps (zenith ≤ 0.15 % per frame where a step was 13.8 %). Moved: physical colour to FW-MOON-07 (it is the look mapping), eclipse dimming to FW-MOON-10. |
| FW-MOON-07 | Night look Eye / Cinematic / Camera. | Captures of all three; test that lamp colours are unchanged; blinded comparison feeds M-D4. |
| FW-MOON-08 | Aureole, thin-cloud transmission, corona, 22° halo by profile, star washout, moon glare, lake moon road check. | Gallery of nine profiles × moon; halo radius 21.8 ± 0.3° measured on capture; star count vs angle test; cost table. Partly delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-08/README.md)): 08a aureole (KS91 aerosol peak anchored to the moonlit zenith, scaled by aerosols, eye-adapted; rendered/predicted 1.01, nine-profile gallery; `test_world_moon_aureole` 23/23); 08b star washout analysed with KS91 + Crumey 2014: the peak lowers the limit ≤ 0.12 mag, so no per-star threshold (FW-24's calibration already carries the global drop). A derived knee (0.005^γ of the disc as shown) keeps close-up limbs clean. Open: thin cloud and corona, 22° halo, glare, lake road. |
| FW-MOON-09 | One moon on every route: TOD astronomical time, pause editor, "View at night", Natural Random, helicopter; `moon` block in the visual context (replaces `"not-modelled"` with TOD). | Route-matrix test; TOD tests updated with the owner. |
| FW-MOON-10 | Eclipses: umbra/penumbra shading, Danjon colour, light/sky/star response. | Espenak contact times within the tolerance M-D9 sets; 2028-12-31 moonrise capture. Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-10/README.md), DECISIONS row): penumbra by the solar disc's visible fraction, umbra from Ugolnikov et al. 2011's measured 677/503 nm curves, per pixel on the disc; the disc average dims the moonlight, its sky and aureole, and opens the eye; the aureole's knee follows the eclipsed disc. Contacts within 2.9 min of Espenak for total eclipses (shallow 2028-01-12: 8.9 min); 2022-05-16 totality V −1.67 vs measured −0.8 ± 0.3 (one eclipse's air); `test_world_moon_eclipse` 27/27, three mutations caught; captures of the 2028-12-31 phases, its moonrise and 2032-10-18. |
| FW-MOON-11 | `moon_view` solver, Moonrise flowing preset, retargeted full-moon night, eclipse event. | Solver tests at the reference place; pilot-view captures show the moon; owner choice. Partly delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-11/README.md)): `moonrise` 2026-09-26 20:20 (az 89°, el 5°), Home "Moonrise, time passing" from golden hour at ×20, `night` retargeted to 2026-09-27 22:00 (az 92°, el 19°, 98 %); `test_world_moon_presets` 23/23. Open: eclipse event (FW-MOON-10 proposes 2032-10-18 19:00 UT; `moon_capture.gd` case `eclipse_field_2032`), owner choice (M-D3). |
| FW-MOON-12 | `openrc-moon-config v1`, CLI/env, `[moon]` preferences, visual checkpoints. | Delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-12-13/README.md)): `moon_config.gd`, CLI/env, `[moon]` preferences, phase choice moves the date (±15 days), off/large/bright in SkyState; `test_world_moon_config` 53/53 (preference round trip added) |
| FW-MOON-13 | Moon group in Conditions and pause dialogs, live preview, rise/set readout and jumps, Home label and brief, "Tonight", es.po. | Partly delivered 2026-10-19 ([evidence](../research/field-world/FW-MOON-12-13/README.md)): Moon, phase, size and moonlight choices with a live summary in Conditions → Time of day and pause → Sky and lighting, applied in place, saved, es.po; `test_ui_moon_controls` 13/13. Open: preview disc, rise/set jump buttons, Home label, "Tonight" |
| FW-MOON-14 | Acceptance: target-GPU cost, FW-36 blinded readability across phases and looks, owner night review. | Cost table; review record; Gate FW-N input. |

**Order, in reviewable milestones:**
1. **Right moon, everywhere:** 01 → 02 → 03 → 03b → 09.
2. **Options in the menu:** 12 → 13, usable with the corrected disc.
3. **Beautiful moon:** 04 → 05 → 06 → 11.
4. **Atmosphere and events:** 07 → 08 → 10.
5. **Acceptance:** 14.

Each step is one small change with its own proof. Run `app/test.sh`, the relevant captures and the golden-flight check after each one.

## 8. Validation sources

- **NASA SVS 5587, "Moon Phase and Libration, 2026".** Hourly phase, diameter, distance, sub-Earth and subsolar points and axis angle for all of 2026. North-up frames for overlays.
- **JPL Horizons API (DE441).** Topocentric az/el, rise/transit/set, observer sub-longitude/latitude, north-pole position angle.
- **Espenak.** Eclipse contacts and phase catalogue.
- **KS91** for flux and sky brightness; Palle 2016 and Montañés-Rodríguez 2007 for earthshine; Kyba 2017 for measured lux.

Software checks prove consistency with these sources. They do not close pilot readability or target-GPU acceptance.

## 9. Owner decisions

| ID | Question | Default if unanswered |
| --- | --- | --- |
| M-D1 | Ownership and prefix: FW-MOON under Field world; the parked TOD-10 moon reservation points here. | Yes. |
| M-D2 | Render path. | **Resolved by FW-MOON-01:** sky-shader disc (candidate A), moved every frame. |
| M-D3 | Night presets: add "Moonrise, time passing"; retarget "Night, full moon" to an in-view date (re-records FW-23/FW-84 night captures, visual only). | Add Moonrise; retarget with captures. |
| M-D4 | Default night look. | Eye if the FW-MOON-07 blinded comparison does not reject it; otherwise Cinematic (today's look). |
| M-D5 | Offer non-physical options (large disc, bright moonlight), off by default and labelled. | Yes. |
| M-D6 | Texture resolution. | SVS 2k colour and 1k normal map; 4k only when a telescope-class camera needs it. |
| M-D7 | Astronomical TOD time renders night through the FW world renderer (one calibrated night), keeping TOD clock and checkpoint contracts, instead of adding a moon to the TOD curves. | Route through FW. |
| M-D8 | "Tonight" live sky from the system clock, resolved once and recorded. | Yes. |
| M-D9 | Upgrade to the Meeus ch. 47 moon for eclipses. | **Resolved by FW-MOON-02:** not needed (Schlyter: eclipse magnitude ±0.031, greatest eclipse ±3.75 min against Espenak). |

## 10. Risks and non-goals

**Risks:**
- Radiance churn or stepping (FW-MOON-01).
- Compatibility limits on two directional lights.
- 8-bit banding in halos (keep `use_debanding`).
- ACES, the day tonemapper, renders linear values below ~0.002 black. Night uses AgX, but earthshine at twilight needs a check.
- Texture LOD on a tiny disc.
- TOD/FW dual-path complexity (M-D7).
- llvmpipe is not a performance reference.

**Non-goals:**
- Enlarging the real disc near the horizon (the moon illusion is perceptual).
- Tides or any effect on flight physics.
- Planets.
- A volumetric atmosphere.
- A full-screen scotopic blur.
