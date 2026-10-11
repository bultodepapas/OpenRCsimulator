# VQ-04a — mesh-derived soft aircraft and field shadows

**Status: delivered and locally validated, 2026-10-11.** Prefix VQ; scoped delivery of
the visual-quality plan's VQ-04a.

## Ownership and coordination

Initial status showed UI-21 menu files, propulsion/audio research, and L4c
cloud-relief tooling in progress. This delivery avoids all of those paths.
It owns new `app/render/projected_shadow*`, `field_projected_shadows.gd`, changes
in `app/render/shadow.gd`, `tools/shadows/`, and the two new projected-shadow tests.
Integration is limited to binding calls in the initially clean `app/main.gd` and
`app/ui/home_scene.gd`, attach/lighting hooks in `field.gd`, and a precise camera
scope assertions in `test_field_integration.gd`, `test_ui_flight_capture.gd` and
the existing `capture_ui.gd` evidence tool. All seven existing files were
byte-checked against frozen originals immediately before integration; no menu layout,
world lighting, aircraft geometry, shader clock or simulation edits are needed.
Other sessions cannot be messaged from this thread; this published boundary and
fresh content checks are the available coordination mechanism. Baseline and
candidate snapshots isolate measurements from concurrent work.

Two Luna agents with max reasoning received bounded research, test and review
assignments. The lead reviewed every contribution, corrected GPU-probe types and
the viewport Y convention, strengthened fallback/datum checks, and retained all
production architecture and integration edits. Later L9e turf and propulsion
changes were left intact. GPU profiling waits for other sessions and rejects
overlapping runs; no other developer's process was stopped.

## Acceptance fixed before implementation

- All four catalog aircraft cast their own visible-mesh silhouette, with model
  origin/CG alignment, including bank, inverted and knife-edge poses.
- Softness grows continuously with height. No opaque rectangle, overlapping
  triangle darkening, mirrored footprint or clipped blur border.
- Existing off/sun/vertical pilot-aid choices, night attenuation and legacy
  fallback remain usable. No aircraft material or illumination changes.
- One merged offscreen silhouette draw, one receiver draw, a bounded 256² target;
  no new assets, dependencies, simulation state or clock.
- At 1280×720, MSAA 4×, VSync off, native RTX 3090: added median GPU time ≤0.5 ms,
  added p95 GPU time ≤1.0 ms; added p95 wall interval ≤2 ms in matched repeated
  runs. Report viewport timings including the offscreen pass separately from wall
  intervals. These are local budgets, not minimum-hardware acceptance.
- Fixed before/after production-field captures, repeatability, real renderer
  shader compilation, projection tests, app regression checks and identical
  frozen-source flight traces. Human pilot acceptance remains separate.

Constants controlling artistic softness and opacity are estimates, not measured
optics. This remains a flat-ground projected shadow, not self-shadowing or terrain
occlusion. The silhouette uses the model's visible neutral geometry; rapidly
rotating propellers and small live control deflections require explicit review.

## Field extension acceptance (VQ-04a-F1)

The requested fence and pilot shadows extend the same technique. Fence slats,
pilot-station rails, windsock and both pilot figures must retain recognizable
silhouettes without the old rectangular shadow underneath. Nearby cars, buildings
and ornamental trees use their existing merged scenery cell meshes. Source and
ancestor visibility must hide/restore the receiver. Explicit lighting snapshots
and flowing daylight must update direction without writing the simulation clock.

Static targets are 256, 512 or 1024² with no MSAA, capped at 16 maps and 8,388,608
pixels (64 MiB nominal RGBA8 plus 32-bit depth, excluding driver overhead). Default
cues use 3 maps / 1,179,648 pixels; scenery-on uses 10 / 4,784,128 pixels (36.5 MiB
nominal). Unchanged lighting schedules no redraw. Near-field selection is within
100 m of the pilot by cell bounds center. Rejected/far cells retain legacy shadows;
an incomplete cue set retains the entire legacy cue set. Apply the same GPU/wall
increment budget to the wide scenery view after its maps are cached.

## Implementation and visual review

[Native before/after gallery](gallery.html) · [Official research](research.md) ·
[Reproduction tools](../../../../tools/shadows/README.md).

Visible neutral triangles are merged into one opaque silhouette surface. An
isolated SubViewport renders alpha coverage; a symmetric 13-tap receiver softens
it in world units. Aircraft use their actual rendered global transform, including
the model datum. Root translation moves only the receiver; changed attitude or
light direction requests one fresh mask. Binding occurs before optional night
lights are added. The old public carrier transform stays stable for existing aids
and tests; empty models recover the original generic mask.

The native oracle identified Compatibility's render-target Y convention; a
deliberately mirrored disposable shader was rejected. A custom culling AABB keeps
world-baked scenery cells visible in the mask camera. Alpha coverage avoids
depending on Compatibility color encoding and opaque triangles avoid darker
self-overlap. Native pairs show distinct aircraft geometry, preserved knife-edge
volume, fence slats, human silhouettes and shaped tree/car shadows without the
old broad rectangles. The retained PNGs are unedited engine outputs.

## Verified results

Pinned Godot **4.7.2 official ed1daf0bf**, Compatibility/OpenGL 3.3, NVIDIA
**RTX 3090**, driver **610.88**, Windows; 1280×720, MSAA 4×, VSync disabled.
Each timing campaign has three before and three after runs in reversed pairs,
two-second warmup and five-second sampling. Accepted runs contain 2,555–3,316
samples each. Other Godot GPU work is checked before and after each run;
overlapping attempts are discarded. This shared desktop is not a controlled lab.

| Measured cost (median of three runs) | Before | After | Increment | Budget |
| --- | ---: | ---: | ---: | ---: |
| Moving P-51, GPU p50 including mask | 0.407 ms | 0.771 ms | **+0.364 ms** | ≤+0.5 ms |
| Moving P-51, GPU p95 including mask | 0.998 ms | 1.504 ms | **+0.506 ms** | ≤+1 ms |
| Moving P-51, wall p95 | 3.104 ms | 2.512 ms | −0.592 ms | ≤+2 ms |
| Scenery-wide, GPU p50, cached masks | 0.541 ms | 0.553 ms | **+0.012 ms** | ≤+0.5 ms |
| Scenery-wide, GPU p95, cached masks | 1.422 ms | 1.260 ms | −0.162 ms | ≤+1 ms |
| Scenery-wide, wall p95 | 2.532 ms | 2.605 ms | **+0.073 ms** | ≤+2 ms |

All defined budgets pass. Negative deltas are run-to-run variance, not a claimed
optimization. The moving aircraft's mask alone measures 0.356 ms p50 / 0.728 ms
p95. One-time aircraft collection in the capture run took approximately 8–43 ms
depending on model (5,892–46,293 triangles); these are startup diagnostics, not a
loading-time acceptance claim. Field loading cost and moving-daylight cost are
not represented by the cached steady-state table.

- **Projection:** native independent CPU/GPU oracle, zero sampled mismatches,
  opaque overlap, clear borders, correct +Z orientation, zero datum error, and
  current-frame pose/light changes. Deliberately mirrored shader rejected.
- **Images:** four aircraft × five poses/heights, plus three field views. All 20
  repeated silhouette masks and all three repeated field captures are exact.
  Three whole-scene aircraft images differ at 2, 2 and 7 pixels respectively,
  by one 8-bit channel step; these MSAA edge differences are recorded, not masked.
  The actual main scene's aircraft-off plus legacy-field route is pixel-identical
  to the original. Final low-sun/fallback fixes preserve every field pixel and
  every P-51 mask; remaining whole-scene variance has the same small edge bound.
- **Simulation:** each aircraft has 721 samples over three seconds. Every CSV
  sample, column and stable metadata byte matches its frozen baseline. Only
  creation time and the exact-input hash are excluded; the latter differs solely
  because the validation copy normalized JSON CRLF to LF, verified before
  comparison. Semantic input hashes match. Raw traces and canonical hashes are
  retained.
- **Focused checks:** 34 aircraft-shadow and 53 field-shadow assertions pass;
  22 pilot-aid and 84 crash-pose assertions pass. Visibility, rebind/freed-source,
  transformed datum, all four aircraft, low sun, flowing light without clock
  writes, empty-field fallback and hard target-budget rejection are covered.
- **Integration:** current workspace imports successfully; native Home and real
  Fly capture preserve exactly one gameplay camera and environment, despite
  isolated mask cameras. Native integrated field, 23:00 and 06:10 captures compile
  and render successfully alongside the other developers' current UI/sky/turf
  work. [Night](images/integrated-2300.png), [dawn](images/integrated-0610.png).
- **App regression coverage:** all `app/test.sh` stages completed on a fresh Linux
  clone with the isolated candidate overlay: generation/float64 guards, every
  script parse, unit/UI tests, model contracts, goldens, trace/trim checks,
  atmosphere/replay checks, frame-rate independence at 30/60/144 fps, and E5a/E5b
  ground-contact verification. Execution was resumed at the UI capture test after
  correcting its gameplay-camera count; the corrected test and every remaining
  original command passed (tail exit 0). The field integration assertion had the
  same correction, plus empty fields now allocate no manager. The capture tool's
  final parse and native Home/Fly runs also pass. The logs retain the intermediate
  failures rather than presenting this as one uninterrupted successful run.

Machine-readable [summary](evidence/summary.json),
[frozen source hashes](evidence/source-hashes.json),
[GPU oracle](evidence/gpu-probe.log),
[mirrored-shader rejection](evidence/gpu-flip-mutation.log), and
[final-runtime image parity](evidence/final-runtime-parity.json) accompany the
gallery. `evidence/profile-*.json.gz` contains every accepted raw timing sample;
`evidence/*-<aircraft>.csv.gz` retains both trace files. The post-integration
source inventory records the shared workspace after capture; frozen comparison
hashes are the authoritative before/after measurement inputs.
The isolated [implementation patch](evidence/implementation.patch) records only
this delivery; later audio edits in shared `main.gd` were preserved and the final
shared script was parsed successfully. Full regression logs are
`evidence/full-suite-final.log.gz` and `evidence/full-suite-tail.log.gz`; the
[validation record](evidence/validation.json) describes coverage and exit status.

Native shutdown diagnostics are not completely clean across the project. Two
early headless trace attempts returned nonzero after writing complete files with
no engine error in their logs; a later strict run completed all eight processes
with exit 0 and matching trace samples. Sequential verbose native baseline and
candidate captures each reported one existing `AudioStreamGeneratorPlayback`
reference and the same orphan `Master` name; no added shadow-related object was
reported in that pair. A current-workspace audio run reported a larger count.
This delivery does not claim to resolve the parallel audio track's shutdown
diagnostics or establish a long-duration memory benchmark.

## Limits

- Flat ground only: no terrain receiving, aircraft self-shadowing, shadow on roofs,
  or physical penumbra simulation. Independent receiver batches can overlap.
- Geometry is captured at binding: live control deflections, rotating propellers,
  windsock flutter and tree motion are not reskinned into the mask. Models and
  scenery keep their original animation behavior.
- Low-angle directions share the existing 12-degree pilot-aid floor; softness and
  opacity are artistic estimates. Finite maps can lose small details at low sun.
- Explicit time-of-day snapshot attenuation is preserved. The older flowing FW
  aircraft aid still uses its existing constant strength while field shadows fade
  with direct-light energy; changing that aid policy is outside this delivery.
- Optional scenery remains opt-in. Only nearby existing static mesh cells are
  upgraded; distant scenery retains its existing shadows.
- GPU results concern this RTX 3090 and Compatibility/OpenGL build. Minimum
  hardware, macOS and other rendering backends are not certified. Static-field
  profiles exclude initial map creation and continuously moving daylight.
- Visual engineering review is complete; human RC pilot/readability acceptance
  remains a separate owner playtest.
