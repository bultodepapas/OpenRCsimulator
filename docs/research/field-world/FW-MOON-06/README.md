# FW-MOON-06: a continuous twilight hand-over between sun and moon

**Status:** engineering-verified 2026-10-19 on llvmpipe. This is a declared visual change for twilight and night with the sun below 0.5°. With the sun's disc above 0.5° (day, golden hour, the sunset preset), renders are identical to the bit, except 1-of-255 differences while a moon below the horizon is between −3° and −1°. Between steps (06d), flowing sessions now render the slow sky per frame in twilight and under a low light; the frames at each step are unchanged. The calibrated Day scene, explicit time-of-day snapshots and physics are unchanged. It covers the plan's continuity and hand-off items. The physical moonlight colour moves to FW-MOON-07, because it is the night-look mapping. Eclipse dimming moves to FW-MOON-10.

- Code:
  - [ephemeris.gd](../../../../app/render/world/ephemeris.gd) (`refraction_deg`);
  - [sky_state.gd](../../../../app/render/world/sky_state.gd) (`sun_shadow_strength`, `cloud_light_weights`, the second lobe);
  - [atmosphere.gd](../../../../app/render/atmosphere.gd) (`_apply_shadow`, sky uniforms) and [sky.gdshader](../../../../app/render/sky.gdshader) (second lobe, two cloud lights). These two are shared with VQ/Landscape; their default uniforms keep every snapshot and day sky byte-identical.
  - [world.gd](../../../../app/render/world/world.gd) (06d: `frame_state`, `_apply_frame_sky`, `frame_sky_needed`, `visual_state`).
- Tests: [test_world_moon_light.gd](../../../../app/tests/test_world_moon_light.gd); the refraction checks in [test_world_ephemeris.gd](../../../../app/tests/test_world_ephemeris.gd); 06d in [test_world_moon_flow.gd](../../../../app/tests/test_world_moon_flow.gd).
- Scripts: [research/field-world/fw-moon-06/](../../../../research/field-world/fw-moon-06/):
  - `light_audit.gd` + `analyze_audit.py`: the state, step by step;
  - `twilight_strip.gd` + `analyze_strip.py`: renders, one per step;
  - `frame_track.gd` + `analyze_frames.py`: renders, frame by frame (06d).

## 1. Audit: what jumped at twilight

`light_audit.gd` steps the field-world state every 30 s of sky, as `World.flow_to` does, through four scenes at the reference field:
- the Moonrise preset's evening (2026-09-26, sun and moon opposite);
- a 19 % waxing crescent after sunset (2026-06-18, both on the same side);
- a gibbous moon setting while the sun rises (2026-10-29);
- a full moon high all night (2026-10-25, control).

Results: [before](audit-before.md), [after](audit-after.md).

| Defect (before) | Where | Size |
| --- | --- | --- |
| Refraction cut to zero below a true elevation of −1°, where it is 0.65° | `Ephemeris.refraction_deg` | The sun dropped from −0.30° to −1.03° in one step. The twilight sky, ambient and exposure jumped: displayed lit ground −26 % (\|ln\| 0.296) at every flowing sunset and sunrise. The moon did the same at moonrise and moonset. |
| The light swapped to the brighter direct source with the sun's shadows still at 1.0 | `SkyState.state` | The direction flipped 177° (Moonrise), 50° (crescent) and 137° (dawn), with shadow strength 1 → 0 in one step. The planar pilot shadow, the projected shadows and the PSSM switched with it. |
| Flow steps never switched the engine shadows | `Atmosphere.apply_light` | `shadow_enabled` stayed as built (on at a golden-hour start) through the night. |
| The sky shader's clouds and horizon lobe follow one source | `sky.gdshader` | At the light swap, the clouds' lit side, silver edge and relief flipped while the sun's twilight still lit them. In deep twilight the west glow (2.3× the haze) moved east in one step (−57 % looking west). Later the clouds' direction flipped again when the sun's cloud term in the sky table ended at −1.5°. |

The full-moon control night has no event: per step, the light moves at most 0.12° and the displayed brightness changes by at most 0.17 %.

## 2. What changed

1. **06a: continuous refraction.** Saemundsson's formula is unchanged from −1° up, so every solver and every daytime position is bit-identical. Below −1° it tapers linearly from 0.65° to zero at −3°. The apparent elevation is continuous and monotonic; its rate is at most 1.32× the true rate over those two degrees. The lunar fixtures still pass 1102/1102 against Horizons.
2. **06b: shadows hand over at zero.**
   - The sun's shadow strength is its disc's direct beam relative to the beam at 0.5° (`sun_shadow_strength`): 1 from 0.5° up, 0.40 with the disc on the horizon, 0 from −0.5°, where the table's beam ends. The light then passes to the moon when both strengths are ≤ 0.09.
   - Flow steps now drive the engine shadows (`_apply_shadow`): the switch, and the PSSM opacity equal to the strength. A crescent's or a setting sun's PSSM fades like the projected and planar shadows. The calibrated day and snapshots keep the on/off switch at full opacity.
3. **06c: the sky shows both sources.**
   - **Lobes.** Beside the brighter lobe (still the one the ground's haze uses), the sky draws the other source's lobe. The west glow fades at the sky table's own pace instead of jumping east.
   - **Cloud shading.** Each source's weight in the clouds' directional shading is its share of their direct light. The split is the same 0.8 direct / 0.2 sky as `cloud_lin`, divided by the day's 0.8.
   - While the sun's disc is up, its weight is exactly 1. As the disc sets, the weight blends into the measured share. From a sun at −1.5° until the moon's light on the clouds outgrows the sky's (sun about −8° to −12°, depending on the moon), the clouds are lit by the sky alone and lose their directional shading; then the moon's weight grows.
   - The relief takes the larger weight's direction and the weights' difference as its strength, so it fades instead of flipping.
   - Defaults (1, 0) and a zero second lobe reproduce the previous shader exactly.

**Not changed.** The ground's single directional light still swaps sides, but at that moment both direct terms are ≈ 0 of the ambient (direct/ambient 0.0000 → 0.0000 in all three scenes). A second engine light would have to be taught to the five custom ground shaders (`ground`, `near_grass`, `water`, `bank`, `ridge_haze`), with no visible gain.

## 3. Verification

| Check | Result |
| --- | --- |
| `test_world_moon_light.gd` | 33/33. Refraction continuous and zero at −3°. Sun shadow strength 1 / partial / 0 and monotonic across the horizon. In all three twilight scenes: one light swap; the sun never drops more than 0.15° per step; shadows hand over at ≤ 0.1 and change ≤ 0.15 per step; the clouds' weighted shading direction moves ≤ 0.25 per step; the visible sun-side glow never loses more than 40 % in a step. Day sky exactly (1, 0) with full shadows. Flow steps set PSSM opacity; the day and snapshots keep 1.0. The sky uniforms are written in flow and cleared for a snapshot. |
| Mutations (disposable copy, one at a time) | Hard refraction cut: 13 checks fail (sun drop 0.731°, swap shadow 0.163, glow loss 0.519). Sun shadows always full: 8 fail (1.000). Clouds following the light only: 3 fail (direction jump 1.86–2.00). One lobe: 2 fail (glow loss 1.000). |
| `test_world_ephemeris.gd` | 34/34, with new continuity checks: monotonic apparent elevation from −6° to +2°, and a setting sun dropping ≤ 0.15° per 30 s. |
| Existing tests, working tree | `test_world_flow` 26/26, `test_world_moon_flow` 23/23, `test_world_moon_sky` 62/62, `test_world_moon_config` 53/53, `test_world_moon_lunar` 1102/1102, `test_world_moon_presets` 23/23, `test_world_sky` 38/38, `test_world_stars` 22/22, `test_landscape_twilight` 394/394, `test_landscape_horizon` 37/37, `test_sky_render` 30/30, `test_world_presentation_context` 17/17, `test_world_field_lights` 86/86, `test_ui_moon_controls` 13/13, `test_time_of_day_scenery_update` 25/25, `test_field_projected_shadows` 57/57. |

### Rendered twilight

[twilight_strip.gd](../../../../research/field-world/fw-moon-06/twilight_strip.gd) renders the Moonrise evening under the "broken" sky (two cloud decks) from the pilot's eye. One frame per 30 s sky step from 19:00 for 3 h, 361 steps, looking east (az 88°) and west (az 268°) at 8° pitch, 70° field of view, 480×270, llvmpipe.

[analyze_strip.py](../../../../research/field-world/fw-moon-06/analyze_strip.py) measures each step's relative mean absolute change in the sky (top 55 %) and the ground (bottom 30 %). Its *pop factor* is that change divided by the median of the ten neighbouring steps: about 1 is the twilight's own pace, much more is a jump.

Before and after ran on the same tree, before the owner's 13:10 merge, with only this step's four files differing ([before](strip-before-summary.json), [after](strip-after-summary.json)):

| View, region | Largest pop, before | Largest pop, after |
| --- | --- | --- |
| West sky | 11.2× at sun −1.03° (the refraction drop; 26 % change in one step) | 2.4× at sun −1.40° (the sky table's sunlight leaving the deck) |
| East sky | 8.9× at sun −1.03° | 2.8× at sun −1.53° (same) |
| West ground | 12.5× at sun −1.03° | 11.5× at sun 10.30°, the same frames as before (see findings) |
| East ground | 12.0× at sun −1.03° | 11.9× at sun 11.24°, the same frames as before (see findings) |

![Before and after through the hand-over](twilight-strip.jpg)

Rows are sky steps; columns are before (east, west) and after (east, west).
- 66.5–67 min: the refraction drop darkens the clouds and ground in one step before; after, nothing jumps.
- 125 min (sun −12°): after, the moon's rising glow already shows in the east; before, it appeared only at the lobe swap.
- 136 min (sun −14.3°): before, the west's red arch vanished in one step; after, it fades at its own pace.

**Byte identity with the sun up.** The owner's merge brought other tracks' scenery changes at 13:10. So the final code was checked again with a fresh A/B on the merged tree: a disposable copy restored only this step's four files to `7f0f7ba2`.

| Window | Steps | Result |
| --- | --- | --- |
| 19:00, sun 11.7° → 11.1° | 7 | Identical to the bit, both views. |
| 19:45, sun 3.3° → 2.8° | 7 | At most 1 of 255, from 06a acting on the moon. It is still below the horizon at a true −1.2° to −0.5°, and its faint sky glow now follows the continuous refraction. All the sky uniforms of this step are at their defaults. |
| 19:48:30, sun 2.7° → 0.51° | 26 | Identical to the bit, both views. |
| 20:01:30, sun 0.43° → 0.18° | 4 | Differs as intended: the sun's shadows fade with the setting disc (strength 0.91 → 0.62). |

The day check in `test_world_moon_light.gd` also requires the exact default uniforms with the sun up: weights (1, 0) and no second lobe. A second lobe below 10⁻⁴ of the first is dropped. The first after-render showed 1-of-255 differences from a 10⁻⁶ moon lobe by day, which this removes.

## 4. FW-MOON-06d: the slow sky between the steps

The plan's proof asks for "no frame-to-frame jump above a bound". Per step that held after 06a–c, but per frame it did not.
- In nautical twilight one 30 s step darkens the sky about 14 %. At ×20 that is a visible jump every 1.5 s, and the eye's adaptation (0.35/s toward dark) catches up late.
- The same steps move the ground's cloud shadows: `ground.gdshader` projects them along `sun_dir`, so at a 10–11° sun one step shifts them about 90 m. The lit ground jumped ±8–10 % (the 11–12× ground pops in §3, identical before and after 06a–c).

**What changed** ([world.gd](../../../../app/render/world/world.gd) `frame_state`, `_apply_frame_sky`, `frame_sky_needed`, `visual_state`):
1. Between steps, `flow_frame` builds the frame's sky from this step's state and the next step's.
   - Colours and exposure terms are interpolated geometrically per channel (twilight falls exponentially); directions by slerp; the moon as in 03b.
   - Terms whose source changes inside the step keep the step's value for that one step, so nothing sweeps across the sky: the light passing between sun and moon, and the brighter lobe swapping sides.
   - Discrete terms keep the step's value: shadow strength, light source, tonemapper.
2. The frame sky is written through the step's own functions (sky, environment, light, haze materials, weather profiles included), and then the stepped `Atmosphere.state` is restored. Everything that reads the state or watches a signature keeps the step cadence: projected and planar shadows, scenery, airfield lights, the lake.
3. The lake's water material is left at the step. Its reflection probe re-renders whenever that material changes (LU's `lake_reflection.gd`).
4. The eye's adaptation goal (`view_exposure`) follows the frame sky (`visual_state`). Without a view target, the exposure is interpolated too.
5. **Gate** (`frame_sky_needed`): the frame sky runs only for steps that change the sky or light luminance by more than 0.4 %, or while the light is up but below 20°. Day, a high moonlit night and a moonless night stay stepped: no cost, and identical to before between steps.

**Verification:**

| Check | Result |
| --- | --- |
| `test_world_moon_flow.gd` | 31/31, with eight twilight checks added (Moonrise evening, sun about −6°). In 3 s at 60 fps, where one step changes the sky by more than 5 %: no frame changes the zenith by more than 0.5 % or the ambient colour by more than 2 %. `Atmosphere.state` stays the stepped state, and the lake's water keeps the step cadence. The adaptation goal rises smoothly. At a step instant the frame sky is the stepped sky, and replays are exact. |
| Mutation (gate always off, disposable copy) | 2 checks fail: frame jumps of 13.8 % (zenith) and 12.5 % (ambient). |
| Gate, by scene | On for golden hour (sun 8.9°), twilight, and a low moon (7°, 18°). Off for noon (39.6°), afternoon (27.8°), a high moon (39.3°) and a moonless night. |
| Production renders, [frame_track.gd](../../../../research/field-world/fw-moon-06/frame_track.gd) | 60 fps across two steps, 480×270, "broken" sky ([summary](frames-summary.json)). See the table below. |
| Existing tests | The world and moon battery as in §3 (18 suites), `test_windsock` 17/17 and `test_world_field_lights` 86/86, on a disposable copy. The copy was needed because local `main` at `0b5a6b6d` did not compile `field.gd`: it called a `Windsock.advance` that only `origin/main` (`b5df6c69`) provided. After the owner's merge `5cbddb02`, all 19 suites pass on the real tree. |
| Smoke | `--quick-flight --start=airborne --date=2026-09-26 --time=20:25 --time_scale=20`, 600 rendered frames: no errors. |
| Cost (llvmpipe VM, GDScript) | 118 µs per frame while the gate is on, and nothing more otherwise (the moon and stars of 03b stay at ~24 µs). One `SkyState` per step, as before. |

| Window | Mode | Mean level | Largest change per frame |
| --- | --- | --- | --- |
| Nautical twilight, west, sky | stepped | 58.8 | 1.52 levels (5.05 %) |
| | per frame | 58.1 | 0.02 levels (0.07 %) |
| Low sun 11.5°, east, ground with cloud shadows | stepped | 32.3 | 3.76 levels (19.1 %) |
| | per frame | 31.3 | 0.03 levels (0.16 %) |

The west ground in nautical twilight is black at the state's own exposure (mean below one display level) in both modes.

![Frames 44 and 45 around a step, and their difference ×8](frame-step.jpg)

In the stepped renders the whole ground (low sun: the cloud shadows hop) or the whole sky (twilight) changes at the step; per frame the difference is almost black.

**Limits:**
- The water's own shading and its reflection keep the step cadence until the lake probe can refresh on a coarser signature (LU).
- At the one step where the light or the brighter lobe changes source, those terms still step. Both direct terms are about 0 there, and the sky draws both lobes (06c).
- Gate thresholds are estimates. Target-GPU and target-CPU cost remain for FW-MOON-14.

## Findings for other steps

- **Twilight brightness and cloud-shadow steps (FW-61).** Resolved by FW-MOON-06d (§4).
- **Scenery shadows frozen during flow (FW-61 with SC).** `Scenery.update_lighting` runs only for explicit snapshots. In a flowing session the trees' directional shadows keep their build-time direction and full opacity all night: Moonrise preset, sun −7.4°, state strength 0, decal alpha 1.0. A full update costs 9–23 ms headless per call, so it needs a thresholded or incremental refresh in the scenery code, not one per sky step.
- **Ground haze lobe.** The ground and grass shaders still take only the brighter lobe, so their faint aerial-perspective tint changes sides at the lobe crossover (sun ≈ −14°). The sky itself no longer does.
- **Owner question.** Physically, a sun below about 10° casts faint ground shadows: its direct share on horizontal ground is a few percent at 1°. Today's full-strength sunset shadows are kept by design (accepted looks). Fading them with the share, as the moon's do, would be a separate look decision.
