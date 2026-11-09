# L8a-R5 Tree-card leaf lighting

2026-11-09 · Landscape **L**. Addresses the material comparison in section 2C of `external Audits/VEGETATION.MD`. Builds on the [matched source families](../L8a-R3/README.md) and [Fagus mesh backlighting](../L8a-R4/README.md).

The distant oak, beech and pine cards now use a neutral backlight coefficient, **0.25**, restricted by the existing source-material foliage mask. Opaque trunks and branches no longer receive the leaf contribution. The old expression multiplied backlight by albedo before Godot multiplied the diffuse light by albedo again. The [pinned Compatibility renderer](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/gles3/shaders/scene.glsl#L1581) adds backlight to diffuse, then [applies albedo](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/gles3/shaders/scene.glsl#L2736). Supplying a neutral coefficient preserves a single leaf-color multiplication.

This is an authored direct-light approximation. Coefficients 0.10, 0.25 and 0.35 were compared under fixed front, side, rear and ambient-only illumination for all three source families. The 0.10 candidate was too dark; 0.25 retains a restrained leaf response and opaque bark. This does **not** close the whole mesh/card appearance gap: crown normals, depth and ambient response still differ.

The production change is confined to `treeline.gdshader`. It reuses the existing atlas and mask, with no added texture, batch, geometry, density or processing loop. Alpha coverage, wind, normals, representation selection, positions and collision/physics remain unchanged. Existing scene-detail presets continue to select their normal card populations.

## Verification

[Machine-readable receipt](lighting-review.json), with source identities, image hashes, checked commands and measured pixel differences. Native Windows, Godot `4.8.beta2.official.cafc17a19`, Compatibility/OpenGL, RTX 3090, NVIDIA `617.42`:

- The new native regression reproduces two failures on the old shader: bark changes by up to **34/255**, and the albedo-normalized gain ratio is **1.9880**. The candidate passes **5 checks**, with bark delta **0**, normalized ratio **0.9696**, and ambient-only delta **0**. The controlled regression uses 192² pixels; it is separate from 1080p visual review.
- The source/card fixture captures all three families at **1920×1080**, under four fixed light conditions. Diagnostic sweeps isolate the original expression, mask-only treatment and neutral leaf treatment. The receipt retains the coefficient trials and final production comparison rather than treating a diagnostic shader as the shipped shader.
- All **12 selected-trial/production** and **12 repeated-production** card comparisons are pixel-identical. All three ambient-only card views retain the baseline pixels, as do all five night field pairs. Dusk retains faint direct sun above the lighting profile's −0.8333° cutoff; its field differences reach **1/255**, so dusk is not presented as exact ambient parity.
- **25 matched field pairs at 1920×1080** cover pilot, zoomed woods, aerial, car park and close western cards under legacy lighting, noon, positive low sun (**6.849°**), dusk (**−0.653°**) and night (**−88.082°**). Camera, light context, wind and draw/primitive counters agree within each pair. The initial eastern close-view attempt was poorly framed and excluded; a corrected western view was captured in fresh folders.
- Focused tree-runtime checks pass (**26,473 checks**), as do detailed-tree selection and imported-tree assets. The detailed-tree test intentionally emits one warning for its invalid LOD-option guard. The native pixel test passes; its headless invocation explicitly skips framebuffer checks.

Raw PNGs, reports and logs remain in ignored `tmp/vegetation-card-lighting-20261109/`. No capture image is added to Git. Use the [tree tools guide](../../../../tools/trees/README.md#tree-card-lighting-l8a-r5) to reproduce the comparisons.

These static SDR snapshots contain no aircraft simulation and do not qualify moving/zoomed flight readability, Field World's moonlit/flowing sky, other renderers or GPUs, exported builds, or the combined frame-time allowance. Equal geometry counters are not a performance result. Shared-workspace changes outside the listed source identities were preserved and are outside this verification.
