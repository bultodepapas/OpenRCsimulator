# NITRO-06-R2 — Reuse repeated carburettor roots within a glow evaluation

2026-10-27. Working-tree change on top of [NITRO-06-R1](../NITRO-06-R1/README.md). Headless
CPU evidence on the Linux dev VM (Godot 4.8-beta1 official editor binary, shared host);
not FPS, release-build or target-hardware qualification. No law or output change.

## Finding and change

Each glow evaluation point computes the carburettor admission twice with the same
opening and speed: in the lifecycle (`lifecycle.gd`) and for the main-tank fuel-feed
solve (`flight.gd`). Every admission solves two roots (restricted and wide open), so
half of the solves repeat a demand ratio solved moments earlier.

`charge_ratio` now remembers the last two interior roots (finite y above the choke
ratio, where equal floats are equal bits) and returns a stored root for an equal y. The
solve is a pure function of y, so the root is identical. Launch trim runs on a worker
thread, so a `Mutex` guards the four-value memo, as LU-25-R1 guards its lake cache.
Invalid and choked inputs return before the memo and are unchanged.

## Parity

[`carburetor_pair.gd`](../../../../research/performance/carburetor_pair.gd), against
`b6e3fe7d4`, bytewise:

- 506,348 single solves and the same sweep replayed as (a, b, a, b) pairs, so repeats
  come from the memo: 0 mismatches.
- Four threads plus the main thread walking 3,726 interior inputs from different offsets
  in the same (a, b, a, b) pattern, about 74,500 calls while the others overwrite the
  memo: 0 mismatches.
- `admission` over 60,802 combinations: 0 mismatches.

The glow runway session fingerprint is the same for `HEAD`, R1 and R2 (all 12 runs).
Glow, NITRO, trim and golden scripts: [run summary](tests.txt).

## Cost

| Measurement | R1 | R2 | Change |
| --- | ---: | ---: | ---: |
| Glow runway session, pair 1, median µs/tick | 5,037 | 4,507 | −10.5% |
| Glow runway session, pair 2 | 5,145 | 4,573 | −11.1% |
| Glow runway session, pair 3 | 4,979 | 4,593 | −7.8% |
| `charge_ratio`, 20,000 distinct interior solves (no repeats) | 5.37 µs | 6.14–6.16 µs | +15% |

The memo costs about 0.8 µs per miss (two lock/unlock pairs and the comparisons), which
the sweep of distinct values shows; in flight, half the solves are repeats, and the tick
falls about 10%. Combined with R1, the glow runway tick fell from about 5.3–5.4 ms to
4.5–4.6 ms.
