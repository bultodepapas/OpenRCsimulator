# 06 · Ground textures without visible tiling

Date: 2026-10-05. **Question:** which anti-tiling and ground-material techniques work in a Godot 4.7 **Compatibility** spatial shader, stay byte-deterministic under llvmpipe, and give the pilot a readable runway, mown field and rough? What should L9 be, concretely?

## Findings

**Techniques (cost = texture fetches per pixel)**

| Technique | Fetches | Notes | Source |
| --- | --- | --- | --- |
| IQ technique 1: random offset/mirror per tile, blended at borders | 4 | Uses `textureGrad` with the original derivatives, so mipmaps don't break at offsets | [iquilezles.org/articles/texturerepetition](https://iquilezles.org/articles/texturerepetition/) [doc] |
| **IQ technique 3**: 8 offset "virtual tiles" selected by a low-frequency noise, blend of 2 | **2** | Cheapest. The article has **no code licence**, so we write our own code from the idea | same [doc] |
| Heitz & Neyret 2018 histogram-preserving blending | 3 + LUT | Needs a precomputed Gaussianised texture and an inverse LUT: extra offline tool | [eheitzresearch](https://eheitzresearch.wordpress.com/722-2/) [AP]; [Unity blog](https://blog.unity.com/technology/procedural-stochastic-texturing-in-unity) [sec] |
| **Mikkelsen 2022 hex-tiling** | 3 | Replaces the histogram transform with a luminance-weighted contrast ramp (`pow(w, 7)`); the paper is CC BY-ND 3.0, the **code is MIT** | [JCGT 11(3):5](https://jcgt.org/published/0011/03/05/paper-lowres.pdf) [AP]; [mmikk/hextile-demo](https://github.com/mmikk/hextile-demo) [repo], `hextiling.h` [src] |

- **The common Godot ports use `fract(sin(x)*43758.5453)` hashes** (Mikkelsen's own `hash()` too [src]). These depend on `sin` precision on each GPU. Hoskins' "Hash without Sine" is MIT and uses only `fract`/`dot` ([shadertoy 4djSRW](https://www.shadertoy.com/view/4djSRW), licence noted in [this issue](https://github.com/Jackicus/GNOME-Wallpaper-FX/issues/20)) [src]. We can't prove cross-GPU identity, but captures only need to match on one machine. [inference]
- `CAMERA_POSITION_WORLD` is a fragment built-in ([spatial shader docs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)) [doc]. It enables **view-dependent mowing stripes**.
- **Why lawn stripes show:** grass bent away from the viewer looks light, grass bent toward the viewer looks dark ([Grasshopper](https://blog.grasshoppermower.com/quickcuts/the-secret-to-perfect-stripes-lies-in-your-deck-height), [Wright](https://www.wrightmfg.com/articles/secrets-to-striping-lawns/)) [sec]. Stripes run along the runway (E–W), and the pilot looks across it (north). So in a real field **stripe contrast is weakest from the pilot box**, and the runway-to-rough **edge** carries the cue. [inference]
- **ambientCG grass:** Grass001–004 are **procedural**, CC0 and "ca. 1.4 m × 1.4 m" ([Grass001](https://ambientcg.com/view?id=Grass001)) [doc]. The API gives `dimensionX = 140` for Grass001–004 and 210 for Ground037. Grass005–008 (2025) give no size ([API query](https://ambientcg.com/api/v2/full_json?id=Grass001&include=dimensionsData,downloadData)) [measured]. The 1K-JPG zip is ~10 MB with all maps; we would ship only Color (and maybe NormalGL). A 1.4 m tile repeats 1 400 times across 2 km, so a photo-like texture **needs** hex-tiling or technique 3. [inference]
- **Anisotropic filtering in 4.7** has an open, unconfirmed report that it has no effect ([#123648](https://github.com/godotengine/godot/issues/123648), 2026-09-20, "needs testing") [iss]. An older Compatibility bug is tracked in [#79567](https://github.com/godotengine/godot/issues/79567) [iss].

**Spike (Godot 4.7.2, llvmpipe, `--rendering-driver opengl3`, copy of `app/` in scratch)** [measured]

I replaced the grass `StandardMaterial3D` with a `ShaderMaterial` that does these four things:
- world-space UV with the existing 256 px procedural tile (6 m);
- technique-3-style anti-tiling (2 `textureGrad` fetches, Hoskins hash);
- macro variation from value noise at 37 m and 160 m, ×0.84–1.12, plus yellowish dry patches;
- the field: a mown apron (220 × 120 m) with a noisy edge and darker rough (×0.74) beyond it, and the runway drawn in the shader (the runway mesh hidden) with 1.5 m stripes in alternating directions, brightness `1 ± (0.04 + 0.10·v.x)`.

| Capture | SHA-256 (run 1 = run 2) |
| --- | --- |
| baseline `--alt=3` | `6ed123c4…f96a` ✔ byte-identical |
| spike `--alt=3` | `7864fb88…96ef` ✔ byte-identical |
| spike default (30 m) | `a70d2f0b…fdeb` ✔ byte-identical |

- **The default 30 m view shows ground only in rows 711–719** (9 px), for both baseline and spike. **That view cannot judge any ground work**; only the low pass can.
- **Luminance (Rec.709, x 700–1280)** in the low pass:

  | Band | Baseline `StandardMaterial3D` | Same texture via shader (mode 0) | Full spike |
  | --- | --- | --- | --- |
  | Near rows 690–720 | 121.5 | 115.3 | 100.2 |
  | Far rows 385–410 | **144.5** | 117.4 | 103.7 |
  | Runway | 148.7 | 148.7 | 121 (stripes 111–129) |

- **The baseline's far grass washes out to almost runway brightness.** At the far runway edge (row ≈ 446, ~21 m away) the step is **6 %** in the baseline, 27 % with the shader at parity and ~14 % in the full spike. With the full spike, the stripe amplitude (±7 %) is as large as the edge step, so the edge reads weaker than it should. Writing `ROUGHNESS`/`SPECULAR` or not changes nothing (same numbers). **Cause not found**; a guess is a different filtering path for `uv1_scale` mesh UVs vs. derivatives from world-space UVs.
- Visually (zoomed crop), stripes, macro patches and the dark rough band read clearly.
- **My repeat metric failed.** Row autocorrelation in the grazing view peaks at the minimum lag (smoothness), not at the tile period. Repetition has to be measured in a **top-down** view.

Stripe and zone core from the spike (our own code; `vnoise` is value noise over the MIT Hoskins `hash12`):

```glsl
// in fragment(), p = world xz:
float aa = max(fwidth(p.x), fwidth(p.y));
float rough = smoothstep(-aa, 4.0 + aa, box_sd(p, mown_rect) + 5.0 * vnoise(p / 9.0));
col *= mix(1.0, 0.74, rough);
float on_rw = 1.0 - smoothstep(-aa, aa, box_sd(p, runway_rect));
float s = mod(floor((p.y - runway_rect.y) / stripe_m), 2.0) * 2.0 - 1.0;
vec2 v = normalize(p - CAMERA_POSITION_WORLD.xz);
col = mix(col, col * runway_tint * (1.0 + s * (0.04 + 0.10 * v.x)), on_rw);
```

## Libraries / tools found

| Name | Version / last activity | Licence | Compatibility / web? | Fit for us |
| --- | --- | --- | --- | --- |
| [mmikk/hextile-demo](https://github.com/mmikk/hextile-demo) | last push 2022-08-25 | MIT | HLSL; port is easy | Reference for hex-tiling if we ship photo textures |
| [Stochastic Hex-Tiling (Mikkelsen) port](https://godotshaders.com/shader/stochastic-hex-tiling-mikkelsens-adaptation/) | 2026-03-20 | MIT | GLSL ES, `textureGrad` (not tested here) | Good start; swap the sin hash |
| [Stochastic Filter for Hiding Tiling](https://godotshaders.com/shader/stochastic-filter-for-hiding-texture-tiling/) | 2025-01, updated 2026-02 | CC0 | 3 fetches, spatial | Alternative, CC0 |
| [Seamless sampler (IQ tech. 3)](https://godotshaders.com/shader/seamless-texture-sampler-without-repeating-patterns-tiling/) | 2025-08-12 | MIT | 2 fetches + noise texture | Same idea as the spike |
| [Terrain3D](https://terrain3d.readthedocs.io/en/stable/docs/tips_technical.html) `detiling_rotation/shift` | push 2026-10-03 | MIT | web experimental | Only with L18 |
| [ambientCG Grass001–008](https://ambientcg.com/view?id=Grass001) | 2021 / 2025 | CC0 | 1K/2K JPG | 1.4 m tile, procedural source |

## What this changes in LANDSCAPE-PLAN.md

1. **L0: add a top-down orthographic capture** (e.g. 60 × 60 m at 50 m) and keep the **low pass** as the ground review view. The default view shows 9 px of ground. *Proof:* byte-repeat; the baseline's top-down 2D autocorrelation peaks at the 6 m tile period.
2. **Split L9 into three steps:**
   - **L9a Ground shader at parity:** a `ShaderMaterial` with world-space UVs and the same procedural texture, no new features. *Proof:* byte-repeat; band luminances recorded against L0. The far-edge contrast goes from 6 % to ≥ 20 % (measured 27 %), which is an intended change and gets its own LEARNINGS line.
   - **L9b Anti-tiling + macro:** IQ technique 3 (2 fetches, own code, Hoskins MIT hash, no `sin`, no `TIME`), macro noise at 2 scales. *Proof:* the top-down autocorrelation peak at 6 m drops below a threshold set from L9a (e.g. ≤ 50 % of it); mean band luminance within ±5 % of L9a.
   - **L9c Field zones:** mown apron, rough, and runway drawn **in the ground shader** from the `openrc-field v1` rectangles (L5). The runway mesh at −0.01 m goes away, and with it the z-fighting risk. The stripes are view-dependent, and their amplitude stays ≤ ½ of the runway-to-grass step, so the edge stays the strongest cue. *Proof:* a column profile across both runway edges in the low pass. The step at each edge is ≥ the L9a value minus a tolerance, and the stripe ripple is less than the edge step.
3. **Photo textures (ambientCG) are optional and come later (L9d):** only if Gate L asks. Then use hex-tiling (MIT, 3 fetches) and size the tile from ambientCG's dimension (1.4 m). *Proof:* the same top-down test, plus the download delta.
4. **E-steps / L12:** surface type (runway / mown / rough) comes from the **same field rectangles** as the shader, so friction and visuals agree without a splatmap. Add a splatmap texture only when shapes stop being rectangles (L13/L17).

## Not confirmed

- Why the `StandardMaterial3D` far ground is 23 % brighter than the same texture through a shader. Is anisotropic filtering active at all in 4.7.2 Compatibility (#123648)?
- Cost on real GPUs. llvmpipe was not timed, per the plan's rule.
- The hex-tiling Godot port was not run. The cross-GPU visual equality of the hashes was not tested.
- The mower width of 1.5 m is an estimate (common deck widths); real club fields may use 2–3 m gang mowers.
