# Track sampler scalar-allocation pass

Evidence collected 2026-10-14 for the float64 obstacle-track sampler in `app/physics/ground_vehicle/airfield_track.gd`. The pass removes temporary smoothstep arrays and avoids constructing a discarded empty-result dictionary on valid samples. Its equations and result dictionary are unchanged.

## Exact-output verification

`research/rc-monster-truck/performance-r2/verify_track_parity.gd` keeps a copy of the pre-change sampler as an independent reference. It compares every returned dictionary field, treating matching NaNs as equal. The 4,615 comparisons all passed:

| Case group | Comparisons | Result |
|---|---:|---|
| Default loop route | 172 | Exact |
| Loop boundaries and shoulders | 2,236 | Exact |
| Technical and access strips | 430 | Exact |
| Ramp and roller transitions | 780 | Exact |
| Changed valid track data | 987 | Exact |
| Empty, non-finite and distant coordinates | 10 | Exact |

The changed-data case adjusts pad and bank heights, lane/shoulder/technical widths, and the first ramp and roller geometry; the resulting track remains valid. Boundary cases sample just below, at and just above representative strip, approach, deck and descent transitions. Invalid-input cases include an empty track, NaN/Inf coordinates and large finite coordinates.

Reproduce the exact-output check from the repository root with the pinned Godot console executable:

```powershell
$Godot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --path app --script "$PWD/research/rc-monster-truck/performance-r2/verify_track_parity.gd"
```

Expected result: `comparisons: 4615`, `failures: 0`, and `ok: true`.

## Timing status

The opt-in same-process comparison ran with the pinned Windows Godot 4.7.2 console build on the AMD Ryzen 9 5900X. It loaded one default track, warmed both methods, and alternated which implementation ran first over seven 16,000-call trials and 935 loop-edge/feature positions. Exact parity also passed again in the same process: 4,615 comparisons, zero failures.

The candidate median was 18.72 µs/sample versus 38.70 µs/sample for the preserved implementation, a 51.6% reduction in this direct-sampler microbenchmark. The means were 24.00 and 53.95 µs/sample respectively. Trial ranges were wide: 17.15–42.97 µs for the candidate and 28.25–105.64 µs for the reference. Treat the median difference as preliminary shared-host evidence because of that variance. The benchmark has no vehicle or session ticks and does not establish an end-to-end tick improvement. Full output, including every trial, is in [the timing log](performance-track-scalar-r2-timing.log). A separate current-model [Session cost profile](performance-active-session-r2.md) records total tick cost; it is not an A/B test and does not attribute whole-tick cost to this sampler pass.

Reproduce the timing mode with:

```powershell
& $Godot --headless --path app --script "$PWD/research/rc-monster-truck/performance-r2/verify_track_parity.gd" -- --bench
```

The prior airfield-course cache measurements in [RCV-performance](../RCV-performance/README.md) concern a separate optimization and are not evidence for this Track sampler pass.

## Source identity and limits

The exact-output run used Godot `4.7.2.stable.official.ed1daf0bf` on Windows x86_64 with an AMD Ryzen 9 5900X. At the time of the run, SHA-256 identities were:

| Input | SHA-256 |
|---|---|
| `app/physics/ground_vehicle/airfield_track.gd` | `08efe15de45136ce066b2c212163ef41e36199f662baa5eb6bbcc8e640e4bd30` |
| `app/data/ground_vehicle/airfield_track.json` | `b178c5c22dd77160a48bd72d2e473f52e66a65c52843d25770b224f6cebbba81` |
| `research/rc-monster-truck/performance-r2/verify_track_parity.gd` | `c662a5632814e5a391bc4e7899133c0a5e535e5bf2a5821a32213149419ced65` |
| Pinned Godot console executable | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbb846643` |

This verifies software output equivalence over the listed cases. It does not establish physical validity, nor does exact sampler parity by itself establish a performance gain.
