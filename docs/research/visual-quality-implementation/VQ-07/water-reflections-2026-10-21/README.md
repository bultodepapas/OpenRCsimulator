# VQ-07: readable lake reflections in High

2026-10-21. Adopted only in the experimental High trial. Godot 4.7.2-stable,
Windows, Vulkan Forward+, RTX 3090, 1920×1080, 4× MSAA.

The lake lost almost all recognizable tree silhouettes in High. A bounded water
material adjustment restores softened reflections using the existing cubemap.
Compare [before](high-baseline/lake.png) and [after](high-candidate/lake.png).

## Attribution and change

Changing capture masks, increasing probe intensity or forcing a later refresh
did not recover the silhouettes. Setting water roughness to zero did, including
with the original transparent water shader. The probe was functioning.

The pinned engine uses different probe roughness sampling: [Compatibility](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/scene.glsl#L1866-L1944)
selects mip level from roughness; [Forward+](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl#L1191-L1237)
uses its square root. The [Forward+ caller](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl#L1528-L1542)
can also add normal-derivative variance through the roughness limiter. These
differences support the observed stronger blur; this is not an exact cross-renderer
BRDF equivalence or proof of an upstream engine bug.

After screening 0, 0.06, 0.10, 0.14 and 0.18 against the original 0.22, the High
fallback is **0.06**. It keeps softened silhouettes rather than the near-mirror
zero-roughness result. Standard remains 0.22. Explicit material configuration and
lighting overrides retain their existing precedence. No shader, geometry, wave
equation, probe allocation, capture mask or refresh cadence changes.

Lower roughness also narrows the direct solar highlight. The retained
[before](solar-highlight/before-030.png) and [after](solar-highlight/after-030.png)
show that tradeoff. Both still contain a saturated solar core. This is a visual
finish choice, not a measured physical-water calibration.

## Verification and limits

- Profile contract: **58 headless / 69 native Forward+ checks pass**. Covers the
  actual renderer gate, Standard fallback, lighting refresh and explicit overrides.
- Lake world: **27 checks pass**, including mesh/cache parity and physical surface
  alignment. An earlier invocation omitted the executable and failed to launch;
  its receipt is retained beside the corrected run.
- Local Windows export passes. The actual package completes a 1 s warmup + 5 s
  scripted render smoke (298 frames, Forward+, 1280×720); this disables flight
  physics and is not a flight-performance run. It retains the seven Texture RID
  and four ObjectDB exit warnings. [Raw report](packaged-smoke.json).
- Six matched Standard views: three pixel-exact; the others differ by at most one
  8-bit channel level on 4, 8 and 562 pixels out of 2,073,600. No exact-image claim
  for those three. [All comparison values and hashes](comparison.json).
- Six High views: four pixel-exact, including the P-51 close view; lake and the
  distant lake strip in the pilot view change. The scene uses the same builders.
- Five matched wave/camera samples over one second, before/after, in daylight
  and solar alignment. Production World comparisons additionally use September
  26 at 19:30 and 20:30 with 20× time, including realtime sky filtering. Retained
  keyframes show the reflection cue at twilight; the later scene is dark and does
  not establish night reflection readability. These are settled samples, not a
  continuous-motion recording or pilot flight acceptance.

The first 20:30 attempt used the static snapshot builder and produced black
images. It is rejected as low-light evidence (`dusk-motion/report.json`); the
production World runs replace it. Their `actual_world_state`, date, time scale
and sky process mode are authoritative; the inherited snapshot `lighting` block
is not the World lighting state.

Native logs contain the existing maple-wind warning and seven Texture RID exit
warnings, plus driver messages about `OpVectorExtractDynamic`. No new shader or
script errors were reported. This change does not resolve those warnings.

No FPS, latency or memory gain is claimed. The change adds no render pass or
resource; its return is a visible near-lake cue with a small material-only patch.
Full pilot motion, repeated performance pairs and other GPUs/platforms remain
open under the [advanced plan](../../../../plans/advanced-graphics.md).

## Reproduction and retained evidence

Run the existing `tools/graphics/capture.gd` with `--aircraft=p51d-mustang-120
--hour=15`, using a new output directory and the chosen native renderer/profile.
The checked commands and original logs are under `checks/`. `identity.json`
records source hashes; `manifest.json` covers retained artifacts. Reports retain
their original scratch paths. Selected full-resolution PNGs are retained here;
other images can be regenerated with the recorded probes.

Local build: `D:/OpenRCsimulator-scratch/reflection-20261021/release/OpenRC Simulator.exe`.
The package is labeled `export-manual`; its executable and companion native
library hashes are in `identity.json`. Use Home → Settings → Graphics → Try High.

`motion_probe.gd` reuses the capture scene and supplies paired roughness values,
wave clocks and camera translations. `glint_probe.gd` aligns the camera with the
solar reflection. `world_motion_probe.gd` replaces the scene setup with production
World for low-light exposure and flowing time. These dated probes are evidence,
not new application options. The mask/material/refresh probes record rejected
diagnostic alternatives. No performance samples were collected with image readback.
