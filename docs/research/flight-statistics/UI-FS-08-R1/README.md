# UI-FS-08-R1 — Statistics observer cost at accepted ticks

2026-10-27. Working-tree change on baseline `b6e3fe7d4`, part of the owner-selected
"observers per frame" work. Headless CPU evidence on the Linux dev VM (Godot 4.8-beta1
official editor binary, shared host). No statistics rule, output or storage change.

## Finding and change

The fixed-wing statistics adapter samples every accepted 240 Hz tick and its detector
observes each sample. Two parts did avoidable work:

- `FixedWingAdapter.sample` called `gear_compressions`, three terrain samples per tick, only
  to derive `> 0.00001` contact flags. Above the contact law's own no-touch bound (gear
  reach over the terrain height bound) every flag is false, so `_compressions` returns one
  negative value per contact there. Invalid state, aircraft or surface table keep the
  original call; the session lake is always valid (`set_lake_context` refuses others).
- `Detector._add_speed_candidate` copied the speed window into typed arrays, sorted
  duplicates for the medians and looped over every value for stability. It now sorts packed
  copies natively and decides stability from the sorted extremes. The values are validated
  finite, the sorted order and medians are the same, and |v − median| (rounded) is monotonic
  on each side of the median, so checking the extremes is exact.

## Parity

- [`statistics_sample_pair.gd`](../../../../research/performance/statistics_sample_pair.gd):
  the baseline and candidate adapters on one real session through two descents with
  touchdown and a runway idle, 7,200 samples (2,907 ground-supported): all bytewise equal.
- [`statistics_detector_pair.gd`](../../../../research/performance/statistics_detector_pair.gd):
  identical real samples into the baseline and candidate detectors through a 30 s trimmed
  cruise and two descents, 12,960 ticks with 11,068 median candidates: returned events and
  complete `snapshot()` bytewise equal after every tick.
- Statistics scripts pass: detector (111), lifecycle (51), resets (48), store (49), writer
  (18), helicopter impact detector (26), statistics UI ([summary](tests.txt)).

## Cost

| Measurement | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| `sample()` per tick, descents only | 130.6 µs | 90.8 µs | −30% |
| `sample()` per tick, descents and runway | 140.4 µs | 109.8 µs | −22% |
| `observe()` per tick | 207.2 µs | 72.2 µs | −65% |

Whole-app airborne pairs (baseline from a hard-linked snapshot with both statistics files
from `HEAD`) were inconclusive: −9.0%, +8.1% and −3.7% with the baseline itself ranging
726–813 ms per simulated second ([raw](pairs.jsonl)). The component results are the
evidence; the whole-app share is below what three pairs on this shared host resolve.

## UI-FS-08-R2 — Composed terrain correction, 2026-11-06

External audit A6/F3 was reproduced on `84f4657814c157f1556f965861c0ab8623f48d8e`, Windows x86-64, Godot `4.8.beta2.official.cafc17a19` headless/reference. At the Club circuit tabletop, Stik NED `[39, -4, -0.755]` had physical wheel compressions `[0.01191764341364, 0.01281855653183, 0.01457621385286]` m, while the observer's field-only bound skipped all wheels. Its terrain sample also omitted the circuit, corrupting clearance and slope-relative attitude. R1's earlier equivalence claims apply to its tested scenes, not this raised terrain.

The adapter now reads `session.environment.ground()` and `ground_max_height()`, preserving malformed-table rejection and the authoritative `session.gear_compressions()` narrow query. It removes the observer's cached lake snapshot so accepted tick-zero lake/track changes use the current terrain. This changes statistics observations, not the simulation or classifier thresholds; existing historical records are not recalculated.

The new [`test_flight_statistics_terrain.gd`](../../../../app/tests/test_flight_statistics_terrain.gd) failed 19 of 82 checks before the repair and passes all 82 after it. Coverage includes the exact witness, near-tabletop clearance, ramps, rollers, banked turns, edges, runway/field controls, a terrain-relative roll discriminator, invalid surfaces/positions, rejected and accepted terrain changes, and unchanged simulation checkpoints during sampling. Production-adapter samples drive a complete staged touch-and-go, full-stop and next-takeoff sequence through the detector. These are geometry/classification fixtures, not a dynamically flown landing or physical validation.

Six focused suites pass **646 checks**: terrain (82), detector (173), lifecycle (73), ground accidents (68), intended hull-support sessions (53), and damage flight events (197). All six receipts are complete and pass with zero engine errors/warnings; source-model caveats remain printed. Lifecycle coverage includes exact observed/unobserved physics checkpoints, rollback and observer attachment. Import and draft parsing pass. The full app/visual suites and target-hardware performance were not run; this is not an FPS or physical-validation claim.

Reproduce with the [checked script runner](../../../tools/shared.md#one-godot-script). Local raw receipts are in ignored `tmp/statistics-terrain-f3/checks/`; no images are required. Candidate SHA-256: `app/statistics/fixed_wing_adapter.gd` = `797906a2db3cf3e896776a7dec7183c63f517af239d7ef4b3fe04a545e63c232`; `app/tests/test_flight_statistics_terrain.gd` = `6ed26271fe4685515828b4ffe805392de4a4d5c32ebe55a6347876c34e3a2046`.
