# 09 · Outdoor lighting, tonemapping and airplane readability

Date: 2026-10-05. **Question:** With Godot 4.7.2 Compatibility, which tonemapper, exposure, sun colour, ambient, glow and flare settings keep the Ugly Stik easiest to read against sky, grass and treeline, while captures still repeat byte for byte?

## Findings

### A. Spike: tonemapper vs plane contrast [measured]

Setup: a scratch copy of `app/` (never `app/`). `ProceduralSkyMaterial` (top `#3d74c4`, horizon `#c9dcef`), ambient and reflections from the sky, `Sky.PROCESS_MODE_QUALITY`, `tonemap_white` 1.0, glow off. One capture per setting: `--capture --t=1.5 --alt=3 --autozoom=0`, xvfb + llvmpipe, 1280×720.
- **Plane mask:** a second capture with `airplane.root.visible = false`. Pixels whose RGB sum differs by more than 12 between the two captures are the plane (52 px, a 17×6 px box at the horizon).
- **Metrics:** Weber W = (L_plane − L_bg)/L_bg on relative luminance (sRGB decoded). "Sat" = mean (max−min) RGB of the sky behind the plane.

| Setting | L_bg | L_plane | W (mean) | px with \|W\|<0.1 | ΔE76 | Sky sat |
| --- | --- | --- | --- | --- | --- | --- |
| Today (colour sky, `BG_COLOR`) | 0.551 | 0.261 | −0.53 | 13 % | 38.1 | 83 |
| Linear | 0.638 | 0.285 | −0.55 | 0 % | 36.4 | 46 |
| Filmic, exp 1.0 | 0.800 | 0.406 | −0.49 | 13 % | 36.7 | 28 |
| **Filmic, exp 0.8** | 0.700 | 0.338 | −0.52 | 13 % | 36.0 | 30 |
| ACES, exp 1.0 | 0.848 | 0.414 | −0.51 | 13 % | 39.6 | 20 |
| ACES, exp 0.8 | 0.756 | 0.342 | −0.55 | 13 % | 38.9 | 24 |
| AgX, exp 1.0 | 0.483 | 0.228 | −0.53 | 8 % | 32.5 | 21 |
| AgX, exp 1.4 | 0.572 | 0.298 | −0.48 | 13 % | 31.8 | 18 |

- **The tonemapper hardly changes how the plane reads.** W stays between −0.48 and −0.55 in every setting. That is 10–25× above the 0.02 (Koschmieder) and 0.05 (ICAO) thresholds (see D).
- **The plane is always a dark silhouette.** No plane pixel is brighter than the sky behind it (max W ≤ +0.02). Its white parts (`#f7f6f1`) blend into the bright horizon sky: about 13 % of plane pixels have |W| < 0.1.
- **The tonemapper does change the sky.**
  - Filmic and ACES at exposure 1.0 push the horizon close to white (L 0.80–0.85).
  - AgX turns the clear sky grey (sat 18–21, against 46 for Linear) and the grass olive, so the scene looks overcast.
  - Filmic at exposure 0.8 keeps the sky blue, keeps W at −0.52, and stops the grass looking lime.
- **Determinism:** AgX run twice gave byte-identical PNGs (`80862590…`). Glow on (intensity 0.3, bloom 0, HDR threshold 0.9) run twice gave byte-identical PNGs (`0ee524d9…`). Glow changed 71 % of pixels by a mean of 1.15 levels (max 43), which is invisible in this view.

### B. What Compatibility 4.7 offers

| Topic | Fact | Source |
| --- | --- | --- |
| Tonemappers | All five live in GLES3 `tonemap_inc.glsl`. AgX uses the allenwp curve with SDR `output_max_value = 1.0` | [src](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl) |
| AgX controls | Since 4.6: `tonemap_agx_white` (default 16.29, min 2.0) and `tonemap_agx_contrast`. `tonemap_white` does **not** affect AgX | [src PR #106940](https://github.com/godotengine/godot/pull/106940), [rel 4.6](https://godotengine.org/releases/4.6/) |
| Auto exposure | Forward+ only: exposure is a constant for us | [doc](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html) |
| Glow | Only Bloom, Intensity and HDR Threshold are available; blend is always Screen. Since 4.6 glow blends before tonemapping and the default intensity is 0.3 | [doc](https://docs.godotengine.org/en/stable/classes/class_environment.html), [src PR #110671](https://github.com/godotengine/godot/pull/110671) |
| Colour-grading LUT | 1D and 3D LUT in GLES3 `post.glsl`, applied after tonemapping | [src](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/effects/post.glsl), [doc](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html) |
| Physical light units | GLES3 scene code honours them. `Light3D.set_temperature()` does nothing unless `use_physical_light_units` is on | [src rasterizer_scene_gles3.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp), [src light_3d.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/light_3d.cpp) |
| Procedural sky | `use_debanding` is on by default. Sun discs come from up to 4 `DirectionalLight3D`s (`sun_angle_max` 30°, `sun_curve` 0.15) | [doc](https://docs.godotengine.org/en/stable/classes/class_proceduralskymaterial.html) |

### C. Sun colour vs elevation

- Godot docs: a clear day is 5500–6000 K; sunrise or sunset is about 1850 K [doc](https://docs.godotengine.org/en/stable/tutorials/3d/physical_light_and_camera_units.html).
- Condit & Grum 1964 measured 4840 K (light haze) to 5960 K (clear) at 40° solar altitude [AP](https://opg.optica.org/josa/abstract.cfm?uri=josa-54-7-937).
- `Spec.SUN` is at 45°, so about 5200 K is a sensible value [inference].
- We should not turn on physical light units just to get a colour temperature: that means re-tuning everything in lux. Instead, we can reproduce Godot's own `_color_from_temperature` (CIE 1960 → sRGB). It gives the following [measured, Python port of the function above]:

| K | 3500 | 4500 | 5000 | **5200** | 5500 | 6000 |
| --- | --- | --- | --- | --- | --- | --- |
| `light_color` | `#ffc78b` | `#ffddbc` | `#ffe6d0` | **`#ffe9d7`** | `#ffede1` | `#fff3f1` |

### D. Readability: thresholds and the livery

- **Thresholds:** the classic photopic contrast threshold is 0.02 (Koschmieder). ICAO's meteorological optical range uses 0.05, and ICAO notes that objects are seen when their contrast with the sky is above 0.05 [doc](https://amc.namem.gov.mn/wp-content/uploads/ICAO/19.%209328_cons_en_2018.pdf?_t=1638837866), [sec](https://en.wikipedia.org/wiki/Visibility).
- **Small targets:** Blackwell 1946 shows the threshold rising steeply for small targets (50 % detection, unlimited viewing time) [AP](https://www.bbastrodesigns.com/blackwel.html). A field multiplier of 2–3× is common practice [not confirmed]. A 14 px Stik at 200 m therefore needs |W| well above 0.1.
- **Busy backgrounds:** ATSB 1991 describes "contour interaction": cluttered backgrounds (ground features, clouds) make an aircraft's outline harder to separate [doc](https://www.atsb.gov.au/publications/1991/limit_see_avoid). A treeline behind the plane is the hard case, not the sky.
- **Dark on light sky:** in daylight an aircraft is usually seen as a dark shape against a lighter sky, and black is often cited as the most conspicuous colour [F](https://www.pprune.org/archive/index.php/t-296276.html). Our spike agrees: W ≈ −0.5 against the sky.
- **Livery vs background** [inference, albedo luminance only, no lighting]:

| Background (Y) | Red `#c8102e` (0.128) | White (0.920) | Black (0.006) |
| --- | --- | --- | --- |
| Horizon sky `#c9dcef` (0.698) | −0.82 | +0.32 | −0.99 |
| Grass `#4a7a32` (0.156) | **−0.18** | +4.9 | −0.96 |
| Dark treeline `#2e4a26` (0.056) | +1.3 | +15 | −0.89 |
| Hazy treeline at 400 m `#7f95a0` (0.285) | −0.55 | +2.2 | −0.98 |

- **Red over grass is the weakest pair in luminance** (low passes, viewed from above). Hue difference rescues it, since red against green is a large chromatic contrast. So the readability check must measure both W and ΔE.
- Aerial perspective (L2) helps: it lifts a treeline from Y≈0.06 to ≈0.3, so the black and red parts read darker against it.

### E. Sun glare and lens flare in Compatibility

- **TranquilMarmot "Lens Flare for Godot 4"** [doc](https://godotshaders.com/shader/lens-flare-for-godot-4/):
  - a CC0 canvas-item shader on a `TextureRect`;
  - `blend_add`, no `SCREEN_TEXTURE`;
  - the sun position comes from `Camera3D.unproject_position()`;
  - occlusion is done on the CPU with a ray.
  - With no screen texture it should run in Compatibility and on WebGL 2 [inference].
- `CompositorEffect`-based flares (ARez2) run on RenderingDevice, so they are Forward+/Mobile only [inference from the API].
- Pattern for our own version:

```gdscript
# CanvasLayer child; sun_dir = unit vector toward the sun (from Spec.SUN). MIT, ours, untested.
func _process(_d: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var p := cam.global_position + sun_dir * 1000.0
	var uv := cam.unproject_position(p) / get_viewport().get_visible_rect().size
	flare.visible = not cam.is_position_behind(p) and Rect2(-0.2, -0.2, 1.4, 1.4).has_point(uv)
	flare.material.set_shader_parameter("sun_uv", uv) # occlusion: our own float64 ray (L12/L14)
```

- Losing the plane in the sun is a real RC hazard. The glare should come mostly from the sky's sun disc plus glow. Ghost flares are a camera artefact; the pilot's eyes have none [inference].

## Libraries / tools found

| Name | Version / last activity | License | Compatibility / web? | Fit |
| --- | --- | --- | --- | --- |
| Godot built-in Filmic/ACES/AgX + glow + LUT | 4.7.2-stable | MIT | ✅ / ✅ | Use Filmic; glow is optional; LUT only if Gate L asks for a grade |
| Lens Flare for Godot 4 (TranquilMarmot) | godotshaders page | CC0 | ✅ likely / ✅ likely | Reference for an optional flare step |
| [GD_LensFlares](https://github.com/GoldenThumbs/GD_LensFlares) | pushed 2025-04-21, no releases | MIT [repo] | not confirmed | Texture-atlas flares; heavier than needed |
| [compositor-effect-lens-effects](https://github.com/ARez2/compositor-effect-lens-effects) | pushed 2026-07-05, no releases | MIT [repo] | ❌ (CompositorEffect) | Not for us |
| Python + Pillow + NumPy plane-contrast script (spike) | Pillow 11.3.0 | — | offline | Becomes the L0 readability metric |

## What this changes in LANDSCAPE-PLAN.md

1. **L0 (add a readability metric).** Each review view is captured twice, with the plane shown and hidden. A script prints the plane's pixel count, mean W, the share of plane pixels with |W| < 0.1, and mean ΔE76.
   - Today's baseline at the 3 m view: W = −0.53, 13 %, ΔE 38.1.
   - Proof: the numbers are recorded in the plan, and both captures byte-repeat.
2. **L1 (pin the settings).**
   - Tonemap Filmic, `tonemap_exposure` 0.8, `tonemap_white` 1.0.
   - Ambient source Sky with `ambient_light_sky_contribution` 1.0 and energy 1.0; reflections from Sky; `Sky.process_mode` QUALITY; glow off.
   - All of these live as one `Spec.LOOK` dictionary.
   - **Proof:** at the 3 m view the plane has W ≤ −0.40, |W| < 0.1 on ≤ 15 % of its pixels, ΔE ≥ 30, and sky sat ≥ 25 (not grey); bytes repeat.
   - AgX is rejected for a sunny field (measured grey sky).
3. **L3 (sun shadows).**
   - Sun `light_color` `#ffe9d7` (5200 K at 45°, computed with Godot's formula), with no physical light units.
   - Re-tune `light_energy` after shadows (#90259) so that a sunlit white wing stays at L < 0.95 (no clipping) and the L1 contrast proof still passes.
4. **New L6b "treeline readability", after L6.** Add review views with the plane in front of the treeline and over grass (low pass).
   - Proof: |W| ≥ 0.3 **or** ΔE ≥ 20 in every view; red over grass is expected to pass only on ΔE.
   - If it fails, tune the L2 fog density before touching the livery (the livery belongs to the model team).
5. **L19 (time of day) gains an optional "sun glare" sub-step.**
   - Glow on: intensity 0.3, bloom 0, HDR threshold 0.9 (byte-repeat measured).
   - An optional CC0-style flare on a CanvasLayer, with occlusion from our own float64 ray.
   - Proof: the toward-the-sun review view and a capture byte-repeat.

## Not confirmed

- Whether the CC0 flare shader and `tonemap_agx_contrast` behave the same on WebGL 2 as on llvmpipe.
- Field multiplier on Blackwell thresholds for small moving targets, and daylight threshold values at 3–15 arcmin (the Blackwell table found is for astronomical luminances).
- The Condit & Grum value is daylight (sun + sky), not direct sun alone; the 5200 K choice is an interpolation.
- Glow's effect with the sun disc in frame (not captured; this spike looked at the horizon only).
- The spike measured one view (52 px plane, horizon background); treeline and grass numbers are albedo estimates.
