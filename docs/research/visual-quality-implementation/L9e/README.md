# L9e — filtered turf microstructure

**Status: implemented and engineering-verified, 2026-10-11. Human Gate L remains open.**
Step prefix L; scoped extension of the landscape ground-material work.

## Ownership and acceptance

Owns `app/render/turf_detail.gdshaderinc`, the turf asset/generator, the new
`tools/ground/turf_*` tools, and small integrations in the initially clean
`app/render/ground.gd` and `ground.gdshader`. Avoids active UI-21, propulsion,
audio, L4c cloud relief and VQ-04a aircraft shadows. Other sessions are not
addressable here; this published boundary and content hash checks coordinate
shared paths. Freeze application snapshots before measurements. Append plan
status without replacing concurrent edits. Luna Max delegates own only their
explicit tooling path or read-only review; the lead reviews and integrates.
The initially clean `app/test.sh` received only the generator `--check` entry;
the generator was verified on both Windows and Linux. Shared plan/index/lesson
edits are additive. No simulation, aircraft, UI, atmosphere or shadow source was
changed by this step.

Acceptance fixed before implementation:

- Visible fine turf structure in near-ground and low-pass production-field
  captures; preserve runway edges, mowing pattern and macro colour.
- Directional matte relief, no emission/gloss, no camera-dependent normal flip.
- Mipmapped stochastic sampling; continuous pixel-footprint fade and no distant
  shimmer/detail at 110 m. No geometry, collision, input or simulation changes.
- Identical repeated captures, zero-strength fallback identical to frozen old
  shader, distant-view parity, day/night checks and real-app trace parity.
- Zero additional draws/triangles; <=6 MiB uncompressed mipmapped data texture.
- Native RTX 3090, Compatibility, 1280x720, MSAA 4x, VSync off: added median GPU
  <=0.5 ms, p95 GPU <=1 ms, p95 wall interval <=2 ms in repeated matched runs.
  Local graphics budget only; minimum hardware and human Gate L remain open.

Blade sizes, slopes and contrast are artistic estimates, not measured turf.
This is surface shading, not displaced or collidable grass. No third-party art.

## Audit and choice

The pinned executable identifies itself as Godot 4.7.2.stable.official.ed1daf0bf;
the project selects OpenGL Compatibility and MSAA 4x. Existing rendering already
has atmosphere/haze, a cloud density field and ground shadows, stochastic macro
grass, filtered mowing stripes, geometric near grass, tree cards and distant
hills. Active L4c and VQ-04a work own cloud relief and aircraft shadows. UI-21,
electric propulsion and audio also have concurrent edits. None are replaced.
Graph discovery returned no ground GDScript/shader results, so direct reads were
used for those files after the graph attempts.

The remaining near-field ground was a flat, noise-coloured surface. L9e adds
directional blade-scale structure in takeoff, landing and ground views. Screen
space/compute effects and a renderer migration would expand scope and renderer
risk. Extra geometry would duplicate L11a; a roughness map would have no useful
effect in the current zero-specular custom Lambert lighting path. A single packed
surface-detail texture adds the missing scale while retaining that lighting path.

## Implementation

An original deterministic 1024-square bake stores two signed world-X/Z slope
channels and centered linear tone. The 2 m tile contains 18,000 tapered blades;
lengths 25–110 mm and widths 2–5 mm are artistic estimates. Two translated samples
blend using the existing smooth noise/hash functions. There are no UV rotations,
so slopes retain their world orientation. Mipmaps average the encoded slopes
before normalization. Explicit gradients are computed before divergent branches;
the largest projected footprint fades microstructure over 15–80 mm/pixel.
Distance fades from 60 to 110 m. Both fades are continuous and camera-relative.

The ground shader converts world slopes into view space, projects against a
normalized base normal, and changes the normal only where detail has nonzero
weight. Existing albedo composition, surfaces, Lambert direct lighting, cloud
transmission, haze and the lighting update interface stay in place. The shader
default is zero; the production ground builder binds the texture and enables it.
This preserves bare Atmosphere material fixtures and duplicate surface fallbacks.

One texture occupies **5,592,404 bytes (5.33 MiB)** including its complete RGBA8
mip chain; PNG source is 2,287,341 bytes. These are format-size calculations, not
driver VRAM-allocation measurements. The import explicitly disables normal-map
compression: auto-detection could discard B, which here carries tone. Runtime
materials share the imported resource. Source provenance is beside the texture.

## Verified results

[Before/after gallery](comparison.html) · [machine-readable acceptance](evidence/summary.json)
· [source fingerprints](evidence/source-fingerprints.json)

Native visual and performance evidence: Windows, RTX 3090, NVIDIA 610.88,
Godot 4.7.2, Compatibility, 1280x720, MSAA 4x, VSync disabled. Five production
field poses cover the pilot's feet, close detail, runway threshold, low pass and
aerial view. Each has off/on/repeat captures, a separate frozen pre-change project,
and a midnight case. Both the source material and packaged resource were exercised.

| Acceptance | Result |
| --- | --- |
| Frozen old shader vs new strength zero | All five images pixel-identical |
| New effect repeats | All five images pixel-identical |
| Far field and unlit midnight | Aerial off/on identical; all five midnight off/on identical |
| Macro brightness | Maximum absolute full-frame mean RGB shift <0.043/255; near detail remains visible |
| Draws and primitives | Unchanged in every paired view |
| Grazing-angle filtering | Linear-RGB error vs 4x reference reduced **72.69%**; three 20 mm-shifted crops |
| Real flight, four aircraft | **721 samples each** identical before/after, excluding only creation UTC; [traces](evidence/traces/summary.json) |
| Aircraft colour preservation | **15,045** interior red-paint pixels unchanged in the real low-flight A/B; [integration](evidence/integration-summary.json) |
| Regression | Complete isolated `app/test.sh` exited 0; [log](evidence/full-suite-nativefs.log). Final shader compiled/rendered natively; generator check separately passed on Windows/Linux and is now wired into the suite |
| Pack | Export succeeded; empty-root runtime produced **15 PNGs identical** to source; [package evidence](evidence/package/summary.json) |
| Shared-worktree integration | Fresh snapshot import and native low-flight/field captures passed; [integrated flight](evidence/integration/integrated-flight-low.png) includes other teams' cloud/shadow work |

The resource pack grew by **2,586,608 bytes (2.47 MiB)**. Pack runtime comparison
used Linux Compatibility llvmpipe with WSLg, loading the Windows resource pack
from an empty directory; this verifies packaged resources, not a Windows installer.
The filter-reference experiment also used llvmpipe, separately from GPU profiling.
Its mutation disables mip/gradient sampling and footprint fade only in a disposable
project. Production RMSE was 1.66 versus 6.09 linear-RGB levels/255 for the raw
mutation. This is a bounded sampling regression, not proof of no shimmer at every
resolution or camera speed.

### Performance budget

Each native session alternates off/on/off/on, warming for >=2 s and 60 frames,
then recording >=3 s and 180 frames per state. Samples pool by state **within**
each session; percentiles are not averaged. Raw wall/CPU/GPU samples are retained
in `evidence/profile1/` through `profile3/`.

| Session | Median GPU off → on (ms) | p95 GPU off → on (ms) | Added p95 wall interval (ms) |
| --- | --- | --- | --- |
| 1 | 0.395 → 0.408 | 0.728 → 0.755 | +0.187 |
| 2 | 0.397 → 0.407 | 0.659 → 0.717 | +0.346 |
| 3 | 0.398 → 0.407 | 0.771 → 0.714 | −0.110 |

All sessions meet the predeclared +0.5 ms median GPU / +1 ms p95 GPU / +2 ms p95
wall budgets. Negative deltas reflect timing noise, not an optimization claim.
Early measurements overlapped other graphics tasks and were superseded. Other
Godot renderers were absent at process-inventory checks during the final serial
runs; this is still a shared desktop, not a controlled minimum-hardware benchmark.
Headless CPU regression work continued separately. These are field-fixture costs,
not whole-simulator frame-time or input-latency acceptance.

The harness now disables the automatic render loop and explicitly draws one
offscreen frame per sample. An earlier automatic-draw run stalled under desktop
occlusion; adding forced draws without disabling the automatic loop would risk
measuring two draws per frame. No runtime rendering-loop setting was changed.

### Evidence integrity and reproduction

All engine calls used fresh output directories, successful exit codes and log
checks. The reducer verifies image hashes, repeat/fallback parity, engine patch,
effective ON/OFF strengths, actual GPU samples, counters and budgets. Negative
controls rejected a current shader posing as the legacy baseline, an all-OFF
profile and a wrong engine patch; [record](evidence/negative-controls.json).

PNG bytes are archived unchanged and deduplicated by SHA-256 in `evidence/frames/`.
Manifests point to those frames; original producer manifests are retained as gzip
files beside them. Verify the archive with:

```sh
python -m pip install -r tools/ground/turf_requirements.txt
python tools/ground/turf_generate.py --check
python tools/ground/turf_verify.py docs/research/visual-quality-implementation/L9e/evidence
```

Fresh capture/profile commands are in [the ground tooling guide](../../../../tools/ground/README.md).
For the independent filter control, provide an imported frozen candidate and a
display (WSLg used here; Xvfb also works):

```sh
LIBGL_ALWAYS_SOFTWARE=1 python3 tools/ground/turf_filter_probe.py \
  --godot /path/to/Godot-4.7.2 --app /path/to/imported/candidate --out /tmp/l9e-filter
```

Windows worktree CRLFs were normalized only in the isolated Linux regression
checkout so exact generated-JSON checks matched their canonical LF output. No
shared working-tree line endings or generated field data were rewritten.

## Primary research sources

Checked 2026-10-11. Versioned manual is 4.7; patch-specific import behavior was
also checked against the 4.7.2 engine source and executed in that binary.

- [Renderer matrix](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html):
  Compatibility constraints; do not assume a Forward+ screen-space normal buffer.
- [Spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html):
  fragment normals are in view space; `VIEW_MATRIX` converts world to view.
- [Shader functions](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shader_functions.html):
  explicit-gradient texture sampling and fragment derivatives.
- [Shading language](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html):
  packed slope/tone data has no `source_color` conversion.
- [Texture importer](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/import/resource_importer_texture.cpp):
  `compress/normal_map=2` means disabled; preserve packed channels and mipmaps.
- [RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html):
  enable viewport timing before reading CPU/GPU milliseconds. Wall intervals are
  separately observed; they are not GPU measurements.

## Limits

No displacement, silhouette change, collision, self-shadowing, physical leaf BRDF,
wetness, runtime generator or new renderer. Relief slopes are artistically scaled,
not derivatives of a measured height field in metres. Fixed camera evidence and
one RTX 3090 do not establish minimum-hardware performance or pilot preference.
The mostly sky-facing normal flight view intentionally changes little. Gate L
remains the owner's flight/readability decision.
