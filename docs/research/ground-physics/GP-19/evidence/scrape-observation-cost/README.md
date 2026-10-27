# GP-19e — Accepted hull-scrape observation without a per-tick key

2026-10-27. Implemented in `226f66b98` (baseline `f9e6dbe8d`). Headless CPU evidence on
the Linux dev VM (Godot 4.8-beta1, shared host); not FPS, listening or target-hardware
qualification.

## Finding and change

The crash director calls `FlightSession.hull_scrape_observation()` at every accepted
240 Hz tick. Before computing, each call serialized a value key with `var_to_bytes` over
the tick, generation, state and bindings: **15,628 bytes** in the default Stik flight
(contact bindings 9,168, hull contact 3,308, lake 1,800, ground support 984, surfaces
200). The key contains the tick, so the first call at a new tick can never hit; the
only production caller makes one call per tick, plus pause and lifecycle calls. The
[VQ-01c profile](../../../../visual-quality-implementation/VQ-01c/tick-observers-2026-10-27/README.md)
puts the observation at 3.26 ms per sample (2.18 ms self) and `HullContact.law()`, which
reformatted nine constants into its identity string on every call, at 0.81 ms.

- The key is now built only when the call repeats the cached tick. A first call at a new
  tick computes the packet, records the tick and stores no key or copy; a second call at
  that tick recomputes and stores both; later calls reuse the copy under the same full
  value-key check as before. Reset and restore clear the tick with the key.
- `HullContact.law()` formats its string once into a static.

## Parity

[`hull_scrape_pair.gd`](../../../../../../research/performance/hull_scrape_pair.gd) runs the
baseline and candidate sessions side by side on `test_hull_scrape_session.gd`'s sliding
wingtip start, calling the observation one to three times per tick for 480 ticks with a
pause toggle, and mutating returned rows:

| Aircraft data | Observations compared | With loaded scrape rows | Bytewise equal | Final state |
| --- | ---: | ---: | --- | --- |
| Electric Stik | 960 | 780 | yes | identical |
| Glow Stik (61FX, live fuel mass) | 960 | 488 | yes | identical |

The memoized law string equals the baseline formatter's.

An independent read-only review found no counterexample. One sequence differs by
construction: the second same-tick call recomputes instead of returning the first
call's copy. Both are equal whenever the packet depends only on the key inputs, which
is the original cache's premise. Inputs outside the key (`environment.road`, finite-fuel
mode, `sim.dt()`) have no mid-tick mutation path for aircraft sessions; vehicle roads
are set only by the ground-vehicle session.

Passing scripts (checks): hull scrape session (56), hull friction observation (388),
hull scrape audio (60), hull crossing (40), hull support normal (70), intended hull
support (174) and its sessions (53), crash audio (12), crash hull labels (274), accident
integration (78), report (119), settlement (46), ground accidents (68) and sessions (33),
checkpoint (92), checkpoint integrity (149), flight reset transaction (148).
`test_golden` output is identical to the baseline.

## Cost

First observation per tick, summed over the 480 ticks of the probe:

| Aircraft data | Baseline µs/tick | Candidate µs/tick | Ratio |
| --- | ---: | ---: | ---: |
| Electric Stik | 295.8 | 111.3 | 0.376 |
| Glow Stik | 637.5 | 354.2 | 0.556 |

These are single probe runs while the wingtip scrapes. The airborne and runway
whole-application effect, combined with LU-25-R3, is in the VQ-01c record.
