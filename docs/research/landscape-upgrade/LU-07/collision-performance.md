# LU-10 — Collision query performance

Status: bounded query optimization implemented and reviewed; lead native crash/reset checks pass, 2026-10-12.

## Change

`SceneryCollision.contacts()` previously rebuilt the same full-tick candidate-bin list inside every attitude subdivision. Every subdivision uses the same previous/current center-of-gravity endpoints, so the repeated query could be removed without changing candidate order or geometry tests.

The detector now builds one conservative whole-hull sweep envelope, expanded by a chord-padding bound for the full shortest-path rotation. It reuses the original unpadded broadphase result when both envelopes occupy the same 32 m bins, and queries the expanded bins only when padding crosses a cell boundary. One broadphase AABB pass removes proxies that cannot overlap the whole envelope. The existing empty-world gate remains unchanged, and each probe still applies its own padded AABB and exact box/capsule sweep before creating a contact event. The immutable world, identity, response parameters, tie-break, and event construction are unchanged.

The first-hit API still returns the first result from the stable full-contact collector. A separate event-sort bypass is not included: paired measurements show little difference between candidate `first_hit()` and `contacts()`, while the `1e-12` time tie tolerance makes comparator-order changes a correctness risk.

## Differential evidence

`tests/fixtures/scenery_collision_reference.gd` is the full detector copied from starting commit `df36b44`; the test pins its SHA-256 as `FE4AAC96EA43249BC2616C6C3658303E4CE26E10BF85E40B9A4F3F6C864C5E68` after canonicalizing CRLF to LF for Windows checkouts. No other content is normalized. The optimized detector was compared against it with the production eight-point Ugly Stik crash hull and a deterministic 206-proxy world. Across 160 sweeps (including 32 m cell-boundary paths, high-speed travel, mixed obstacle types, and 180-degree attitude changes), all event fields and contact states matched exactly. The fixture produced 53 contacts in 41 cases; `first_hit()` also matched the oracle’s first full-contact event in all 160 cases. A mutation check that removed all envelope candidates was detected by the differential test.

Focused validation passed: detector (51 checks), differential oracle (326 checks), collision session/checkpoint identity (25), collision setup (22), collision-world production test, landscape checkpoint (18), checkpoint integrity (149), and generic checkpoint tests (90). The float64 guard and transcendental-call check passed. Existing session behavior and checkpoint schema are untouched by this detector-only change.

Final portability checks reran all 326 oracle checks with the original LF fixture and with a CRLF copy in an isolated staging project: both passed. Only the fingerprint input canonicalizes line endings; the fixture and collision implementation are unchanged. [LF log](checks/test_landscape_collision_oracle_lf.log), [CRLF log](checks/test_landscape_collision_oracle_crlf.log).

## Paired native benchmark

The captured command used Godot `4.7.2.stable.official.ed1daf0bf` on the same native Windows host and process, with 20 warmups and 200 measured calls per method/case. Samples alternated baseline/candidate/contact order. The lead confirmed no native benchmark or capture was running during the capture; other CPU load was not measured. Queries used the production world (3,867 proxies, 950 bins; identity `c81d0edeb09ab1d4d6803df9ba1d0cf42370e2f073fc663a97a367afa33e6e63`), the full crash hull, and 80 m/s. The 120 Hz and 240 Hz displacements were 0.667 m and 0.333 m respectively. Each near-obstacle query straddled the first contact with the first production car or shade-tree crown.

P95 elapsed microseconds from the paired run:

| Tick rate | Scenario | Baseline `first_hit` | Candidate `first_hit` | Candidate `contacts` |
| ---: | --- | ---: | ---: | ---: |
| 120 Hz | Empty air | 18 | 17 | 15 |
| 120 Hz | Near car | 448 | 313 | 311 |
| 120 Hz | Near tree | 420 | 297 | 295 |
| 240 Hz | Empty air | 20 | 15 | 14 |
| 240 Hz | Near car | 393 | 297 | 317 |
| 240 Hz | Near tree | 470 | 289 | 314 |

The near-car and near-tree p95 fell by 24% and 39% at 240 Hz; p50 fell from 241/245 µs to 172/172 µs. Candidate first-hit and full-contact costs are close, so a separate early-event path was not justified by this profile. The 100 µs p95 goal is still missed for obstacle contacts; this step improves the current query without changing collision semantics, but does not close the cost gate. The host was not instrumented for scheduler or garbage-collection activity, so isolated maxima are not treated as stable performance estimates.

Reproduce the paired capture with:

```powershell
.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/benchmark_landscape_collision.gd
```

The full output is preserved in [benchmark-collision-paired.log](benchmark-collision-paired.log). The benchmark script reports engine/world identity, obstacles, warmups, sample counts, and percentiles. It profiles the baseline detector, candidate `first_hit()`, and candidate `contacts()` in adjacent alternating runs.

## Remaining cost

The narrowphase still tests all eight crash-hull probes against every proxy whose AABB overlaps the full swept-hull envelope. A stronger reduction would need an ordered lower-bound traversal or an identity-safe spatial query cache. Neither is added here: the former must preserve the tolerance-based stable-ID tie rule, and the latter would add cache lifetime and world-version concerns beyond this bounded detector change. Keep the 100 µs target open until another measured optimization clears the oracle tests and the lead repeats the paired benchmark.
