# NK-6i — quiet hull terminal for glow aircraft

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Extends [NK-6h](../NK-6h/README.md) to glow engines.

## Why

A glow aircraft's contact sample at fraction 0 is `FuelSample.build(GlowFlight.properties(total, line), ...)` over the
main tank and the feed line. Like the liquid sample, it fed `HullContact.terminal_at_properties` on every tick near
the ground, and on an ordinary rolling tick that answers `{ok, no event}`.

## Change

- `nk_kernel.cpp`:
  - The geometry half of NK-6h's quiet check is shared (`terminal_geometry_quiet`).
  - `prepare_glow_terminal(crash_depth, stores, sample_static_ok)` takes the sample's tanks as
    `[capacity, unusable]` pairs, main tank first. Each `prepare_stage` clears it.
  - `stage_glow_terminal_quiet(previous, s, total, line)` applies `FuelSample.build`'s amount checks to
    `{main: total - line, line: line}`. It checks the prepared glow mass (`glow_raw_mass`, NK-6e) with
    `live_hull_properties_error`, then applies the quiet geometry. A configuration without a feed line refuses a
    nonzero line.
- `native_stage.gd`: `_prepare_glow_terminal` reads the tanks from `GlowFlight.mass_context` of the installed store,
  and checks `FuelSample.build` at both ends of each store's range.
- `flight_session.gd`: `_native_terminal_quiet` also asks for glow, with the start store's total and line fuel. The
  sampler exists only when that store passed `GlowFlight.mass_context`, which includes `properties(total, line).ok`.

## Evidence

- `app/tests/test_native_liquid_terminal.gd`: 24 checks, none failed. It adds the Stik glow 61FX and FS64V to the
  liquid aircraft.
  - The tick pairs use random total and line fuel, including out-of-range and NaN values.
  - Every glow quiet answer (2,410 and 2,366) is the reference's `{ok, no event}`.
  - Takeoff rolls, hard landings and nose-overs fly byte-identical with the answer on and off.
- All nineteen installer gates are identical for binary
  `b0a8687f2cfd8ae825990d90e20c03c31a1026fc0bb140d077bf9864a776243a`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T071235399411Z.json` `aa9f7f2de26876e538837138645a64e61de683b4abbc0b9a2f7e91530ad3ce93`
  - `stage_mutant-20261127T071301383228Z.json` `4696a5079f349f25efb7e89c6dfcc4655d07432f36e8e6ccb0914e053ca52768`
  - `trajectory-20261127T071327641655Z.json` `663f0c7699dc67644e76994ed2693d5b8ead53ae0f84d29c794955b660533f03`
  - `glow-stage-20261127T071547699201Z.json` `4fca0b275085d018680959c373d9f3cfc6edb56086a91bbbfc889ccf7c64feef`
  - `liquid-stage-20261127T071527839387Z.json` `56056734093b7e349d720ed38068c8445257dbdc8d61859df374243006adfa73`
- With the native stage installed, 144 affected suites pass:
  - native, crash, hull, glow, liquid, fuel and contact suites;
  - ground, lake collision and strike suites;
  - golden flights, replay integrity and policy, and reset publication.

## Gain

Headless, alternating 120-tick blocks with the answer on and off (whole tick), on the runway:

| Aircraft | Off | On |
| --- | ---: | ---: |
| Stik glow 61FX | 561 µs | 461 µs |
| Stik glow FS64V | 556 µs | 454 µs |

Airborne the hull is out of reach: no change.
