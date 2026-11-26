# NK-5i — the statistics sampler's endpoint evaluations in one native answer

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5h](../NK-5h/README.md).

## Why

An in-app attribution of a flying tick (Windows, Forward+, Corsair, debug bridge attached) found the statistics
observer (`statistics/fixed_wing_adapter.gd`, `_stepped`) the largest `stepped` observer, at 150–180 µs per tick.
Its sample took about 120 µs on real ticks. Most of that time went to evaluations the native stage already makes
for the same endpoint:

| Section of `sample(true)` | µs per tick |
| --- | ---: |
| `published_gear_collapsed` (`_collapsed`) | 25 |
| reach check and published compressions (`_compressions`) | 21 |
| `environment.ground` and the table check | 18 |
| `air_data(s, t)` | 18 |
| everything else | 35 |

## Change

- `nk_kernel.cpp`: `stage_endpoint_facts(s, aux, time_s)` returns
  `[V, terrain height, slope north, slope east, collapsed, c_0 … c_{n-1}]`.
  - The compressions come from `stage_compressions` (NK-5e), with every one of its refusals.
  - V is `air_data(s, t).V`, from the NK-5g `pre_step_air` with the endpoint aux.
  - The terrain is `Environment.ground(north, east)`, from `terrain_sample_validated` on the stage's surface table
    and lake.
  - `collapsed` is `Ground.collapsed`'s comparison of each compression with its posed contact's `max_compression`.
  - Empty refuses: the stage cannot reproduce the reference, the aux has another layout, the time is nonfinite, the
    spatial air sample refuses, or a contact has no numeric travel limit.
- `nk_wheels.hpp`, `nk_kernel.cpp` and `nk_retractable.hpp`:
  - Each wheel contact decodes `max_compression` without new refusals: a missing or non-numeric value stays NaN.
  - The posed in-transit gear sets it to 0, as `RetractableGear.pose` does.
  - No contact law reads it.
- `native_stage.gd`: `endpoint_facts`, bound once per installation (`_facts_bound`).
- `flight_session.gd`:
  - `_on_sim_stepped` marks the tick whose publication carries a natively measured endpoint (`_native_facts_tick`).
  - `published_endpoint_facts(s)` asks the kernel only within that publication, with `s` and `sim.aux` carrying the
    published bits (NK-5f).
  - It refuses with an RC track, a pending weather reset or a derived session class.
  - A contact-history reset or restore withdraws the mark, as it withdraws NK-5f's publication.
- `fixed_wing_adapter.gd`: `sample(true)` takes V, the terrain, the collapse and the contact flags from the answer.
  An empty answer evaluates them as before. Only the compressions' `> 0.00001` flags are read, the same as from the
  previous clear values above the reach bound.

A gearless airframe (`moonrunner-x99`) has no contact table in its stage and keeps the reference sample.

## Evidence

- `app/tests/test_native_endpoint_facts.gd`: 218 checks, none failed.
  - Random endpoints for the whole native fixed-wing fleet, in calm, gusty, turbulent and spatial weather. They lie
    over the field and the lake, from 80 m up to 0.5 m into the ground, with random attitudes and velocities.
  - Retractable gear in transit, with posed contacts.
  - Every answer equals `air_data().V`, `environment.ground()`, `gear_collapsed()` and `gear_compressions()` bit for
    bit; collapses occurred in every set.
  - Only refused spatial air samples refuse: 9–15% of the spatial sets, where the reference V is NaN.
  - Takeoffs, landings, gear cycles and gusty, turbulent and spatial flights answer every natively measured
    publication. On each accepted tick the statistics sample is byte-identical in three ways: built from the answer,
    from NK-5f's publication, and from the session's own evaluations.
  - Refusals: another tick, other state or aux bits, an RC track, a pending weather reset, no observations, the test
    hook off, and a contact-history reset.
- All nineteen installer gates are identical for binary
  `15326727fe35d9cb08e96f68f61369b84240a3cdd049059d44d7d883793e8659`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261126T195227776877Z.json` `d2b0147240d6683fa0d640cec2eb848ccaea772887056cc1fe547f6eed39ba99`
  - `stage_mutant-20261126T195257536428Z.json` `f9ed08ab34d7e98f999b94740be9e72d0f05b8d17c2e648e37d575142a70664c`
  - `trajectory-20261126T195327109506Z.json` `423953d1d7126f2acfd28edfdf51ef96f7518f41291655ea9a139e23d7a7823b`
  - `liquid-stage-20261126T195545580005Z.json` `4af5a12fdfa33c7c13f0c46b67e97809a4cbc6e319157f7a0d01d7961ad83230`
- With the native stage installed, 42 suites pass:
  - all native suites;
  - golden flights, replay integrity and the runway fleet;
  - reset and restore publication;
  - out-of-trim, turbulence, wind, atmosphere and spatial-weather flights;
  - retractable gear (session and ground), flaps and lake;
  - crash cost (fleet), and statistics eligibility, terrain, detector, lifecycle, resets and context;
  - ground accidents (two suites);
  - the electric and Extra runways, trim throttle, servo-interval flight and helicopter weather admission.

  `test_weather_publication` still fails only on the publication fixture renewal pending since NK-5d.

## Gain

Live app, Windows, Forward+, 1080p, airborne. The statistics observer was timed on every accepted tick, alternating the
native facts on and off in 240-tick blocks of the same flight:

| `fixed_wing_adapter._stepped` per tick | Reference | NK-5i |
| --- | ---: | ---: |
| Corsair | 152 µs | 104 µs |
| Stik | 153 µs | 108 µs |

On the paused published endpoint, the sample costs 29 µs and the whole query 3.9 µs (the kernel call 2.0 µs). What
remains of the observer is its detector (`statistics/service.gd` and `detector.gd`, about 55 µs), the accident
observation (5–11 µs) and the gear-deployed check (4–7 µs).

The same attribution located the rest of a flying tick: about 780 µs in all. The native stage itself took
38 µs (four RK stages). The `stepped` observers took about 190 µs. About 500 µs was `Simulation`'s own GDScript around
the callbacks: validation, RK4 plumbing and the endpoint frame.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- Gearless airframes, RC-track sessions and ticks without a natively measured endpoint keep the reference sample.
