# DT-11a — hoist horizon ring invariants

2026-10-19. Complete native horizon mesh construction fell from **45.507 to
39.899 ms (12.3%)**, using the median of five process medians. This is a component
construction improvement, not a measured Home/Fly, FPS or GPU-time improvement.

`Horizon.mesh()` now resolves each ring's radius, outer-boundary flag, height row
and vertex offset once per ring instead of repeating those lookups across its
1,440 vertices. There are 30 rings and 43,200 vertex iterations. The existing
profile validator guarantees nonempty height rows before this code runs.
Arithmetic precision/order, validation, triangle order and normal accumulation
are unchanged. Each call still creates an independent mesh; no cache is added.

## Comparison

Baseline: `8abefc50f0281526bdd13604f84694fee1686f27`, `app/render/horizon.gd`.
[Runtime patch](runtime.patch), [source identities](source-before.json) and
[artifact manifest](manifest.json) retain the comparison. The final runtime text
matches the measured candidate. Profile, project and engine hashes matched before
and after the campaign and regressions. A concurrent edit to the debugging-tools
research document was preserved and was outside this workload.

Godot 4.7.2-stable (`ed1daf0bf`), native Windows Compatibility, RTX 3090 / OpenGL
NVIDIA 617.42, Ryzen 9 5900X. Measurements ran serially on a shared workstation;
foreground/background activity and OS cache temperature were not controlled.

The unchanged [existing probe](../probe.gd.gz) alternates reference/candidate order
within each process; the first order also reverses between processes. Each process
performs eight pairs. The first pair is excluded from warm timing medians but
included in parity checks. Timing includes profile loading/validation and mesh
construction/submission; GPU readback and comparison are outside that interval.
It does not measure GPU completion. All five processes passed strict engine-error,
warning and completion-marker checks.

| Process | Reference median, ms | Candidate median, ms | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 45.321 | 39.582 | 12.66% |
| 2 | 45.648 | 40.259 | 11.81% |
| 3 | 45.507 | 39.899 | 12.32% |
| 4 | 47.248 | 43.394 | 8.16% |
| 5 | 45.444 | 39.192 | 13.76% |

[Summary](summary.json) and `run-1.json` through `run-5.json` retain raw samples.
All **40 pairs** compare complete surface-array bytes, primitive, material and
serialized AABB, and reject shared mesh identity. This covers 43,201 vertices,
normals and 254,880 indices, including flat inner rings and the square outer ring.
The separate eight-pair exploration also passed; its timing is not pooled above.
Every process clears the existing 5% affected-workload improvement gate.

## Verification and limits

Integrated-source suites pass **103 checks**: horizon 19, field surfaces 19,
field integration 39 and world flow 26. These cover exact heights, winding,
seams, normals, bounds, corrupted-profile rejection, independent resources,
custom-field fallback, Home/Fly transitions and lighting/time behavior.

The field-surfaces strict-warning attempt failed on an unsupported maple-tree
wind material. A disposable field/test copy using the original horizon reproduces
the same warning and passes all 19 assertions. The candidate field-surfaces and
world-flow runs retain this warning under the normal runner policy; world flow
also deliberately exercises an invalid time-scale warning. No warning was hidden
or production diagnostic changed. Field integration initially used an incorrect
completion marker; its rerun with the actual marker passes. All attempts and
diagnostic counts remain in [checks](checks/).

No new unit suite, asset, dependency or profiler was introduced. The Luna Max
helper independently reviewed the row equivalence and test scope; the lead ran
the measurements. No full app suite, export, physical-flight, total-loading or
native Linux/macOS acceptance is claimed. The earlier combined atmosphere-texture
shutdown finding in the [parent report](../README.md) remains unresolved.

## Reproduce

From the repository root, use Python to prepare a new scratch directory containing
`reference.gd` from the baseline revision, `candidate.gd` from the current runtime,
and `probe.gd` decompressed from the existing probe. Normalize source text to LF
when comparing against the retained candidate/reference text hashes.

```powershell
python tools/godot/run_checked.py --warnings-as-errors --timeout 60 `
  --require-text 'horizon exact mesh pairs=8 failures=[]' -- `
  .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy `
  --script <absolute-scratch>/probe.gd -- `
  --directory=<absolute-scratch> --output=<new-report.json>
```

Repeat in five fresh processes, adding `--reverse` to processes 2 and 4. Use new
output files. The probe is reused unchanged and does not itself refuse overwrites.
Inspect errors, source identities and parity before reducing timing samples.
For each variant/process take the median of samples with `pair > 0`, then the
median of those five medians. Existing tests use the [checked runner](../../../../../../../tools/godot/README.md).
This follows Godot's [CPU measurement guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html).
