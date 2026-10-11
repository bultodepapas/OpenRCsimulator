# FW-24 — Stars and moon; Compatibility colour findings

**Status:** engineering-verified 2026-10-10. Code: [stars.gd](../../../../app/render/world/stars.gd), [stars.gdshader](../../../../app/render/world/stars.gdshader), [engine_srgb.gdshaderinc](../../../../app/render/world/engine_srgb.gdshaderinc), moon disc in [sky.gdshader](../../../../app/render/sky.gdshader). Data: [stars.json](../../../../app/data/sky/stars.json) from [stars.py](../../../../tools/world/stars.py) and the [Yale Bright Star Catalogue](../../../../assets/sky/PROVENANCE.json). Test: [test_world_stars.gd](../../../../app/tests/test_world_stars.gd) (13 checks).

## What was done

- 5,080 stars (V ≤ 6.0) as one MultiMesh of camera-facing quads (1 draw), turned by local sidereal time and latitude. Chosen over the plan's star cubemap: point stars stay round near the pole, no 4096² texture, and depth hides them behind hills and trees for free.
- Physical brightness (V = 0 ≈ 2.1·10⁻¹¹ of the sun's illuminance, spread over the quad) × a documented display gain of 25; extinction 0.2 mag per airmass; the sky's own cloud deck hides them; 7 Hz scintillation on `sim_clock`.
- Moon: 0.52° disc in the sky shader, terminator from the true sun direction, 2 % earthshine; brightness from Allen's phase law; clouds hide it.

## Results

- Sirius, Vega and Altair land within 0.01° of `Ephemeris.horizontal`; Polaris stands at the latitude's height, due north.
- Night captures (WSLg llvmpipe, 1280×720, south view 30° up): about 340 star pixels on a moonless night, 290 under the full moon (sky brighter), none in civil twilight.

## Engine findings (Godot 4.7.2 Compatibility, read in the pinned source and measured)

1. **Every material's `ALBEDO` and `EMISSION` go through the engine's cubic `srgb_to_linear`** (`drivers/gles3/shaders/scene.glsl` line 2398), unshaded included. A constant unshaded 0.3 rendered grey 54 at noon, exactly the cubic-then-ACES prediction (0.3 → 0.073). Faint values are divided by ~13 (the cubic's slope at zero is 0.0125): stars and lamp sprites came out ~40× too dim until the shaders encoded their linear output with the cubic's exact inverse (`engine_srgb.gdshaderinc`, the same fix L2 applied to the sky's `COLOR`).
2. **The sky's radiance cubemap already contains the exposure** (`sky.glsl`, cubemap pass: `color *= exposure` before encoding) and `scene.glsl` multiplies ambient by the exposure again. Harmless at the calibrated 0.6; at night exposures of 10⁴–10⁵ every lit surface turned white. Time-of-day mode therefore uses an ambient colour anchored to the calibrated look (FW-23).
3. **Godot's ACES fit has a black point:** `(x(x + A) − B) / …` is ≤ 0 below x ≈ 0.0037 after the 1.8 bias, i.e. linear values under ~0.002 render black. It shapes how dark a moonless night can be shown and why point lights need a minimum on-screen size.
4. Headless runs keep no MultiMesh instance data (already a known lesson): star placement is tested through the pure `Stars.placements()`.

## What it does not prove

Precession since J2000 (~0.36°) is not applied. The display gain is a judgement checked on llvmpipe captures, not on the owner's monitor. Licence of the catalogue: factual data, no explicit licence in the distribution; owner review requested (D-7).

## Reproduce

`python3 tools/world/stars.py --check`; `$(app/get-godot.sh) --headless --path app --script res://tests/test_world_stars.gd`; `tools/world/capture_times.sh <out> night night_dark blue_hour`.
