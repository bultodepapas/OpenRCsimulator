# 01 · Sky and cloud shaders that run in Compatibility

Date: 2026-10-05. **Question:** which open-source Godot 4 sky shaders (gradient, sun disc, clouds) work in the Compatibility renderer, how do they make clouds, handle the radiance pass and banding, and what exact shader should steps L1 and L4 use?

## Findings

**What the GLES3 sky path does in 4.7.2** (read from the `4.7.2-stable` source):

- **Built-in debanding exists.** `render_mode use_debanding;` makes `drivers/gles3/shaders/sky.glsl` add interleaved gradient noise (±1/255, seeded from `gl_FragCoord`, no time) after tonemapping and sRGB conversion. We don't need our own dither. Sources: [sky.glsl L132-138, L275](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/sky.glsl) [src], [PR #60641 "Use IGN instead of white noise for sky dithering"](https://github.com/godotengine/godot/pull/60641) [rel].
  - It dithers the final 8-bit value only while tonemapping runs in the sky pass; glow, SSAO, adjustments or 3D scaling move it to post ([rasterizer_scene_gles3.cpp L2393-2422](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)) [src].
- **Automatic process mode turns incremental as soon as the shader has any uniform** (`ubo_size > 0`) or reads `LIGHT*`. `TIME` or `POSITION` turns it real-time, which re-renders the radiance every frame ([L690-708](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)) [src]. Any change to a uniform marks the radiance dirty. So set `Sky.process_mode = QUALITY` explicitly, and change uniforms rarely.
- **Half- and quarter-resolution passes are parsed but never rendered in GLES3.** `use_half_res_pass` sets a flag ([material_storage.cpp L2846](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/material_storage.cpp)) that `rasterizer_scene_gles3.cpp` never reads [src]. Shaders built on `HALF_RES_COLOR` (MMqd, "AAA Fake Volumetric Clouds") lose their clouds in Compatibility [inference].
- **`LIGHT0_SIZE` is the light's `light_angular_distance` in radians, and it is a diameter** ([L768-769](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)) [src]. It defaults to 0, so the light gives no disc [measured: `light_angular_distance_deg 0.0`]. `ProceduralSkyMaterial` draws the disc where `dot > cos(LIGHT0_SIZE)`, so its disc radius equals the full diameter: twice the real size ([sky_material.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/sky_material.cpp)) [src][inference]. Our shader should take the sun's size from its own `Spec` uniform.
- **The radiance cubemap is RGB10_A2**, 32-2048 px per face ([L545-627](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp)) [src].

**Existing shaders:**

| Shader | Clouds | Uses `TIME` | Passes | Sun | Dither |
|---|---|---|---|---|---|
| [Sky3D v2.1.0](https://github.com/TokisanGames/Sky3D/blob/v2.1.0/addons/sky_3d/shaders/SkyMaterial.gdshader) [src] | **Textures** (`noiseClouds.png`, `noise.jpg`); cirrus = 2 texture taps; cumulus = 10-step raymarch on a 500-unit sphere, 4-octave fbm from 2D-texture "pseudo-3D" | **Yes**, `current_time = TIME` (star twinkle) → real-time radiance every frame | none | hard `step(size, dist)` disc | `use_debanding` |
| [MMqd Nishita](https://github.com/MMqd/godot-nishita-sky-with-volumetric-clouds) (MIT, last push 2023-07) [repo] | 3D textures `worlnoise`/`perlworlnoise` + weather map, raymarched | Yes | **half/quarter res** (not rendered in GLES3) | Nishita scattering | no |
| [Stylized Sky Shader with Clouds](https://godotshaders.com/shader/stylized-sky-shader-with-clouds/) (CC0, 2023) [F] | 3 sampler textures (NoiseTexture2D) with domain distortion | Yes | none | `distance(EYEDIR, LIGHT0_DIRECTION)` ramp | no |
| [Procedural Sky Blended Cover, Wind, and Clouds](https://godotshaders.com/shader/procedural-sky-blended-cover-wind-and-clouds/) (CC0, 2025-04, 4.4) [F] | `sky_cover` texture | Yes | none | `LIGHT0_SIZE` disc + curve | `use_debanding` |
| [Cartoon Sky Shader](https://godotshaders.com/shader/cartoon-sky-shader/) (CC0, 2026-08) [F] | **in-shader** integer hash + quintic value noise, 3-octave fbm | Yes | none | smoothstep disc | no |
| [AAA Fake Volumetric Clouds](https://godotshaders.com/shader/aaa-fake-volumetric-clouds/) (CC0, 2026-05) [F] | textures | Yes | half res | `pow(dot,120)` + glow | no |

- **All but MMqd read `TIME`; most need noise textures** (runtime `NoiseTexture2D` = FastNoiseLite, not guaranteed identical across OSes).
- **Hash choice:** [Jarzynski & Olano 2020](https://jcgt.org/published/0009/03/02/) [AP] test GPU hashes: "LCG and trig are obviously bad, with visible banding, linear artifacts, and repeated patterns." They recommend pcg2d/pcg3d. The integer hash in the Cartoon shader uses Hoskins's "Hash without Sine" constants ([MIT](https://compute.toys/view/15)) [sec]. Integer hashes are exact on every conforming GPU. The noise interpolation is still float maths, so captures are only guaranteed to repeat on one driver [inference].
- **Skip limb darkening:** the 0.53° sun is ~7 px wide at 720p and tonemaps to white [measured]; size and halo matter more [inference].

**Spike** [measured], run in a scratch copy of `app/` with Godot 4.7.2 and Mesa llvmpipe under xvfb. It used a [77-line shader](#spike-shader): gradient, ground skirt, a flat cloud deck from a 5-octave in-shader fbm, a sun disc and halo, `use_debanding`, no `TIME`, no textures. Settings: `Sky.process_mode = QUALITY`, radiance 256, ambient from the sky, Filmic tonemapping.

| Capture | SHA-256 (first 12) | Result |
|---|---|---|
| `--alt=3`, run 1 and run 2 | `824c7e1cdba3` ×2 | **byte-identical** |
| default view (30 m), run 1 and run 2 | `fdfef96c7604` ×2 | **byte-identical** |
| default view, without `use_debanding` | `81df260e2d8c` | 98 unique colours vs 347 in a 170×105 px strip of lower sky; longest run of identical pixels down a column **7 px vs 2 px** |
| default view, background = `texture(RADIANCE, EYEDIR)` | `00dc06b0e99c` | works in GLES3, but the mean sky is **+30/255 brighter** (mean RGB 183/220/247 vs 153/195/237) and softer (256 px faces) |
| sun moved into the view (12° up, 10° right of the camera's forward direction) | `2803bd23f3d1` | disc centroid (527.8, 189.4) vs `unproject_position` (528.3, 190.0): **0.6 px off** |

- Look: at 30 m a deep-to-pale blue gradient with soft cumulus fading into haze; at 3 m clouds above a pale horizon band. ~2.1-3.3 s per capture.
- Side effect: `AMBIENT_SOURCE_SKY` + Filmic visibly lightens the grass, so L1 changes the lighting baseline too.

<a id="spike-shader"></a>Core of the spike shader. Ours, MIT. The hash constants are from Hoskins's MIT hash. Full file: `scratchpad/inv-01/app/render/sky.gdshader`, not committed.

```glsl
shader_type sky;
render_mode use_debanding;
uniform vec2 cloud_offset = vec2(0.0); // seed + drift from SIM time, never TIME
float hash2(ivec2 c) {
	uvec2 q = uvec2(c) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}
// value_noise: quintic fade of 4 hash2 corners; fbm: 5 octaves, x2.03, rotated
vec3 sky_color(vec3 dir) {
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(zenith_color.rgb, horizon_color.rgb, pow(1.0 - up, gradient_curve));
	if (dir.y > 0.0) {
		vec2 deck = dir.xz / max(dir.y, 0.02);           // flat cloud layer
		float n = fbm(deck * cloud_scale + cloud_offset);
		float d = smoothstep(1.0 - cloud_coverage, 1.25 - cloud_coverage, n)
		        * smoothstep(0.02, 0.25, dir.y);          // fade into haze
		col = mix(col, cloud_color.rgb * mix(0.95, 0.82, d), d);
	} else { col = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.08, -dir.y)); }
	float ang = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
	float r = sun_radius;                                 // from Spec, not LIGHT0_SIZE
	col += LIGHT0_COLOR * (exp(-ang * 18.0) * 0.35 + 4.0 * (1.0 - smoothstep(0.9 * r, 1.1 * r, ang)));
	return col;
}
void sky() { COLOR = sky_color(EYEDIR); }
```

## Libraries / tools found

| Name | Version / last release | License | Compatibility / web? | Fit for us |
|---|---|---|---|---|
| [Sky3D](https://github.com/TokisanGames/Sky3D) | v2.1.0, 2026-05-19 | MIT (J. Cuéllar; Petkovsek) | Yes per README (Compatibility needs "Sky Contribution 0.75, Fog Density 0.01"); reflection probes broken in Compatibility ([#43](https://github.com/TokisanGames/Sky3D/issues/43)) | **No as a dependency**: `TIME` forces real-time radiance, noise comes from textures, day cycle we don't need. Useful as a reference for Mie phase tint and the cirrus layer |
| [MMqd Nishita + volumetric clouds](https://github.com/MMqd/godot-nishita-sky-with-volumetric-clouds) | no release; push 2023-07-01 | MIT | **No**: needs half/quarter-res passes | No |
| [SunshineClouds2](https://github.com/Bonkahe/SunshineClouds2) | push 2026-09-27 | MIT | No (compute compositor) | No |
| godotshaders.com (above) | 2023-2026 | CC0 | Yes, except AAA | Ideas only |
| Godot built-in `use_debanding` (sky) | in 4.7.2 | MIT | Yes | **Use it** |
| [Jarzynski & Olano hashes](https://jcgt.org/published/0009/03/02/) | 2020 | paper (code in supplement) | GLSL ES 3.0 `uint` OK | pcg2d if the value-noise hash ever shows patterns |

## What this changes in LANDSCAPE-PLAN.md

1. **L1: replace "ordered dithering" with `render_mode use_debanding`** (built in, deterministic). Also:
   - Set `Sky.process_mode = QUALITY` explicitly; the shader has uniforms, so automatic mode would pick incremental.
   - The sun's size comes from a `Spec` uniform (0.53°), not from `LIGHT0_SIZE`.
   - Draw the background per pixel, **never from `RADIANCE`** (measured +30/255 and blurred).

   **Proofs:**
   - Two runs give identical bytes (done in the spike: `824c7e…`, `fdfef9…`).
   - Zenith pixel darker than horizon pixel in every L0 view.
   - Sun centroid within 2 px of `unproject_position` (spike: 0.6 px).
   - **Banding test:** the longest run of identical pixels down a sky column stays ≤ 3 px (spike: 2 vs 7 without debanding).
2. **Split L1 into L1a (background sky shader, ambient unchanged) and L1b (`AMBIENT_SOURCE_SKY` + Filmic re-tune).** The spike showed ambient-from-sky visibly brightens the ground and the model. Proof for L1b: a new L0 baseline and an airplane luminance check in the 30 m view.
3. **L4: clouds from an in-shader integer-hash value-noise fbm on a flat deck (`dir.xz/dir.y`), no textures, no `NoiseTexture2D`.**
   - The seed is `cloud_offset` from `Spec`.
   - Drift: update the uniform from sim time at **≤ 1 Hz**. Each change rebuilds the 6-face radiance cubemap with QUALITY mode.
   - Fade the clouds into the horizon with `smoothstep(0.02, 0.25, dir.y)`.
   - **Proofs:** byte-repeat; same sim time → same hash; t vs t+10 s differs only above the horizon row; a radiance-rebuild counter shows ≤ 1 rebuild per second.
4. **Add to Risks:** no half/quarter-res sky passes in GLES3; third-party skies use `TIME`; debanding weakens once glow/SSAO/adjustments are on.

## Not confirmed

- Why `RADIANCE` reads back brighter (cubemap-pass tonemap or sRGB handling; not traced).
- GPU cost of the 5-octave fbm per pixel on real hardware and WebGL 2. The cost of a QUALITY radiance rebuild at 256 px.
- Whether `light_angular_distance` > 0 changes shadow softness in Compatibility.
- Whether captures are identical across GPUs or drivers. They only repeat on llvmpipe.
- Whether the post-pass debanding is good enough once glow is enabled.
