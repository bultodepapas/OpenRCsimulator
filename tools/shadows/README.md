# Projected-shadow validation (VQ-04a / VQ-04a-F1)

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
