# L9c-R1 — stripe sampling reference

**Status (2026-10-08): bounded stripe-filter regression verified; perceptual and target-GPU acceptance remain open.** Follows the [L9c ground-pass proof](../L9c/README.md). No production shader, field, or physics change.

## Question and method

Does the production mowing-stripe filter reduce sampling error without erasing nearby detail? L9c's surface-on/off motion score includes expected camera motion and cannot answer this alone.

The new capture fixture uses production field geometry, lighting, ground material, and frozen shader time. At each pose it subtracts a `stripe_amp=0` image from the normal image. It renders the same raw-square-wave mutation at 8× and 16× resolution, decodes the PNGs to linear RGB, and box-averages each high-resolution pixel block. This yields a stripe-only reference for each camera position. The reference is independent of the production filter's formula.

For stripe residuals `S`, two camera positions `0, 1`, and the 16× reference `R`:

- Spatial error: `RMS(S - R)` across both positions.
- Temporal error: `RMS((S1 - R1) - (S0 - R0))`. The reference's expected camera motion is subtracted.
- Reference disagreement: the same errors for 8× against 16×. Twice this measured disagreement is an engineering separation margin, not a statistical bound or proof of convergence.

The two grazing views are 100 m and 300 m oblique views with 10° vertical FOV. Both filtered errors must be lower than raw errors by more than the separation margin. A threshold view checks nearby detail: deleting all stripes must be worse than keeping the filter, beyond the same spatial margin. These are regression checks, not human visibility thresholds.

Each view renders a 640×64 sub-frustum of the original 1280×720 image. The crop is centred horizontally; its top row is 328 for the oblique views and 416 for the threshold. Camera translation always uses half a **base-resolution** pixel at target depth. Position and projection are checked across resolutions. The fixed measurement mask contains pixel centres inside the runway inset by one metre, intersected across both camera positions. A one-pixel image erosion would remove the distant runway entirely.

The native filtered run repeats in a separate process with identical PNG hashes and render metadata. The acceptance function is also run with the raw output and with zero stripe contribution; both controls must fail. Raw-shader mutation is confined to an imported project copy.

## Results

Godot 4.7.2, Compatibility/OpenGL, Mesa llvmpipe 25.2.8, one render thread. All three views passed; 12 native images repeated byte-for-byte in an independent process. Both negative controls were rejected. Temporal errors below are RMS in linear RGB on [0, 1], not perceived flicker ratings.

| View | Mask pixels | Filtered temporal error | Raw temporal error | 8×/16× disagreement | Error reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| Oblique 100 m | 5,311 | 0.002051 | 0.012398 | 0.001479 | 83.5% |
| Oblique 300 m | 310 | 0.003680 | 0.019431 | 0.005466 | 81.1% |
| Near threshold | 40,358 | 0.002467 | 0.004009 | 0.000445 | 38.4% |

Spatial error fell by 81.4% at 100 m and 83.3% at 300 m. At the threshold, filtered spatial error was 0.001758 versus 0.031514 after removing the stripes; nearby detail is retained. The 300 m reference disagreement is larger than the filtered error itself: this supports improvement over raw sampling, not a precise absolute-error claim.

The full-frame/sub-frustum comparison found a maximum projection discrepancy of 0.000244 base pixels and a maximum per-image mean absolute RGB difference of 0.002399 byte levels. A few pixels differed by up to 7 levels; this was not claimed as byte parity. The existing surface fixture's four images and all capture records remained exactly equal to L9c's prior output. The production ground shader, builder, atmosphere, and field-data hashes still match L9c.

Four measurement unit tests pass; the capture script parses in Godot; `bash -n app/capture.sh` passes. Static project lint remains at zero errors and the same 12 existing warnings. The capture logs contain no engine errors; Xvfb reports the existing unsupported V-Sync warning. No production logic changed, so the full physics suite and complete multi-track `app/capture.sh` pipeline were not repeated.

Saved proof: [summary](summary.json), [native capture manifest](filtered-capture.json), [8× reference](reference8-capture.json), [16× reference](reference16-capture.json), [crop comparison](crop-parity.json), [legacy parity](legacy-parity.json), and [unit tests](unit-tests.log). Renderer logs and all five manifests are alongside this report. Native crops: [filtered 100 m](filtered-100m.png), [raw 100 m](raw-100m.png), [filtered 300 m](filtered-300m.png), [raw 300 m](raw-300m.png). High-resolution PNGs are reproducible outputs, not runtime assets.

## Reproduce

```bash
"$(app/tests/visual-env.sh)" tools/ground/test_stripes.py
"$(app/tests/visual-env.sh)" tools/ground/check_stripes.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l9c-stripe-reference
```

`app/capture.sh` invokes both checks and hashes the resulting summary in its complete-run manifest. Output must be new or empty; engine errors, incomplete images, mismatched projections, or stale output fail the run. Supersampling needs an OpenGL framebuffer up to 10240×1024; the ordinary app still renders at its configured resolution.

## Limits and references

Two camera positions and three fixed crops do not establish perceptual absence of shimmer, cover all field layouts, or close owner/target-GPU Gate L. Software-renderer elapsed time is not a performance result. The 8×/16× comparison measures reference disagreement; it does not bound all remaining reference error. Earlier full-frame 2×/4× references were too undersampled to separate the grazing-view filter effect reliably and were not accepted.

The production triangle-integral square filter is mathematically consistent; its uniform one-dimensional footprint remains an approximation to a projected two-dimensional pixel. This step adds a defensible regression measurement instead of tuning the appearance to an ambiguous motion score.

- [PBRT: texture sampling and antialiasing](https://pbr-book.org/4ed/Textures_and_Materials/Texture_Sampling_and_Antialiasing): filtering and supersampling principles.
- [PBRT: image reconstruction](https://pbr-book.org/4ed/Sampling_and_Reconstruction/Image_Reconstruction): box-filter limitations.
- [Godot Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html): cropped frustum API; signatures checked against the pinned 4.7.2 engine.
- [Godot spatial shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html): Compatibility output colour space.

Tooling and derivation are original project code under the repository license. No new runtime assets or dependencies.
