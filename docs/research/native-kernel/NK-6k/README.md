# NK-6k — the propeller-strike check's clear answer from the native stage

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6j](../NK-6j/README.md).

## Why

On the ground, `FlightSession._check_prop_strike` ran `HullContact.prop_disc_depth` on every tick with the engine
turning: about 15 µs per tick by real timers. [NK-6e](../NK-6e/README.md)'s altitude bound only skips it in flight.
Near a lake, most of that time is GDScript around a short calculation: lake validation, the bank polygon's bounds and
the covered-terrain sample of the disc's lowest point.

## Change

- `nk_kernel.cpp`: `prepare_prop_strike(hub, axis, radius)` takes the session's propeller disc at installation.
  `stage_prop_strike_clear(s)` computes the disc's lowest point and its flat-datum depth in the reference's order. It
  returns 1 only where the reference must find no strike:
  - the depth is at most 0;
  - the stage's lake is absent, or valid with the lowest point outside the bank bounds expanded by
    `LakeSurface.SAMPLE_EPSILON_M`, and the disc, padded as `_disc_near_lake` pads it, horizontally clear of them.

  Every other case returns -1 for the reference, strikes included.
- `native_stage.gd`: `prop_strike_clear(s, disc, lake)` answers only for the disc and lake dictionaries the
  installation read.
- `flight_session.gd`: `_check_prop_strike` asks after the NK-6e bound, under NK-6j's conditions: the last
  publication's natively measured endpoint, no RC track, this class. Test hook: `native_prop_strike_enabled`.

## Evidence

- `app/tests/test_native_ground_guard.gd`: 66 checks, none failed, for the Corsair, Ugly Stik 60 and Turbo Lumber.
  - 3,000 perturbed endpoints each, a third of them at the lake's bank or over its water, from level to nosed over,
    a quarter with quaternions up to 0.1% off unit length: every native clear answer has a reference depth of at
    most 0. Away from the lake the native stage answers every clear endpoint. Between 319 and 1,035 of the endpoints
    strike, all of them in the reference.
  - Without a lake, 1,000 endpoints each: the native stage answers exactly the clear ones.
  - A disc or lake dictionary other than the installation's is refused.
  - Takeoff rolls, a lake-shore taxi, hard landings and a nose-over at full power fly byte-identical with the shortcuts
    on and off. They decide the same propeller strikes on the same ticks: the shore taxi and the nose-over strike on
    all three aircraft. The native stage answered 1,175 to 1,439 checks of each roll.
- An independent review found no input where the native stage answers while the reference would strike, and no path
  where the installation's disc or lake differs from the session's. A lake present but invalid is refused by
  reading (`stage_config.gd` passes `lake_valid`); `set_lake_context` admits no invalid lake to test it live.
- All nineteen installer gates are identical for binary
  `2e780d742a6349a617e190f74a5e60701d93f96ecaa2a54c025224abdfad779e`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T082642492566Z.json` `23b23a940ec745723a2fa1c4780b892a7a3093694f650d1976a8e9a458a34914`
  - `stage_mutant-20261127T082709398218Z.json` `8fa2f3ce30e98247f0fbc2bce8064a4268f2b11d0e397e12c59af7ea3fbcf6ed`
  - `trajectory-20261127T082736907521Z.json` `5a99014ee57520539e53bde716b741877ac2cf2d7224f182ce43940c88760b70`
  - `legacy-ground-20261127T083122715250Z.json` `b0f3d39589befc072658d0eceeaf7627566fb82565a914862f0dd327cc28da5b`
- With the native stage installed, 199 of 200 affected suites pass:
  - native, crash, gear, retraction, ground, hull, contact, propeller strike, lake and statistics suites;
  - golden flights, replay integrity and policy, and reset publication.

  `test_fixed_gear_brake_input` needs its legacy-engine oracle from the checked runner and fails without it, as in
  [NK-6j](../NK-6j/README.md).

## Gain

Headless, with the native stage installed, on the runway at taxi power:

| Aircraft | `_check_prop_strike` | Whole tick (alternating 120-tick blocks) |
| --- | ---: | ---: |
| Corsair | 16.6–17.1 → 2.3 µs | 364–366 → 341–344 µs |
| Ugly Stik 60 | 16.5–16.8 → 2.3–2.4 µs | 283–308 → 260–287 µs |
| Turbo Lumber | 16.2–16.5 → 2.3–3.3 µs | 306–331 → 291–314 µs |

In flight NK-6e's altitude bound already answers first.
