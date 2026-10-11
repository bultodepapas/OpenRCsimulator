# L4c — directional cloud relief

**Status: implemented and visually verified, 2026-10-11.** Landscape step L4c;
render-only upgrade. Local timing budget passes observationally; isolated performance
acceptance and Gate L pilot review remain open.

## Scope and coordination

The initial worktree audit found active UI-21 menu changes, EL2a-P3 propulsion
research, and audio research. This task owns `render/cloud_relief.gdshaderinc`,
one narrow integration in `render/sky.gdshader`, and `tools/atmosphere/l4c_*`.
No UI, physics, model, world-composer, weather, or field-data files were edited.
Baseline/candidate app snapshots isolate measurements from concurrent work.
Shared files are checked against their frozen source before integration.
The follow-up audit found another developer's turf-detail and electric-propulsion
edits. Those files were preserved. The sky source still matched the frozen baseline
byte for byte at installation; only the sky shader and new include/UID were copied.
The existing Phase 6 producer received a two-line legacy-mode compatibility update
after its clean-file check. A fresh snapshot of the combined tree imported and
rendered the actual app successfully.
The final audit also found the parallel projected-shadow integration. A second fresh
combined snapshot imported and rendered successfully after those changes; its complete
[source hashes](merged-sources.json.gz) identify precisely what was smoke-tested.

## Acceptance defined before implementation

- Directional bright rims and shaded cloud interiors visible in production sky
  captures toward, across, and away from the sun; no change to cloud coverage,
  silhouette, drift, horizon fog, cirrus, or ground-shadow projection.
- Keep the radiance pass unchanged, so aircraft/ground illumination is preserved.
- No extra draws, textures, framebuffers, dependency, simulation state, or clock.
- Zero strength reproduces baseline pixels; repeated captures reproduce pixels.
- Clear sky and ground/aircraft pixels remain unchanged; unlit night does not gain
  light. Moonlit shading uses the existing cloud illumination, never an emission term.
- Native RTX 3090 at 1280×720, VSync off: incremental median GPU time ≤0.5 ms,
  incremental p95 GPU time ≤1 ms; report raw frame samples and wall time separately.
  This is a local graphics budget, not target-hardware or total simulation acceptance.
- Real renderer compilation, relevant atmosphere/world checks, whole-app regression
  suite, and identical real-app physics trace for frozen baseline/candidate.

All optical depth and shape constants are artistic estimates, not measured weather.

## Audit and research decision

Runtime: **Godot 4.7.2.stable.official.ed1daf0bf**, OpenGL 3.3 Compatibility,
NVIDIA RTX 3090, driver 610.88, Windows. `project.godot` selects Compatibility
and 4× MSAA. The native engine identifies the same patch version as the launcher.
The public reference is the versioned **4.7** manual; patch behavior was checked
in the **4.7.2-stable** engine source and native rendering.

| Candidate | Decision |
| --- | --- |
| Volumetric fog / compute-based clouds | Requires Forward+; conflicts with the renderer contract and broadens the change substantially |
| Raymarched sky with half-resolution subpasses | The generic sky manual shows this technique, but the project's Compatibility investigation found no working subpasses; avoid relying on them |
| SSAO | Available in current Compatibility, but targets near geometry; the pilot spends most flight time watching the sky |
| Temporal reconstruction / TAA | Poor fit for the current renderer and the small moving aircraft's readability requirements |
| Directional optical-depth cloud relief | Selected: large visible area, no assets or extra passes, bounded cost and exact zero-strength fallback |

The existing landscape already has anti-tiling ground, cloud shadows, cirrus,
tree-card crown shading, geometric near grass, and horizon haze. This step adds
directional depth to the existing fair-weather cloud layer rather than duplicating
those systems. Research/review delegated to a read-only Luna Max agent; implementation
and renderer validation stayed in one task.

## Implementation and iteration

Three samples of the unchanged periodic density field along the light direction
estimate optical depth. Exponential attenuation, an ambient floor, a bounded
density-difference shoulder, and weak forward scattering shade the visible cloud.
No density, alpha, drift, sun-disc, cirrus, or ground-shadow equations change.

The first render gave distant wisps excessively sharp shading. The final version
softens the shoulder, raises its ambient floor, and smoothly removes relief between
`EYEDIR.y=0.12` and `0.40`. At the horizon the old shading is exact. Light-path
length is bounded near a horizontal light; a zenith light has no arbitrary azimuth.
All math stays in the existing linear-light path before its Compatibility encoding.

`AT_CUBEMAP_PASS` excludes relief from the radiance pass. This deliberately keeps
the calibrated environment lighting and reflections: the background gains detail
that is absent in reflected clouds. `cloud_relief_strength=0` is the exact legacy
fallback; production defaults to 1. The old Phase 6 capture producer also zeros this
new strength in its legacy mode, retaining its reference meaning.

## Verified image and integration results

The final visual matrix contains 144 original 1280×720 PNGs: six camera directions,
two cloud times, baseline/candidate day, clear, sunrise, unlit night and aircraft-off
controls, plus repeated candidate and zero-strength captures. Daylight views gained
sunward shoulders and shaded interiors; the second iteration removed the harsh
distant wisps visible in the first. The actual flight camera also shows the change.

| Check | Observed result |
| --- | --- |
| Zero strength / repeat / clear sky | 12/12 exact pixel matches in each group |
| Ground-only frames | 2/2 exact pixel matches; draws and primitive counts unchanged in all 12 day views |
| Aircraft interior mask | 11/12 exact; sun view at 120 s differs by at most one 8-bit level, consistent with mixed MSAA coverage; strict all-aircraft pixel equality is not claimed |
| Visible day change | 94,729 pixels differ by >3 levels toward the sun at 0 s; 115,570 across it and 252,180 at zenith |
| Unlit snapshot | No positive channel delta in all 12 views |
| Actual app day / sunrise / moonlit night | All render successfully; moonlit clouds retain the existing illumination source |
| Actual dark-night / precise midnight | Maximum increase 1 / 0 levels respectively; precise midnight is pixel-identical |
| Flight state | All 721 initial/tick rows and metadata identical, except the creation timestamp; trimmed-flight check passes |
| Export | Windows PCK loads through the native engine; daylight PNG is pixel-identical to the unpacked candidate |
| Regression | Entire `app/test.sh` exits 0 in an isolated Linux clone, including 180 GDScript test files and the suite's other checks; zero script/shader errors |
| Combined worktree | Final native import and actual-app render pass with parallel menu, turf, electric-propulsion and projected-shadow work present |
| Existing Phase 6 legacy producer | 15/15 baseline/candidate PNGs pixel-identical after the compatibility update; [controls](legacy-summary.json), [original images and metadata](legacy-controls.zip) |

The regression clone contains baseline commit `b5febac` plus only the three runtime
files for L4c. It does not claim to validate unfinished changes from other tracks.
The frozen native baseline/candidate also differ only in those three files. Existing
aircraft inertia warnings are unchanged. The exported-pack check does not constitute
a standalone installer or all-platform delivery test.

## Frame-time observations

All twelve native runs completed: three alternating revision pairs at each resolution,
10 s warmup then 60 s of samples each. GPU times below are milliseconds per viewport
render. The 720p incremental budget was median ≤0.5 ms and p95 ≤1.0 ms; all three
pairs pass those observed bounds. This is **provisional performance evidence** because
the workstation was shared, with [another native capture observed](profile-concurrency.json).
The 1080p rows document behavior at a second resolution, not clean scaling attribution.

| Resolution / pair | Median before → after | p95 before → after | Median delta | p95 delta |
| --- | --- | --- | --- | --- |
| 1280×720 / 1 | 0.291 → 0.317 | 0.365 → 0.610 | +0.026 | +0.245 |
| 1280×720 / 2 | 0.293 → 0.327 | 0.571 → 0.542 | +0.034 | −0.029 |
| 1280×720 / 3 | 0.316 → 0.319 | 0.367 → 0.749 | +0.003 | +0.382 |
| 1920×1080 / 1 | 0.355 → 0.406 | 0.559 → 0.762 | +0.051 | +0.203 |
| 1920×1080 / 2 | 0.357 → 0.407 | 0.687 → 1.358 | +0.050 | +0.671 |
| 1920×1080 / 3 | 0.358 → 0.407 | 0.686 → 0.658 | +0.049 | −0.028 |

At 720p the candidate's viewport CPU median is 0.377–0.479 ms and wall median is
0.837–0.913 ms; candidate wall p95 is 1.714–1.852 ms. At 1080p candidate wall p95
ranges from 1.512 to 6.602 ms, illustrating the contention. Do not convert these
off-screen static-render intervals into claimed flight FPS. Full CPU/GPU/wall
p50/p95/p99 and every sample are retained; no outliers were removed.

## Sources

Accessed 2026-10-11. No external code, texture, or dependency was added to runtime.

- [Godot 4.7 sky shaders](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html): background versus cubemap execution; uniform-driven radiance refresh. Kept the existing quantized simulation clock and avoided `TIME`/`POSITION`.
- [Godot 4.7 renderer features](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html): renderer-specific feature availability. Existing repository notes about older SSAO support must not substitute for the current feature table.
- [Godot 4.7.2 GLES3 sky source](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/sky.glsl): compile-time cubemap pass and final sky color conversion.
- [Godot 4.7 RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu): viewport CPU/GPU timing, measurement enablement and GPU clock-state caveat.
- [NVIDIA GPU Gems, chapter 39: Volume Rendering Techniques](https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-39-volume-rendering-techniques): light absorption, density gradients, accumulated attenuation and the accuracy/cost of sampling. These concepts inform the artistic thin-layer approximation; this is not its texture-based volume renderer. The newer NVIDIA volumetric-scattering PDF appeared in search but could not be fetched, so it was not relied on as implementation evidence.
- Local foundation: [Compatibility sky investigation](../../landscape-investigations/01-sky-shaders.md), [L4b](../L4b/README.md), [L15d](../L15d/README.md), [rendering lessons](../../../learnings/models-and-rendering.md).

## Reproduction

Review the [before/after gallery](review.html), [visual metrics](visual-summary.json),
[integration results](integration-summary.json), [timing summary](profile-summary.json),
[regression record](verification.json) and [full suite log](full-suite.log.gz).
The [capture archive](captures-and-integration.zip) retains every original PNG,
capture report, integration trace and log; its `manifest.json` maps logical capture
paths to deduplicated image members and SHA-256 hashes. Separate compressed profile
reports retain every raw wall/CPU/GPU sample. [Artifact hashes](artifact-hashes.json)
cover the packaged evidence. The [combined-tree render](merged-smoke.png) and
[log](merged-smoke.log) are smoke evidence only, not the isolated before/after pair.

Use separate frozen baseline/candidate app folders. Evidence tools refuse an existing
output folder and fail on engine errors or missing artifacts. Python evidence dependencies
on this machine were Pillow **12.3.0**, NumPy **2.4.6**; runtime has no new dependency.

```powershell
python tools/atmosphere/l4c_verify.py --godot <godot-console.exe> --baseline <before-app> --app <after-app> --out <fresh-visual-folder>
python tools/atmosphere/l4c_verify.py --godot <godot-console.exe> --baseline <before-app> --app <after-app> --out <fresh-profile-folder> --profile
python tools/atmosphere/l4c_integration.py --godot <godot-console.exe> --baseline <before-app> --app <after-app> --out <fresh-integration-folder>
python tools/atmosphere/l4c_package.py --visual <visual-folder> --profile <profile-folder> --integration <integration-folder> --out <report-folder-containing-README.md>
```

Run profiling alone on the GPU. It uses three alternating before/after pairs at each
resolution, ten seconds of warmup and sixty seconds of samples per process. The
production field, Stik model and sky are present, but their poses and cloud time are
frozen to isolate shader cost: azimuth 225°, elevation 35°, FOV 50°, cloud time 0 s,
default coverage. This is the toward-sun fixture, not a worst-case cloud-coverage sweep.
Wall intervals and viewport CPU/GPU timers are separate;
viewport CPU time excludes scripts. These measurements do not establish complete
240 Hz flight performance, radiance-refresh spikes, or minimum-hardware acceptance.

A window-bound trial and an automatically drawn off-screen trial did not finish
reliably and were discarded. The final producer disables the automatic render loop
and calls `force_draw(false)` once per process frame into an always-updating off-screen
viewport on the same real OpenGL device. It does not wait for a window's post-draw
signal. The manually drawn sun-view control matched its visible-window capture pixel
for pixel. This is GPU rendering,
not Godot's headless dummy renderer. Other developers' jobs shared the CPU. A process
audit during the 1080p run also found a concurrent native VQ-04a capture on the GPU;
that developer's process was preserved. No complete GPU-activity history exists for
the 720p runs. The paired results satisfy the observed budget, but both wall times
and GPU differences are shared-machine observations, not isolated cost attribution
or a clean system benchmark. A quiet-machine rerun is needed for that stronger claim.

## Limits

The clouds remain an angular layer: no camera parallax, true 3D volume, volumetric
fog, or measured weather. Added relief performs three five-octave density evaluations
per eligible sky fragment (roughly 72 extra lattice-corner hashes when clustering is
enabled). Cost varies with visible sky and cloud coverage. Lower-end GPUs and other
vendors remain unmeasured. The existing Gate L
human attitude-recognition review remains open; image preservation is not pilot acceptance.
