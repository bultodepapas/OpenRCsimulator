# RCV terrain sampler performance

Evidence collected 2026-10-14 for the surface-table validation cache in `app/physics/ground_vehicle/airfield_course.gd`. The cache skips full table validation only when the entire `PackedFloat64Array` equals the last validated table. A different table is still validated; invalid input is not cached. The sampler also constructs its fail-closed invalid-result dictionary only on an error path.

## Method

`research/rc-monster-truck/performance/run_airfield_profile.py` launches a bounded hidden Godot process and records source and executable hashes. `bench_airfield.gd` first runs 60 warmup and 480 measured `Session.tick_once` ticks at 240 Hz, then measures three sampler implementations in one process with rotated call order:

- **Reference:** captured pre-cache `AirfieldCourse.sample`, including full validation on every call.
- **Cached eager:** the candidate implementation with full-array cache validation, but allocating the invalid-result dictionary on every call.
- **Candidate:** the cached sampler, allocating the invalid-result dictionary only when a sample fails.

Each implementation handles 4,800 calls across the 540 positions recorded from the route and 36 authored feature, wall, runway, and out-of-bounds queries (576 positions total). Results are compared as complete dictionaries, including the normal, friction, track coverage, IDs, bounds flag, and nearby walls. The session is loaded from the frozen vehicle data at `research/rc-monster-truck/performance/vehicle_snapshot.json` (SHA-256 `732ad4197a60b111610e7eadf169e4718a68bdf85799f7cff4350eb4df698a0c`), so current model edits do not change the paired input.

The route uses the production default airfield's `track_start`, armed throttle 0.55, zero steering, and zero brake. It includes the authored dirt loop and tabletop. The runs used Godot 4.7.2 official debug build on an AMD Ryzen 9 5900X, with the native ground-vehicle dynamics backend. There is no rendering or recording in this harness.

## Results

| Run | Reference mean | Cached eager mean | Candidate mean | Cache gain vs reference | Deferred-allocation gain vs cached eager | Exact outputs |
|---|---:|---:|---:|---:|---:|---|
| [candidate-paired-03](candidate-paired-03/profile.json) | 51.781 µs | 49.137 µs | 46.717 µs | 5.1% | 4.9% | 4,800/4,800 for both comparisons |
| [candidate-paired-04](candidate-paired-04/profile.json) | 52.962 µs | 50.457 µs | 48.288 µs | 4.7% | 4.3% | 4,800/4,800 for both comparisons |

Both runs also passed cache invalidation checks for a same-length valid mutation, a NaN mutation, an empty-table transition, and restoration of the original table. The invalid mutations returned the same fail-closed result shape as the reference; the valid changed friction value altered the sample and matched the reference exactly.

The complete 540-sample route dictionaries and vehicle trajectory SHA-256 match the pre-cache paired run: `fe7c689651fc40f49fa47c89116b703aab4e1732c373181a8c82fe394e1df9bd`. The route had dirt coverage on all 540 samples, with `dirt_loop` reported 359 times and `tabletop` 181 times.

The profiles also record complete-tick timings, but those are contextual only. They vary between runs and include the rest of the production dynamics work, so the measured sampler gains are not presented as an end-to-end tick-speedup. These results establish an improvement for this debug-build sampler workload; they do not establish physical-model accuracy or performance on other hardware/build configurations.
