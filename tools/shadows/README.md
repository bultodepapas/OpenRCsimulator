# Projected-shadow validation (VQ-04a / VQ-04a-F1)

DT-11a fallback mask generation hoists repeated pixel clamping while preserving
the two-pass box filter's exact sum order. Run `res://tests/test_shadow_blur.gd`
with the pinned engine, headless or native, for complete float32 parity, edge
weights and independent image/texture/material checks. [Mask/carrier construction
evidence](../../docs/research/visual-quality-implementation/VQ-01c/loading/shadow-blur/README.md)
records native timings; no regeneration or cache invalidation is needed.

DT-11a collection uses native packed-vector transforms and directly appends faces
when no height cutoff is configured. The original bounds scan and static-caster
height test remain. `res://tests/test_shadow_collection.gd` checks exact face order,
thresholds and source isolation; run it with the pinned engine, with or without
`--headless`. [Construction measurements and rejected bounds shortcut](../../docs/research/visual-quality-implementation/VQ-01c/loading/shadow-geometry/README.md)
are separate from visual acceptance below.

DT-11a cutoff collection also appends contiguous accepted triangle runs in native
code. `test_field_population_collection.gd` checks run boundaries, selection and
source isolation. `compare_field_collection.gd` accepts `--reference=<frozen field
collector>`, `--reference-projected=<frozen projected collector>` and `--out=<JSON>`;
candidate scripts default to the working runtime. Population rows include static
base work, so report the two kinds separately. [Measurements and reproduction](../../docs/research/visual-quality-implementation/VQ-01c/loading/shadow-geometry/triangle-runs-2026-10-21/README.md)
record the exact-output and visual checks.

Use the pinned official Godot 4.8-beta2 Compatibility engine for new native runs.
Dated validation and timing evidence retain their recorded engine scope.

Install the pinned offline analysis dependency with `python -m pip install -r
tools/shadows/requirements.txt`. Use the pinned Godot console executable and a
display; headless rendering cannot validate masks or GPU cost.

```powershell
python tools/shadows/vq04a_verify.py --godot .tools/Godot_v4.8-beta2_win64_console.exe --baseline PATH_TO_BEFORE_APP --candidate app --out NEW_OUTPUT_DIRECTORY
```

The baseline must precede VQ-04a, with the same unrelated source/assets as the
candidate. The tool copies both inputs into a new output directory, imports
resources, records source hashes, probes GPU projection against an independent
CPU ray-plane oracle, and captures four aircraft at five attitudes/heights plus
three scenery views. It also exercises the actual flight route and shadow-off
parity, profiles six alternating runs each for moving aircraft and static scenery,
and compares every sample and stable metadata byte in three-second traces for
all four aircraft. Trace creation timestamps are excluded. Exact input-file hash
differences are excluded only after confirming that the input differs solely in
CRLF/LF encoding; semantic input hashes must still match.

Aircraft mask repeats must be exact. Whole-scene repeats allow at most eight
pixels differing by one 8-bit channel step; every nonzero difference is reported.
This allowance concerns opaque model edge quantization, not shadow correctness.
No masks or excluded regions are applied to images. Compare full images manually
as well; automated image equality cannot establish visual quality.

Profiling uses `RenderingServer` CPU/GPU viewport timestamps, includes the moving
aircraft's offscreen pass, and retains every raw sample. Static field maps finish
before the measurement window. Windows runs wait for other Godot GPU processes;
they never stop another developer's process. A display that stops rendering when
occluded may cause a timeout; keep the capture window available. Results apply
only to the recorded hardware, resolution and scene, not minimum hardware.

`--resume` reuses frozen, hash-checked captures and completed profiling campaigns
after an interrupted run. An overlapping profile attempt is retained as discarded
evidence and retried; it never enters the accepted timing summary.

`--field-shadows=off` restores the old field contact/shadow path for technical
comparisons. The existing aircraft `--shadow=off` remains independent. Scenery
is on by default; use `--scenery=off` or `OPENRC_SCENERY=off` for an explicit
scenery-free comparison. See the [scenery tools](../scenery/README.md).

Evidence and limits: [VQ-04a](../../docs/research/visual-quality-implementation/VQ-04a/README.md).

## Aircraft mask LOD proxy

The ordinary stock Corsair flight can reuse imported LOD indices for its shadow
mask. Admission requires the exact asset, manifest, default `midnight` livery,
pinned engine hash and a non-headless Compatibility renderer. Workshop trials,
custom paint, scripted/capture/trace fixtures, Home previews and other aircraft
keep full geometry. Invalid or unsupported LOD records retain full mesh faces;
the original bounds and existing angular cache remain authoritative.

Use `--aircraft-shadow-proxy=full` after `--`, or
`OPENRC_AIRCRAFT_SHADOW_PROXY=full`, for the full-geometry comparison. CLI takes
precedence; `auto` restores the stock-source policy. Unknown values select full.
This switch does not change saved settings. Frame reports record the actual
representation, triangle counts and manifest in
`render_settings.projected_aircraft_geometry`; the native reducer treats these
as measurement identity.

Run the focused `res://tests/test_aircraft_shadow_proxy.gd` through the checked
runner for decoder, bounds, source ownership and session-context checks. For
native binding, image and component-timing evidence, use a display and a fresh
absolute output directory. Run one rendered process at a time:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta2_win64_console.exe').Path
$TrialScript = (Resolve-Path 'tools/shadows/aircraft_proxy_trial.gd').Path
python tools/godot/run_checked.py --label aircraft-shadow-proxy --timeout 240 --warnings-as-errors -- $GodotWindows --path app --audio-driver Dummy --rendering-method gl_compatibility --resolution 1920x1080 --script $TrialScript -- --out=C:/ABSOLUTE/NEW_DIRECTORY --cache-controls --profile-frames=240
python tools/shadows/analyze_aircraft_proxy.py C:/ABSOLUTE/NEW_DIRECTORY --out C:/ABSOLUTE/NEW_DIRECTORY/summary.json
```

The trial exercises seven production `Shadow.bind_model` admission/fallback
cases and eleven poses through the actual 256² MSAA 4× mask and 1080p receiver.
It also checks four initially disabled routes (master Off, Native, saved cue Off
and explicit local Off). These use one precomputed full shape to isolate setup
allocations, then require exact eager/deferred mask and receiver PNG parity on
activation. Renderer texture-memory deltas are estimates; setup timings exclude
geometry collection and are not full-flight benchmarks.
Gear/flaps are set before collection, matching the existing bind-time geometry
contract. `--cache-controls` adds three fresh full masks at 0.24° local-axis
perturbations; these are sampled context, not a universal error bound.
`--profile-frames=0..1200` collects four alternating pairs after 60 warmup frames
per batch. Each frame changes roll enough to redraw. `--lod-distance=<positive>`
changes the isolated candidate criterion; production admission still uses its
pinned criterion. This is not the full-flight 10-second/60-second qualification.

The analyzer verifies PNG hashes, measures mask-alpha and maximum RGB-channel
differences, and reports interpolated p50/p95/p99 component samples. GPU polls
can lag or repeat. Retain the raw report and captures for review; a component
triangle saving or timing difference does not establish a whole-flight gain.
[Dated source, visual and timing evidence](../../docs/research/visual-quality-implementation/VQ-04a/aircraft-proxy-20261109/README.md)
records the extra binding cost and current hardware limits.

## Paired aircraft collection comparison

`compare_aircraft_collection.gd` compares prior proxy/projected sources against
the current collector, including exact mesh arrays, bounds, counts and fallback
metadata. Export both prior files as `.gd` outside `app/` and check their hashes
against the intended baseline commit. The tool binds the baseline proxy to the
supplied baseline projected collector in memory; passing current files as the
baseline establishes only a null control. Create the output parent first:

```powershell
python tools/godot/run_checked.py --timeout 180 --require-text '0 failed' -- `
  .tools/Godot_v4.8-beta2_win64_console.exe --path app --audio-driver Dummy `
  --rendering-method gl_compatibility --resolution 1920x1080 `
  --script "$PWD/tools/shadows/compare_aircraft_collection.gd" -- `
  --baseline-proxy=res://../tmp/shadow-base/aircraft_shadow_proxy.gd `
  --baseline-projected=res://../tmp/shadow-base/projected_shadow.gd `
  --out=C:/captures/shadow-collection-new.json
```

The JSON path must be new. Five gear/flap fixtures each run five alternating
ABBA/BAAB groups after untimed setup/shape checks. Every timed shape is compared
outside timing, and selected source hashes are checked before/after. Run without
competing measurements. This measures warm-process collector CPU cost; it does
not measure first interaction, FPS, GPU pass time or peak memory. Add `--headless`
for software-only screening; that cannot establish native rendering performance.
[Packed-index qualification and rejected experiments](../../docs/research/visual-quality-implementation/VQ-04a/collection-decoder-20261109/README.md).

## Initially disabled aircraft cues

`Shadow.create(parent, cue_override)` and the optional fifth argument to
`Shadow.bind_model` accept the same `sun` / `vertical` / `off` override as
`Shadow.update`. Defaults follow saved settings; the global technique can veto
all local cues. Main resolves the initial mode before building the world and
passes it to creation and binding, including direct `--shadow=off` launches.

An initially disabled cue skips its fallback texture and defers the projector,
256² viewport, receiver and shader materials. Binding still captures geometry
immediately: some visual meshes mutate in place, and collecting later would
change the existing bind-time silhouette. A weak source reference guards the
pending shape; expired sources release it on the next policy process frame.
Visibility and tree-entry events replay the latest request for static owners.

The first visible, nonzero enabled update installs the captured shape. An
already-created projector remains cached while hidden for quick toggles. Empty
models and unbound legacy carriers create their canonical fallback texture only
when displayed. Freed bound sources cannot produce a generic ghost shadow.

Frame metadata reports `representation=deferred`, zero instantiated mask
triangles, and `pending_representation` / `pending_triangles` for the retained
geometry. It restores the selected representation when activated. This does
not mean the retained mesh buffers consume no memory. Geometry collection,
Home's precomputed cache and field-shadow resources remain separate costs.

Run `res://tests/test_shadow_deferred.gd` through the checked runner for snapshot,
startup-order, override and source-lifetime checks. The existing cue, projector,
blur, ownership, settings and Home-geometry suites cover affected consumers.
[Dated native allocation and activation evidence](../../docs/research/visual-quality-implementation/VQ-04a/deferred-startup-20261109/README.md)
records exact image parity and the first-enable setup cost.

The [VQ-04a-F2 windsock follow-up](../../docs/research/visual-quality-implementation/VQ-04a/windsock/README.md) shares the visible sleeve deformation and basket yaw with one 512² field map. Run `test_windsock_shadow.gd` and `test_field_projected_shadows.gd` headless for lifecycle/cache/budget checks. Native `windsock_capture.gd -- --out=<new directory>` saves seven wind/light cases, isolated masks, shadow-hidden appearance controls and a wide low-sun view. `windsock_probe.gd -- --out=<JSON path>` checks coverage against independent ray-plane intersections and records alternating dynamic/cached component timings. These native tools require a display and absolute script paths when run with `--path app`; timings are fixture evidence, not full-flight performance qualification. `check_windsock_pack.gd` accepts one exported PCK path as its sole user argument from an empty project and constructs the imported caster and shaders.
