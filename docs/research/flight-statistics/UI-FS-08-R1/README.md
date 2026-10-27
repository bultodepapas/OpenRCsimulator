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
