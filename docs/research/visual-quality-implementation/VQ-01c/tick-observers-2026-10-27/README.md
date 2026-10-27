# VQ-01c — accepted-tick observer attribution and first repairs (2026-10-27)

Linux dev VM, Godot 4.8-beta1, headless, Dummy audio, shared 12-vCPU host with other
projects running. This is CPU attribution and paired relative evidence. It does not
measure FPS, GPU, native hardware or the Gate P statistic. Runtime source: baseline
`f9e6dbe8d`, repairs in `226f66b98`.

## Where an accepted tick goes

`debugctl.py launch --headless --script-profile`, default Stik `fly start=airborne`,
throttle 0.7, then `profile seconds=40`: 14 samples, 158 accepted ticks (about 11 per
sample). The profiler adds call overhead and attributes GDScript only. Listings:
[by total](profile/airborne-by-total.txt), [by self](profile/airborne-by-self.txt).

| Work per profile sample | ms (total) |
| --- | ---: |
| `Simulation.step`, including `stepped` observers | 42.49 |
| Stage evaluation `_wheel_evaluate` (aero loads 6.33, ground evaluation 3.19) | 12.11 |
| `_pre_step` | 3.79 |
| Collision step (lake first hit 2.26) | 3.52 |
| **Observers on `stepped`** | **≈ 20.3** |
| — flight audio accepted tick: ground contact endpoint 6.66 (wheel snapshot 5.43, of which material lookup 2.03), mechanical 1.50 | 8.26 |
| — flight statistics adapter | 5.10 |
| — crash director hull scrape (observation 3.26, of which self 2.18) | 3.72 |
| — windsock and field people | 1.36 |
| — profile smoke 0.60, session contact commit 0.56, ground gear 0.41, accident contacts 0.33 | 1.90 |

About half of the step's script time is presentation observers. `Simulation.step_usec`
is measured before `stepped.emit` (1,490 µs unprofiled in this flight), and
`bench_regimes.gd` and the session pair probes never attach the observers, so earlier
per-tick budgets did not include this cost.

An earlier 20 s window, flown near the default lake, was printed but not retained. It
recorded 111,120 `LakeSurface._point_segment_distance_sq` calls from 5,508
`_polygon_state` calls, and `ground_audio_model.surface_observation` as the largest
self-time entry.

## Repairs

Both are exact: outputs are bytewise equal to the baseline and `test_golden` output is
identical.

- [LU-25-R3](../../../landscape-upgrade/LU-25-R3/README.md): inline the lake polygon
  edge distance. Terrain query near the lake 36% shorter (median of three runs).
- [GP-19e](../../../ground-physics/GP-19/evidence/scrape-observation-cost/README.md):
  no per-tick 15.6 kB cache key; hull law identity formatted once.

## Whole-application paired result

[`app_cpu_per_sim.py`](../../../../../research/performance/app_cpu_per_sim.py) at a
30 fps cap and `Engine.time_scale` 0.5, 10 s warmup and 40 s sample, alternating
baseline/candidate order per pair. The baseline scripts sat in the working tree only
until each flight had loaded them. The value is main-thread CPU per simulated second.

| Scenario | Pair | Baseline ms | Candidate ms | Change |
| --- | ---: | ---: | ---: | ---: |
| Airborne climb | 1 | 816.31 | 802.55 | −1.69% |
| Airborne climb | 2 | 851.24 | 807.62 | −5.12% |
| Airborne climb | 3 | 948.99 | 867.87 | −8.55% |
| Runway idle | 1 | 1,655.07 | 1,322.31 | −20.10% |
| Runway idle | 2 | 1,317.30 | 1,306.86 | −0.79% |
| Runway idle | 3 | 1,293.85 | 1,315.46 | +1.67% |

All three airborne pairs favour the candidate (median −5.1%; whole-process CPU −1.4%,
−4.6%, −8.3%). Both roles drifted upward across the session, and the spread is wide,
so treat the magnitude as approximate.

Runway idle is **inconclusive**. With loaded wheels `sim_step_usec` is about 3.3 ms, so
the main thread saturates (realtime 0.60–0.77, 12–16 fps). The metric then reduces to
the inverse of realtime, and a faster role also draws more frames. The first baseline
is an outlier; the other two pairs are within noise. No runway gain is claimed. The
first runway attempt taxied with throttle 0.25 and crashed off the runway before
sampling ended, so the scenario now idles.

A first attempt measured whole-process CPU with uncapped frames and saw no difference
(1,109 vs 1,114 ms per simulated second): headless frames are uncapped, so saved time
goes into extra frames. It was discarded as a method failure, not a result.

## Unprofiled observer share

`app_cpu_per_sim.py` with `OPENRC_DETACH_PRESENTATION=1` disconnects the six
presentation observers (windsock/people, ground gear, profile smoke, flight audio, crash
director, statistics) after the flight starts; the session's contact commit and the
recorder stay connected. Same settings as above, on the source with LU-25-R3/R4 and
GP-19e, alternating order ([raw](observer-share-pairs.jsonl)):

| Scenario | Pair 1 | Pair 2 | Pair 3 |
| --- | ---: | ---: | ---: |
| Airborne climb, main-thread ms per simulated second | 717 → 468 (−34.6%) | 718 → 467 (−34.9%) | 722 → 482 (−33.2%) |
| Runway idle | 983 → 756 (−23.1%) | 961 → 743 (−22.7%) | 976 → 747 (−23.6%) |

Without profiler overhead, the presentation observers take about a third of
main-thread CPU in flight and about a quarter on the runway (both including per-frame
work at the 30 fps cap). This bounds the gain available from running them per frame
instead of per tick. The owner chose that direction; measured steps so far:

- [GP-19f](../../../ground-physics/GP-19/evidence/unloaded-rows/README.md): the ground-audio
  observer stays per tick but returns cheap unloaded rows well clear of the ground. Flight
  main-thread CPU −10.3% median (−11.8%, −7.1%, −10.3%); touchdown cues unchanged.
- Windsock and field people per frame: rejected (+3.2%, +1.0%, −1.2%; no gain beyond
  noise) and reverted.

## Not done: candidates for owners

| Candidate | Profile cost | Why not here |
| --- | --- | --- |
| Skip the wheel material lookup while a wheel carries no load | 2.03 ms per sample | Material is audible only while rolling (`force_off` ≥ 1 N), but `test_ground_audio_materials.gd` pins resolved material on every wheel; a GP-19/audio contract decision |
| Incremental exact median for statistics speed windows | `_add_speed_candidate` 1.35 ms | Copies and sorts the whole window every tick; exact alternative needs its own parity proof |
| Cache `wheel_brake_available()` (6 calls per tick) | 1.75 ms | Validates the public, mutable `aircraft` dictionary; caching needs an ownership guarantee |
| Value-equality guards (`LakeSurface.is_valid_definition`, `is_valid_surface_table`) | 1.09 + 0.61 ms | Deliberate fail-closed design (LU-25-R1) |
| 240 Hz windsock/people/profile-smoke advance | ≈ 2 ms | Lower cadence changes visuals; owner decision |

The runway-idle tick (about 3.3 ms against 1.3–1.8 ms airborne, before observers) was
then profiled: per-point lake sampling in the hull contact law was the largest leaf.
[LU-25-R4](../../../landscape-upgrade/LU-25-R4/README.md) rejects it for a hull wholly
outside the bank bounds: complete-session runway tick −22% median in three pairs,
identical fingerprints. Ranked next ideas: [optimization scan](../../../godot-optimization-scan-2026-10-27.md).
