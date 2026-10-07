# L15d · GPU cloud-density and projection probe

Date: 2026-10-07. **Status: the shared density and projection probe passes; this does not close L15d cloud-shadow integration or visual acceptance.** Godot 4.7.2 Compatibility, Mesa llvmpipe.

## Scope and method

`tools/atmosphere/probe_clouds.gd` rasterizes the actual `app/render/cloud_field.gdshaderinc` `cloud_density` function into one 3,072 × 256 PNG atlas. The twelve panels cover 64-cell x/y shifts at positive and negative coordinates, a pilot-origin sky/ground projection pair, a deliberately wrong-sign control, the two sides of a drift wrap, and zero coverage. Every GPU result carries a range/finite sentinel. The checker reads the quantized PNG; periodic and projection comparisons allow at most 2/255 per sample.

The stress sample uses seed 1253, coverage 0.55, cluster strength 0.65, a 1,500 m deck, and cloud scale 6.0. The projection panel varies ground x/z over ±1,500 m and height from 0–100 m. With the 225°/45° render-space sun `(-0.5, 0.70710678, 0.5)`, the ground expression `p.xz + (1500 - p.y) * sun.xz / sun.y`, scaled by `6/1500`, is compared with the corresponding ray slope from the pilot origin, also scaled by 6.

## Result

Two independent GPU processes produced byte-identical PNGs (SHA-256 `1ca3a0ffe6c4b2c798c7d1ef585b591c6721c386d097c8782c0924bf2f8f81c0`). The density channel spans all 256 byte levels; the GPU range sentinel had zero failures, and zero coverage returned zero in every pixel.

| Check | Maximum byte delta | Result |
| --- | ---: | --- |
| +64 cells in x / y | 1 / 1 | Pass |
| +64 cells from negative x / y | 0 / 0 | Pass |
| Ground projection vs corresponding sky ray | 1 | Pass |
| Drift at 63.999 vs 0.001 cells | 5 (p99 2) | Pass; gate is max 8 and p99 4 |
| Deliberately reversed sun offset | mean 151.87; 92.53% of samples changed | Detected |

For a checker mutation, a copy of the atlas had its correct ground-projection panel replaced with the wrong-sign control panel. `check_cloud_probe.py` rejected it at the projection comparison (max delta 255; 92.53% of samples changed). The candidate was copied to a temporary app directory before rendering, so the candidate app was not modified. Before and after hashes matched: shared include `d81a737759b3cf63249a99afcfca708ffa3e0c0442c31b7ff8ac136e049b4cce`, sky shader `e05c62adedf0cf4cb03f22917718c551e000260f2df55c136466dd7fb3609769`, ground shader `11a08b9e2d9e3d8113e969cd8c02d6c96446a45951d13aba86fed18e974e9eb0`.

## Reproduce

```sh
"$(app/tests/visual-env.sh)" tools/atmosphere/check_cloud_probe.py \
  --app app \
  --godot "$(app/get-godot.sh)" \
  --out /tmp/l15d-cloud-probe
```

The script compiles the shared include dynamically and needs no editor import. The output directory can be reused; a second invocation at the same path passed. The checker removes its prior summary first, clears only its two repeat directories and known logs, and rejects unowned entries. It writes `summary.json` only after all checks pass.

## Limits

This probe establishes deterministic compilation and numeric agreement for the shared density function on software OpenGL. It does not prove the production `sky.gdshader` and `ground.gdshader` consumers use the function correctly, quantify final ground-light response, establish target-GPU performance, or replace visual review.
