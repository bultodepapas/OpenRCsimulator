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

Status: Native Godot 4.7.2 Compatibility validation tools.

Install the pinned offline analysis dependency with `python -m pip install -r
tools/shadows/requirements.txt`. Use the pinned Godot console executable and a
display; headless rendering cannot validate masks or GPU cost.

```powershell
python tools/shadows/vq04a_verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --baseline PATH_TO_BEFORE_APP --candidate app --out NEW_OUTPUT_DIRECTORY
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

The [VQ-04a-F2 windsock follow-up](../../docs/research/visual-quality-implementation/VQ-04a/windsock/README.md) shares the visible sleeve deformation and basket yaw with one 512² field map. Run `test_windsock_shadow.gd` and `test_field_projected_shadows.gd` headless for lifecycle/cache/budget checks. Native `windsock_capture.gd -- --out=<new directory>` saves seven wind/light cases, isolated masks, shadow-hidden appearance controls and a wide low-sun view. `windsock_probe.gd -- --out=<JSON path>` checks coverage against independent ray-plane intersections and records alternating dynamic/cached component timings. These native tools require a display and absolute script paths when run with `--path app`; timings are fixture evidence, not full-flight performance qualification. `check_windsock_pack.gd` accepts one exported PCK path as its sole user argument from an empty project and constructs the imported caster and shaders.
