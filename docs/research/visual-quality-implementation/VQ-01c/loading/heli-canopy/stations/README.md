# DT-11a — bounded helicopter canopy station scans

2026-10-15. Accepted refinement of HELI-30 canopy contour construction.

Previously each of 17 longitudinal planes scanned all 38,240 canopy triangles.
The collector now visits triangles once, finds their inclusive plane range with
binary search, and accumulates each plane's intersections in original triangle/
edge order. Profile evaluation retains the same arithmetic and output order.
Planes retain their original `lerpf` values in a `PackedFloat64Array`; non-finite
triangle coordinates use the original exhaustive comparison path. Nothing is
cached between calls, and the simulation state is unchanged.

## Native paired measurement

Godot 4.7.2 `ed1daf0bf`, Windows, Compatibility/OpenGL, RTX 3090, Dummy audio.
Five fresh processes, six serial alternating reference/candidate pairs per
workload, with the starting order reversed between processes. Model construction,
snapshots and cleanup are outside the timers. Pair zero is retained in raw data;
the table pools the remaining 25 samples per variant/workload.

| Workload | Reference median | Candidate median | Reduction |
| --- | ---: | ---: | ---: |
| Four canopy contours | 88.701 ms | 20.501 ms | 76.9% |
| Complete helicopter night kit | 96.207 ms | 28.519 ms | 70.4% |

All five process medians improve for both workloads. [Summary](summary.json) and
[manifest](manifest.json) retain per-process results, commands and source hashes.
This removes about 68 ms from kit construction in this paired campaign. Host
activity is uncontrolled; these timings do not establish whole Home/Fly loading,
FPS, crash latency, cold startup or exported-package performance. Do not compare
absolute timings across the preceding independent campaigns.

## Workspace tradeoff

The real canopy has 650,080 triangle/plane visits in the exhaustive scan and
5,638 in the bounded traversal. The new per-call workspace retains all planes'
intersections until profile evaluation finishes, rather than one plane at a time.
A separate [headless probe](workspace.json) records 5,638 segments / 11,276 points
and a 686,252-byte static-memory increase while sections are held (about 670 KiB).
The three warm probes return to their pre-call allocation count after clearing
sections; the first leaves a 27,060-byte residual. This is an attributed temporary
workspace observation, not a peak-memory or whole-application leak qualification.
Workspace scales with triangle/plane intersections; it is not a fixed-size cache.

## Verification

All **60 real contour/complete-kit geometry pairs** match byte for byte. Each
process runs the same 256 synthetic cases: **1,280 case evaluations**, not 1,280
distinct scenarios. They include exact/near station boundaries, coplanar and
degenerate edges, incomplete final triangles, random geometry, empty inputs,
reordered/duplicate profiles, out-of-range profile heights and NaN/±infinite Z.
The comparison uses the frozen current baseline, including the preceding native
vertex-transform and null-index repair.

Five permanent checks verify inclusive endpoints, intersection order, independent
workspaces/input ownership, plane differences smaller than float32 precision and
the non-finite fallback. Runtime, comparison and regression drafts were parsed
outside `app/` before integration; the disposable test parse copy points to the
candidate because it introduces the private section helper.

| Integration check | Result |
| --- | --- |
| Helicopter lights, headless | 47 checks; clean exit |
| Night rotor, headless | 18 checks; clean exit |
| Crash presentation, headless | 44 checks; clean exit |
| Home preview cache, headless | 18 checks; clean exit in this run |
| Helicopter lights, native | 47 checks; two texture shutdown errors |

[Checks](checks.json) and logs retain the diagnostics. Native comparison processes
themselves exit cleanly. The integrated native test still reports two leaked
349,524-byte textures, previously [reproduced on the reference](../../heli-updates/README.md).
It is not a clean native integration pass. One clean Home exit does not close its
historical intermittent audio lifecycle issue. Full CI, exports and pilot/rendered
flight acceptance were not run for this slice.

## Reproduce

```powershell
python research/visual-quality/heli-canopy-stations/run.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/heli-canopy-stations-reproduction
```

Use a fresh output directory. The runner expands the retained reference and uses
the current runtime, or an external draft supplied with `--candidate`. Accepted
runtime/test snapshots, parse logs and evidence hashes are retained here.
`research/visual-quality/heli-canopy-stations/workspace.gd` accepts `--candidate`
and `--out` after Godot's `--` separator to reproduce the workspace probe.

Primary source consulted 2026-10-15: [Godot PackedFloat64Array.bsearch](https://docs.godotengine.org/en/stable/classes/class_packedfloat64array.html#class-packedfloat64array-method-bsearch)
documents sorted input, the upper insertion boundary with `before=false`, and
NaN caveats. The implementation preserves closed triangle bounds and bypasses
binary search for non-finite triangle coordinates.
