# VQ-07b / LU-16-R2: recover mountain texture in High

2026-10-21. Implemented in the experimental High path. Windows, Godot 4.7.2
`ed1daf0bf`, RTX 3090 / NVIDIA 617.42, Forward+ Vulkan, 1920×1080, 4× MSAA.

[Interactive before/after](comparison.html), [before](high-baseline/lake.png),
[after](high-candidate/lake.png), [pilot view](high-candidate/pilot.png).
These are unmodified native images with identical scenery on both sides.
The separate vegetation team's assets are present in both; this change neither
authors nor modifies them.

## Cause and change

The two mountain photographs supply scalar modulation and biome thresholds,
using an authored sRGB-domain recipe. `source_color` made Forward+ decode those
samples before applying that recipe. Darker values hit its minimum clamps and
flattened variation. The shader also passed its encoded palette to linear ALBEDO.

Remove the color hint from these two control samplers and decode the completed
palette once on RD with Compatibility's existing cubic. Standard retains its
original arithmetic. No assets, import settings, geometry, normals, haze,
lighting, simulation, texture allocation or render passes change. The gain is
recovering existing downloaded detail with a small shader patch.

Engine references: [RD texture-view selection](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/storage_rd/material_storage.cpp),
[Compatibility ALBEDO conversion](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl),
[its cubic](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl),
and [shader renderer conventions](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).
The photos remain filtered in the encoded control domain, deliberately matching
the accepted recipe; they are not used as direct physical surface color.

## Verification

- **48 horizon checks pass:** topology, bounded mipmapped assets, shared material
  and explicit/flowing lighting updates.
- **11 native GPU palette cases pass on each renderer.** The original shader
  fails all eleven in Forward+. The test isolates the actual production fragment
  path and compares it with independent StandardMaterial3D reference panels;
  it rejects headless execution and empty/background reference samples.
- Six Standard views: three pixel-exact; flightline/windsock differ on one pixel
  each, lake on 921 of 2,073,600 pixels, all by at most one 8-bit channel level.
  The measured mountain patch and the pilot view are exact. Do not call the
  complete Standard set pixel-identical.
- Six High views: four pixel-exact; the lake and pilot mountain backgrounds
  change. The same middle-ridge patch's horizontal luminance gradient rises
  **0.07374 → 0.24856** in 8-bit units. This measures recovered local variation,
  not a general quality score. Standard remains 0.75042: full renderer parity
  is not established.
- **24 production World samples** cover day, twilight and night, lake/pilot views,
  and two camera/clock positions. [World report](world-cases/report.json) records
  the actual flowing state. These are settled samples, not continuous flight.
- Disabling ridge shadow reception in a disposable experiment changes only one
  pixel by one level. It is rejected; the remaining broader lighting difference
  is not hidden with mountain-specific brightness or haze tuning.

A single 10 s warmup + 10 s offscreen pilot-view timing pair reports GPU p95
**1.659 → 1.786 ms**, wall p95 **1.943 → 2.035 ms**. Both have **266 draw calls /
321,140 primitives**. This short pair does not establish a speedup, zero GPU
cost, causality for the timing delta, or flight-performance qualification.
See [all metrics and source identities](comparison.json).

The Windows trial export passes, and the actual packaged executable completes
a 1 s warmup + 5 s scripted render smoke: 300 frames, Forward+, 1280×720,
`complete=true`. [Raw packaged report](packaged-smoke.json). This route disables
flight physics and is not flight validation. The package retains the seven
Texture RID exit warning; no script/shader errors were reported. Binary/DLL and
source hashes are in [package identity](package.json).

Existing Forward+ exit warnings report seven Texture RIDs; existing driver
messages mention `OpVectorExtractDynamic`. The checked capture runs have no
shader/script errors. Initial harness failures are retained: a missing external
aircraft authoring directory in the first isolated archive, and a reference-test
revision that incorrectly assumed the legacy cubic equals exact sRGB near black
(plus a corrected GDScript type inference error).

## Reproduce and integrate

The shared worktree was receiving other teams' commits and had missing imported
resources. Comparisons therefore use a frozen archive of commit
`2bb2fc2fadc55cc8e41030608a22daf64ef5a2dc`, its aircraft authoring sources, and a
fresh **isolated** import cache. Only the ridge shader differs between successful
before/after runs. The shared asset files and import cache were not repaired or
modified. Native engine jobs for this campaign ran serially.

Use the existing `tools/graphics/capture.gd` with `--hour=15
--aircraft=p51d-mustang-120`, each renderer/profile, and a new output directory.
Run `tools/graphics/test_ridge_color.gd` natively on both renderers. To reproduce
the color mutation, restore `ridge-before.gdshader` **only in a disposable copy**.
`world_probe.gd` takes a new absolute output directory and that baseline shader
path. `compare.py <campaign directory>` reproduces pixel metrics and retains the
selected artifacts. Logs, including expected failures, live under `checks/`.

The local Windows trial is built from this frozen source plus the correction;
it is not a release or a claim to include later parallel commits. Package identity
and smoke results are recorded alongside this report. High remains experimental;
other GPUs, macOS/Linux, repeated pacing pairs and pilot acceptance stay open in
the [advanced plan](../../../../plans/advanced-graphics.md).
