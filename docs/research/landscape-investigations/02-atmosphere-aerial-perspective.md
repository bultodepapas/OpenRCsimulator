# 02 · Cheap atmospheric scattering and aerial perspective models

Date: 2026-10-05. **Question:** which sky and haze model gives a believable horizon and sun-dependent haze cheaply in LDR on Godot 4.7.2 Compatibility, with sky and fog colours from one source of truth?

## Findings

**Godot 4.7.2 Compatibility, read from source** (`drivers/gles3`, tag `4.7.2-stable`):

| Fact | Evidence |
| --- | --- |
| **`fog_aerial_perspective` does nothing on objects**: the block that samples the radiance map is commented out of `fog_process()`. The docs don't mention this | [scene.glsl L1981-1993](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L1978) [src]; [class_environment](https://docs.godotengine.org/en/stable/classes/class_environment.html) [doc] |
| Object fog colour = `fog_light_color·energy + Σ light_color·energy·π·pow(max(dot(view, L), 0), 8)·fog_sun_scatter` (×π comes from non-physical light units). Amount = `1−exp(−d·density)` or depth mode `smoothstep(begin,end,d)^curve·density`; height fog takes `max()` | [scene.glsl](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L1978), [rasterizer_scene_gles3.cpp L1751-1756](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L1751) [src] |
| **Sky fog has no horizon dependence**: the sky is mixed toward the fog colour by the constant `fog_sky_affect` in every direction, which tints the zenith too | [sky.glsl L142-156, 234-237](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/sky.glsl#L142) [src] |
| In a sky shader `LIGHT0_COLOR` is **sRGB** (scene lights are linear), and `LIGHT0_ENERGY` has no ×π. Copying the fog term with `LIGHT0_*` therefore gives a mismatch | [material_storage.cpp L1539-1541](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/material_storage.cpp#L1539), [rasterizer_scene_gles3.cpp L745-764](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L745) [src] |
| `render_mode use_debanding;` **works in GLES3 sky shaders** (interleaved gradient noise from `gl_FragCoord`, so it is deterministic). Material/scene debanding is a stub ("not yet implemented") | [sky.glsl L132, L275](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/sky.glsl#L132), [rasterizer_scene_gles3.cpp L4525](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp#L4525) [src] |
| Spatial shaders can write `FOG` (defines `CUSTOM_FOG_USED`, which replaces engine fog for that material) | [spatial_shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) [doc], [scene.glsl L2382](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L2382) [src] |
| `ProceduralSkyMaterial` = `mix(top, horizon, pow(1−y, 0.6/sky_curve))`; `PhysicalSkyMaterial` = Preetham-style with the three.js hack, and it is too dark in Compatibility (#84441 open) | [sky_material.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/sky_material.cpp#L328) [src]; [#84441](https://github.com/godotengine/godot/issues/84441) [iss] |
| Compatibility has no compute shaders, no RenderingDevice and no CompositorEffect, so Hillaire-style per-frame LUT passes are out | [renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) [doc] |

**Sky models compared**

| Model | Cost | Quality | Fit |
| --- | --- | --- | --- |
| Preetham 1999 | ~5 exp | Whole horizon turns orange at low sun; "unusable" for T < 2 | [Zotti & Wilkie 2007](https://www.cg.tuwien.ac.at/research/publications/2007/zotti-2007-wscg/zotti-2007-wscg-paper.pdf) [AP]. Avoid |
| **Hosek-Wilkie 2012** | 2 exp, 1 pow, 1 sqrt per channel; 9×3 coefficients from the CPU | Best analytic clear sky; turbidity 1-10; no twilight | Reference code is **BSD-3-Clause** ([header](https://github.com/ebruneton/clear-sky-models/blob/master/atmosphere/model/hosek/ArHosekSkyModel.cc)) [src]; [project page](https://cgg.mff.cuni.cz/projects/SkylightModelling/) [doc] |
| Bruneton 2008/2017 | 3 texture fetches | Accurate, includes aerial perspective | BSD-3; a 256×128×32 RGBA16F 3D texture (~8 MB), loaded as `.dat` files in its WebGL 2 demo ([constants.h](https://github.com/ebruneton/precomputed_atmospheric_scattering/blob/master/atmosphere/constants.h), [demo.js](https://ebruneton.github.io/precomputed_atmospheric_scattering/atmosphere/demo/webgl/demo.js.html)) [src]. Overkill for a static sun |
| Hillaire 2020 | LUTs; 0.14 ms on PC; aerial perspective volume 32×32×32 over 32 km | State of the art | [paper text](https://www.readkong.com/page/a-scalable-and-production-ready-sky-and-atmosphere-3211109) [AP], [repo MIT, DX11](https://github.com/sebh/UnrealEngineSkyAtmosphere) [repo]. Needs render-to-float passes, which we can't add in Compatibility |
| Nishita / [Lague](https://github.com/SebLague/Solar-System) (MIT) ray march | 8×4 to 16×6 samples ([top-sky](https://github.com/llama-nl/top-sky) [repo]) | Good, planet scale | Too costly for a static sun |

**Hosek-Wilkie colours for our sun** (elevation 45°, `Spec.SUN`). I evaluated the BSD-3 RGB dataset in Python [measured], with values scaled so that the anti-sun horizon's largest channel is 0.85:

| Direction | T=2.5 sRGB8 | Luminance vs anti-sun horizon (T=2.5 / 4) |
| --- | --- | --- |
| Zenith | `#4e6893` | 0.18 / 0.26 |
| 30° up, anti-sun | `#6184b3` | 0.30 / 0.36 |
| 10° up, anti-sun | `#9ac0e8` | 0.69 / 0.75 |
| Horizon, anti-sun | `#c9e3ed` | 1.00 |
| Horizon, 90° from sun | `#b1c8d1` | 0.75 / 0.79 |
| Horizon, toward sun | `#dff7fe` | 1.21 / 1.65 |

- Godot's gradient form `mix(zenith, horizon, pow(1−y, k))` fits these values with **k ≈ 2.6** (10°: 0.38, 30°: 0.83 blend weights), which is `sky_curve ≈ 0.23` [measured fit].
- The sun-side brightening (×1.2-1.65) is what `pow(cos γ, 8)·sun_scatter` approximates. The 90° dip (Rayleigh cos²γ) can't be expressed in Godot's fog [inference].

**Real-world haze**

- Koschmieder: a distant object's luminance tends to the **horizon sky luminance**, `L = L₀e^{−βd} + L_h(1−e^{−βd})`. The physics itself says: fog colour = horizon sky colour. Visual range is `3.912/β` (2 % contrast threshold) or `3.0/β` (WMO MOR, 5 %) ([Visibility](https://en.wikipedia.org/wiki/Visibility), [Wilson 2015](https://www.rtwilson.com/academic/WilsonMiltonNield_2015_VisAOT.pdf)) [sec][AP].
- Pure Rayleigh air: 296 km; haze: 2-5 km ([Visibility](https://en.wikipedia.org/wiki/Visibility)) [sec].
- MODTRAN defaults: rural **23 km = clear**, 5 km = hazy, and 23-50 km is "clear to very clear" ([DTIC ADA445003](https://apps.dtic.mil/sti/tr/pdf/ADA445003.pdf)) [doc].
- **Transmittance at 23 km (β = 1.7e-4 /m)** [computed]: 300 m 0.95, 600 m 0.90, 2 km 0.71, 5 km 0.43, 6 km 0.36.

**Consequences for us** [inference, computed]:

1. **Realistic haze doesn't hide a 6 km ground edge** (36 % contrast left). From the pilot's eye the edge is sub-pixel (0.016° below the horizon). From 100 m up it is 0.95° (~20 px at 1080p). The ground needs its own rim fade.
2. **Depth fog mode can't mimic haze.** The best `smoothstep^curve` fit gives 0.00-0.02 at 600 m against a physical 0.06-0.09.
3. **Fog can't hide L8's billboard pops at 400 m:** only 7 % haze there. A 20 m tree at 400 m is 2.9° tall, about 62 px.
4. Today `Spec.CAMERA.far = 3000` and the ground is ±1000 m (`app/spec.gd`). The ground has to grow and `far` with it.

**Snippet** (ours, MIT like the repo; the formula mirrors GLES3 `fog_process`):

```glsl
shader_type sky;
render_mode use_debanding;
// All set by render/atmosphere.gd from Spec.ATMOSPHERE (one source of truth).
uniform vec3 zenith_lin;     // linear
uniform vec3 haze_lin;       // == env.fog_light_color.srgb_to_linear() * fog_light_energy
uniform vec3 sun_dir;        // toward the sun == light.global_basis.z
uniform vec3 sun_lin;        // light_color.srgb_to_linear() * light_energy * PI
uniform float sun_scatter;   // == env.fog_sun_scatter
uniform float curve = 2.6;   // Hosek fit, T=2.5, sun 45 deg

vec3 haze(vec3 d) {          // what the engine fogs geometry toward, direction d
	return haze_lin + sun_lin * pow(max(dot(d, sun_dir), 0.0), 8.0) * sun_scatter;
}
void sky() {
	float y = max(EYEDIR.y, 0.0);  // below the horizon: pure haze
	COLOR = mix(haze(EYEDIR), zenith_lin, 1.0 - pow(1.0 - y, curve));
	// + sun disc; clouds later (L4) in AT_CUBEMAP_PASS
}
```

The ground shader writes `FOG = vec4(haze(view_dir_world), max(1.0 - exp(-beta*d), smoothstep(0.8*R, R, d)))` with the same uniforms. Other materials keep engine fog: exponential mode, `density = beta`.

## Libraries / tools found

| Name | Version / last release | License | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| Hosek-Wilkie code + RGB data | 1.4a (2013) | BSD-3 | Shader is ALU only | **Yes**: colours now, L19 later |
| Bruneton precomputed_atmospheric_scattering | push 2025-10 | BSD-3 | WebGL 2 demo; 3D float textures | No (size, complexity) |
| UnrealEngineSkyAtmosphere (Hillaire) | 2022 | MIT | DX11 only | Reading only |
| Sky3D | v2.1.0, 2026-05-19 | MIT | Yes, with fog/sky tweaks | Too much (day cycle) |
| top-sky | push 2026-09 | **none** | Claims Compatibility | Excluded (no license) |
| [iq fog article](https://iquilezles.org/articles/fog/) | — | none stated | — | Ideas only; write our own code |

## What this changes in LANDSCAPE-PLAN.md

- **L1, modified:** the gradient + horizon-match shader above.
  - Colours come from the Hosek table (labeled `[measured]`, BSD-3 credit).
  - Use `render_mode use_debanding` instead of hand-made dithering.
  - New `Spec.ATMOSPHERE = {zenith, haze, sun_scatter, mor_m = 23000 (MODTRAN "clear"), curve = 2.6}`. One `render/atmosphere.gd` sets the sky uniforms, the fog and the light.
  - **Proof:** a headless test (no GPU): the fog colour (linear) equals `haze`, `fog_sun_scatter` equals the uniform, `sun_dir` equals the light basis within 1e-6, `fog_sky_affect == 0` and `fog_aerial_perspective == 0`. Plus the planned capture and pixel tests.
- **L2, rewritten:**
  - Exponential fog with `density = 3.912/mor_m`. **Not** depth mode, and **not** `fog_aerial_perspective`.
  - Ground half-size ≥ 6 km, with a rim fade through custom `FOG`. `Spec.CAMERA.far` ≥ ground radius + 5 %.
  - **Proof:** (a) a float64 mirror of the fog gives 0.90 / 0.71 / 0.43 at 600 m / 2 km / 5 km; (b) at 1.7 m and 100 m eye height, no step > 2 levels across the ground rim rows in 4 azimuths, including toward the sun; (c) captures byte-repeat.
- **L7:** hills at 2-5 km get 29-57 % haze naturally and stay readable, as in reality. No forced fog.
- **L8, modified:** fog won't hide pops at 400 m. Switch billboards at ≥ 2 km (29 % haze), or accept the pops and measure them. Proof: a 10-frame strip across the switch, with a mean pixel delta below a threshold set from L0.
- **L19, refined:** time of day = per-pixel Hosek (the CPU cooks 27 coefficients when the sun moves), with `fog_light_color` taken from the same evaluation. Proof: the L1 equality test at 5 sun elevations.

## Not confirmed

- Whether the Hosek RGB dataset uses linear sRGB/Rec.709 primaries (assumed); the absolute brightness scale was chosen by hand.
- Whether aerial perspective stays commented out after 4.7.2. Grep `gles3/scene.glsl` on each upgrade.
- That the "4.6 fog blending change" applies to GLES3 at all: no `legacy` string in the GLES3 fog code.
- Ground fog banding without engine debanding (the grass texture probably masks it). Check in the L2 captures.
- Local visibility for the owner's field; 23 km is a generic default.
