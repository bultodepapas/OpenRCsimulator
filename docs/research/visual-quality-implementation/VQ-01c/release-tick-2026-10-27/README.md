# VQ-01c — release-template tick cost on current source (2026-10-27)

First measurement of the simulation tick inside an official **release template** on the
current source (all 2026-10-27 optimizations included). It answers the optimization scan's
item 5 and the native scoping's NK-0 question for this host. Linux dev VM, Intel i5-10500
under KVM, shared with other sessions; Godot 4.8-beta1 official binaries; no rendering.

## Method

Release templates ignore `--path` and `--script`, so
[`release_session_probe/build.sh`](../../../../../research/performance/release_session_probe/build.sh)
exports a hard-linked snapshot of `app/` with `session_probe.gd` and a wrapper main scene,
using the official `linux_release.x86_64` template (SHA-512 checked against the release's
`SHA512-SUMS.txt`). The debug side ran the same probe with the official editor binary on the
same snapshot. `session_probe.gd`: default Stik, real input and simulation callbacks, 2,400
warmup and 14,400 sampled ticks, alternating order, three pairs per case
([summary](summary.json)).

## Result

| Case | Debug median µs/tick | Release median µs/tick | Speedup | p95 debug → release |
| --- | ---: | ---: | ---: | --- |
| Airborne trim, pair 1 | 1,203 | 1,102 | ×1.09 | 2,053 → 2,168 |
| Airborne trim, pair 2 | 1,254 | 1,022 | ×1.23 | 2,241 → 1,766 |
| Airborne trim, pair 3 | 1,237 | 997 | ×1.24 | 2,269 → 1,712 |
| Runway idle, pair 1 | 2,595 | 2,194 | ×1.18 | 4,271 → 3,657 |
| Runway idle, pair 2 | 2,644 | 2,149 | ×1.23 | 4,877 → 3,476 |
| Runway idle, pair 3 | 2,662 | 2,241 | ×1.19 | 4,672 → 3,934 |

Median speedup ×1.23 airborne and ×1.19 on the runway. Debug and release give the same state
fingerprint in every case, so the build type does not change the physics.

## Reading

- The release gain on current source is smaller than the 1.5–1.9× NITRO-02 measured on
  2026-10-13 (Windows, Godot 4.7.2) and at the low end of the engine benchmarks' 1.14–1.93×.
  A plausible reason, not measured: the 2026-10-27 work removed much of the call- and
  allocation-heavy GDScript that release templates speed up most.
- On this host a release tick still costs about 1.0 ms airborne and 2.2 ms on the runway,
  above the 500 µs Gate P statistic; this VM is slower than the reference hardware, so the
  absolute numbers are not a Gate P verdict.
- Presentation observers are outside `session_probe.gd`; whole-app shares are in the
  [tick-observer record](../tick-observers-2026-10-27/README.md).
