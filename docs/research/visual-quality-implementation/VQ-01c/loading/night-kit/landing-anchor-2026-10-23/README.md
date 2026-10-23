# DT-11a — skip unused landing-light geometry

2026-10-23. Adopt a narrow construction optimization in
`app/render/world/aircraft_lights.gd`: when the aircraft supplies a `landing`
anchor, use it without first scanning the triangles for a fallback seat.
Aircraft without that anchor retain the same scan and fallback arithmetic.
There is no cache, geometry, lighting, physics or dependency change.

## Measurement

Windows, Ryzen 9 5900X, RTX 3090 / NVIDIA 617.42, Godot **4.7.2 ed1daf0bf**,
Compatibility, Dummy audio. Five fresh native processes ran sequentially on
the shared workstation. Each used six alternating reference/candidate pairs
per visual family; even processes reversed the initial order. The first pair
is separate; warm results pool pairs 1–5, **25 observations per variant/family**.
Fresh process does not mean cold OS/GPU caches.

The timer surrounds `attach` only: complete night-kit construction. Aircraft
building, output serialization, comparison, teardown and rendering are outside
the timer. The 1080p launch option does not turn these CPU timings into render
performance or Home-ready measurements.

| Family | Reference median | Candidate median | Reduction |
| --- | ---: | ---: | ---: |
| P-51, authored landing anchor | 90.528 ms | 86.177 ms | 4.351 ms / 4.8% |
| Timber, authored landing anchor | 68.843 ms | 62.830 ms | 6.013 ms / 8.7% |
| Stik, fallback | 84.061 ms | 84.342 ms | No gain |
| Extra, fallback | 39.502 ms | 39.835 ms | No gain |
| Corsair, fallback | 141.270 ms | 142.052 ms | No gain |
| Avanti, fallback | 201.873 ms | 203.620 ms | No gain |

Both affected families improve in **all five process medians**. Unchanged
families vary by less than 1%; do not claim a fleet-wide improvement.
[summary.json](summary.json) retains first-pair and per-process medians;
`native-1.json` through `native-5.json` retain all 360 measured calls.

## Correctness and visual evidence

- **180 paired kit comparisons** across six families match exactly for the
  captured child fields: names, transforms, visibility, metadata, mesh arrays,
  shader source/uniforms, shadow/cull settings and spotlight parameters.
  The reused comparator omits kit-root metadata; this is not exhaustive resource
  identity. The patch leaves root setup and metadata untouched.
- The reused fixture also passes **256 synthetic geometry cases per process**.
  These are supporting collector regressions, not additional kit timings.
- Integrated native-headless checks: night kit **36**, P-51 anchors/gear gating
  **13**, world lighting **86**, Home preview lifecycle **23**: **158 total**.
  All pass with engine warnings treated as errors. The Home test prints its
  existing aircraft-data advisory, separately from engine diagnostics.
- Three native **1920×1080, 4× MSAA** studio A/B cases—P-51, Timber and fallback
  Stik—are pixel-identical. [Capture report](captures/report.json) and
  [manifest](manifest.json) retain results and both hashes. One PNG per identical
  pair is retained; duplicate reference PNGs were discarded. All three retained
  images were visually inspected. These are stills, not flight readability proof.
- Independent Luna Max review found no blocker and independently confirmed both
  affected families' per-process improvement. It identified the snapshot's
  kit-root metadata limitation, stated above.

The method being skipped, `wing_piece`, only reads triangle data and returns
local geometry. Presence of `landing_right` alone still takes the original
primary-light fallback. Invalid authored data is not assigned a new recovery
policy by this change.

## Reproduction and limits

`reference.gd.gz` and `candidate.gd.gz` preserve the exact measured sources.
`compare.gd.gz` reuses `research/visual-quality/aircraft-light-geometry/compare.gd`
with its workload list narrowed to `kit_build`; no geometry timing is included.
Decompress these into a new ignored `tmp/` directory. The manifest retains all
five commands; adjust the absolute paths, preserve ordering and use new outputs.
Run native collections sequentially.

```powershell
python tools/godot/run_checked.py --timeout 120 --warnings-as-errors -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script tests/test_night_kit.gd
# Repeat for test_p51_lights.gd and test_world_field_lights.gd.
```

For images, run the retained [capture fixture](capture.gd) with the native
Compatibility renderer, `--resolution 1920x1080`, and user arguments
`--reference=<decompressed reference.gd> --candidate=<decompressed candidate.gd>
--out=<new absolute tmp directory>`. It forces the internal render size to
1080p and checks exact pixel equality. Keep generated duplicates outside Git.

The whole Linux `app/test.sh` and `app/capture.sh` runners stop before execution
in this CRLF Windows checkout (`pipefail\r: invalid option name`). They are not
claimed as passing. Focused checked-runner logs/verdicts are retained in `checks/`.
Raw reports preserve their original temporary paths; colocated logs remain the
retained copies.

An initial Home check used the wrong required completion string (`failed=0`)
and was correctly rejected by the runner despite all 23 assertions passing.
`checks/preview-marker-failure/` retains that failed collection;
`checks/preview-final/` is the subsequent passing run with the correct marker.

This removes measured unnecessary work with a small branch change. Full
Home/Fly readiness, frame pacing, night-flight acceptance, exports and platform
qualification remain open. Do not sum savings from historical campaigns or
represent these construction timings as an FPS gain.
