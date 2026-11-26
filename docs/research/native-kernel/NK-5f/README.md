# NK-5f — the statistics sampler reuses the published wheel compressions

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps),
repair (2). Follows [NK-5e](../NK-5e/README.md).

## Why

The statistics observer (`app/statistics/fixed_wing_adapter.gd`) samples every accepted tick after the session's own
`stepped` handler. Split on a paused endpoint in the headless app, it cost 60–64 µs in flight and 145–179 µs while
rolling. On the ground, two of its calls evaluate the wheel compressions that the session's contact observer had
just measured for the same endpoint, natively since NK-5e:

| Per call, rolling | Corsair | Stik |
| --- | ---: | ---: |
| `_compressions` (`session.gear_compressions`) | 49.0 µs | 45.9 µs |
| `session.gear_collapsed` (`Ground.collapsed` recomputes them) | 39.1 µs | 45.9 µs |

## Change

- `flight_session.gd`:
  - `_observe_contact_tick` keeps copies of the endpoint state and aux its compressions were measured at. Packed
    arrays are shared by reference in GDScript, so a reference would follow later in-place writes.
  - `published_gear_compressions(s)` returns a copy of those compressions only while the observer's tick is
    `sim.tick`, cost observations are on, and `s` and `sim.aux` carry the same bytes as that endpoint. Otherwise it
    returns empty and the caller evaluates `gear_compressions(s)`.
  - `published_gear_collapsed(s)` runs `gear_collapsed(s)`'s own checks in `Ground.collapsed`'s order: state and
    aircraft, invalid lake, no gear, the reach shortcut, then each contact against its travel. Only at that last
    step, where `Ground.collapsed` computes the compressions, does it read the publication; without one it computes
    them with the same call. A first version read the publication before the reach shortcut and cost 3–10 µs more
    in flight than the reference.
  - `gear_aux_index()` becomes a tick fact like `anchor_count()` and `downwash_index()`. It was called about 18
    times per tick, each through three memoized calls.
- `fixed_wing_adapter.gd` passes `published = true` only from its own `stepped` handler. There, the two places that
  called `session.gear_compressions(s)` and `session.gear_collapsed(s)` try the published answers first. The airborne
  shortcut and every other path are unchanged. `sample()` called elsewhere, including the crash path
  (`contact_events_changed`), evaluates as before.

## Why the answer is exact

- The contact observer runs first in each `stepped` publication and measures `gear_compressions(sim.state)`: the
  reference itself, or the NK-5e native answer proven bit-identical to it. Between it and the statistics observer
  only other `stepped` observers run, and none of them changes the aircraft, gear, surfaces, lake or track.
- The publication is used only for the same tick and the same state and aux bytes. A crash restart inside the
  publication resets the tick, and an in-place write to the live state changes its bytes. Data edited between ticks
  (Workshop, loads) never reaches it: the adapter asks only from inside the publication.
- `published_gear_collapsed` repeats `Ground.collapsed` step for step. Its only difference is that the compressions
  are read instead of recomputed when published, and they are the same values.

## Evidence

- `app/tests/test_published_compressions.gd` (66/66), Corsair, P-51 and Stik:
  - Direct: 2,000 published endpoints each, over the runway, grass and lake, from 4 m up to 0.5 m into the ground,
    with random gear poses. Published compressions and collapse equal `gear_compressions` and `gear_collapsed`
    (271–384 collapsed endpoints per aircraft). An invalid lake collapses both ways.
  - Refusals: other state bits (1e-12 m), other aux bits, another tick, an in-place write to the live state and
    observations off, a contact-history reset, and a restored history (rebuilt from events, not measured). The
    answer is a copy. A planted publication that puts every contact past its travel decides
    the collapse on the ground and is never read above the reach shortcut.
  - Flights: a 1,440-tick runway roll, a hard landing and a 2,100-tick gear cycle. On every accepted tick the
    published answers equal the reference, and the statistics sample built from them is byte-identical to the one
    built from the session's own evaluations.
- All nineteen installer gates are identical for the unchanged binary
  `e7fb24c3b160d7975204c660e72d2952ddc4395d7c4c35d09c3ee9dc3a672cfc` with the new mirrored sources, and the mutant
  build still fails. Accepted results (tool root, not in Git): `stage-20261126T122147180706Z.json`
  `867efbb36e68e2278b4adde8ff31b25fc38b980cb80359ea7f1f46526eee539a`, `stage_mutant-20261126T122216865394Z.json`
  `a5d74937a03828841c6817ee0023708b3e6a5da1819c34bd17f058b6a9f7c50d`, `trajectory-20261126T122247878382Z.json`
  `560982895b86bfccfb574ceefcc97a5ce5164e0c6732018c4ce0a539df17087b`, `liquid-stage-20261126T122507559020Z.json`
  `0a67e536eab10ac8f0757fbd36eb576a2aaed1a4aa34ac07d1bcf386dfb99852`.
- With the native stage installed, these suites pass: the statistics suites (terrain, eligibility, detector,
  lifecycle, lock, resets, context, failure events, damage flight events), ground-accident and intended-hull-support
  sessions, reset and restore publication, crash-cost coverage, fleet and producers, the runway fleet, electric,
  Extra and Lumber runways, retractable-gear ground and P-51 retracts, lake session, ground contact, the native
  suites, golden flights and replay integrity. `test_flight_statistics_eligibility.gd` overrides `sample()` and
  takes the new optional parameter.
- An independent review found no defect. Its follow-ups are included: the endpoint copies join the start
  transaction's rollback fields, and the contact-history reset and restore clear them.

## Gain

Headless app (debug bridge), paused accepted endpoint, best of three rounds of 40 calls; the statistics sample built
as before and from the publication. This run used the reference backend while the new mirrored sources awaited
their gates; the sample's own work is the same on either backend.

| Statistics sample per tick | Before (µs) | Published (µs) |
| --- | ---: | ---: |
| Corsair, 39 m | 59.4 | 59.1 |
| Corsair, rolling | 218.0 | 115.9 |
| P-51, 43 m | 68.0 | 60.5 |
| P-51, rolling | 149.2 | 83.6 |
| Stik, 36 m | 58.6 | 60.3 |
| Stik, rolling | 124.8 | 70.2 |

In flight the two paths do the same work. The flight rows differ within this protocol's noise; an earlier run gave
Corsair 64.8 for the reference sample.

## Limits

- Only the statistics observer's own `stepped` handler reads the publication. Callers between ticks (the session's
  endpoint checks, presentation) keep their own evaluations, because data may change there without a tick.
- The publication exists only while cost observations are on, as in the app.
