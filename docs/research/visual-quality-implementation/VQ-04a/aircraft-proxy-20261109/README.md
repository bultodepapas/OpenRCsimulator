# VQ-04a — stock Corsair shadow proxy, 2026-11-09

The triangle audit's projected-shadow experiment now reuses existing imported
LOD indices for one verified stock Corsair. The mask contains **178,455 rather
than 321,191 triangles: 142,736 fewer (44.44%)** across 39 selected surfaces.
Visible aircraft geometry, materials, physical state and the projector's bounds,
resolution, shaders and angular cache retain their existing behavior.

This is a source-scoped rendering change, with local visual and component
evidence. It does not establish a whole-flight FPS gain or hardware qualification.

## Admission and fallback

Ordinary flights explicitly supply a stock-session context and the verified
model-manifest hash. Admission also requires the exact Corsair asset, default
`midnight` livery, no custom-paint metadata, Godot engine hash
`cafc17a192acf67903910a68aeb3c076c0907a4b` and a non-headless
`gl_compatibility` renderer. Other callers, Home's precomputed geometry,
Workshop trials including unit-scale customizations, scripted/capture/trace
fixtures and other aircraft retain full collection. Current exports are desktop
builds; this policy is not a GPU capacity classifier.

Malformed/unsupported LOD data retains the original mesh faces. The full
collector supplies the exact framing bounds; nonfinite or outlying proxy
vertices reject the candidate. The maximum imported LOD selection distance is
0.0005, an importer criterion rather than a certified surface-error bound.
The decoder depends on the pinned engine's serialized `_surfaces` representation;
a different engine fails admission until explicitly revalidated.

The [tool guide](../../../../../tools/shadows/README.md#aircraft-mask-lod-proxy)
owns reproduction commands and the `--aircraft-shadow-proxy=full` / environment
override. Frame reports expose the actual geometry selection and manifest;
native campaign reduction treats these fields as measurement identity.

## Native evidence

[Raw report](report.json) retains all 1,920 timing samples, source hashes, image
hashes, engine/driver/GPU identity, case configuration and binding results.
[Summary](summary.json) retains image metrics and per-batch p50/p95/p99.
The checked run completed with zero engine errors or warnings on an RTX 3090,
Windows, NVIDIA OpenGL 617.42, Godot 4.8-beta2, Compatibility, native 1920×1080,
MSAA 4× and VSync disabled. No competing Godot process was present at launch.
No complete-system background-load isolation is claimed.

Seven production `Shadow.bind_model()` checks passed: admitted stock, explicit
full, missing context, Workshop, wrong manifest, custom paint and precomputed
Home shape. Full cases retained 321,191 triangles; the admitted case used 178,455.

Eleven matched cases cover landing/takeoff with flaps, low sun, ±60° bank,
±90° knife edge, inverted, gear up/transit and the horizon-direction clamp.
Each uses the production 256² MSAA 4× mask and a 1920×1080 receiver-only view.
Gear/flaps are set before binding, preserving the existing snapshot semantics;
the experiment does not add live articulation to the shadow.

Full/proxy mask differences affect 1–11 of 65,536 alpha samples, with an L1 sum
of 64–701 8-bit alpha steps. The final receiver changes 64–2,452 of 2,073,600
pixels; maximum channel differences are 6–25 steps at rare edges. Landing and
low-sun bank pairs were visually inspected with no observed clipping or lost
major silhouette feature. Exact pixel parity is not claimed.

For each case, three additional fresh full masks perturb one local axis by
0.24°, within the existing 0.25° reuse threshold. Proxy mask-alpha and receiver
maximum-RGB-channel L1 sums are below the largest sampled control in all eleven
cases. These controls provide scale for observed differences; they are not a
global error bound, and proxy error can add to existing cache error.

Four alternating full/proxy pairs use 60 warmup and 240 measured frames each.
Every batch confirms 300 redraws and 300 root draws; raw mask primitive counters
match the collected counts throughout. Roll changes by 1° each frame.

| Pair | Full wall p50, ms | Proxy wall p50, ms | Full mask GPU p50, ms | Proxy mask GPU p50, ms |
| --- | ---: | ---: | ---: | ---: |
| 0 | 0.7020 | 0.6665 | 0.2650 | 0.1690 |
| 1 | 0.6755 | 0.6525 | 0.1880 | 0.1610 |
| 2 | 0.7000 | 0.7270 | 0.1920 | 0.1935 |
| 3 | 0.7200 | 0.7165 | 0.1905 | 0.1810 |

The third pair regresses slightly. GPU timestamp polls can lag or repeat;
wall intervals include frame dispatch and receiver rendering. The short isolated
fixture is not the owning full-flight 10-second warmup / 60-second measurement.
Only the geometry reduction is a firm performance result here.

Collection median is **19.956 ms full versus 166.197 ms proxy**, adding 146.241 ms
per bind in this final run. An earlier same-host trial added about 98 ms. The
stock Corsair binds once per newly constructed flight; this is loading cost,
not per-frame work. No new persistent geometry cache was introduced.

## Software checks and remaining evidence

[Verification receipt](verification.json) identifies the tested sources and
checked-run receipts. Focused GDScript suites passed 359 checks: proxy/context
80, collection 77, projector 47, ownership 49, population collection 57 and cue
controls 49. Main and the native tool parsed; the five native-summary identity
tests passed. Engine error/warning counts were zero for the checked Godot runs.

A separate native 1080p debug-bridge smoke followed Home → stock Corsair → runway.
The actual flight admitted the stock context and reported 178,551 proxy / 321,287
source triangles: the assembled evening flight retains 96 additional full faces
relative to the isolated fixture. The same 142,736-triangle saving applies.
The live log contained no error/warning records and shutdown reported no crash
or leaked objects. Background/focus hitches were observed; this route check is
not timing acceptance.

The retained images remain in ignored
`tmp/shadow-proxy-20261109/trial-final/`; no PNGs are committed. The analyzer
verifies their recorded hashes before reduction. The raw report is retained
here so distributions remain independently reducible after temporary captures
are removed.

Complete representative flights, no-change variation, lower-powered GPUs,
other drivers/renderers, macOS and human pilot/readability acceptance remain
unmeasured. No physics or collision change was made, and golden flights were
not re-recorded.
