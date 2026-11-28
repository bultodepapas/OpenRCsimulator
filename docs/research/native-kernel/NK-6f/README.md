# NK-6f — native hull-scrape diagnostics

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6e](../NK-6e/README.md).

## Why

While any hull point touches the ground (a ground loop, a nose-over, a belly slide), the crash director observes the
hull scrape on every accepted tick for its scrape audio. `FlightSession.hull_scrape_observation` then re-evaluates
`HullContact.loads_at_properties` at the endpoint for its diagnostics rows. For every touching point that computes the
effective mass in 26 directions in GDScript. A live Windows Corsair resting on its nose measured 693 µs per
observation: 531 µs in `loads_at_properties` for one touching point, 110 µs in `mass_properties()`, 41 µs in the
surface sample. With the other contact observers, ticks reached 3–4 ms and catch-up held the app at 19 FPS.

## Change

- `nk_hull.hpp`: `hull_loads` and `hull_loads_at_properties` take an optional `HullDiagnostics` collector. It records
  each flat-branch row's own `f_up`, `f_n`, `f_e`, `vn` and `ve` with the point index. It also flags a lake-covered
  sample, where the reference's structured diagnostics are unavailable. Ordinary calls pass none and compute exactly
  as before.
- `nk_kernel.cpp`: `stage_hull_scrape_rows(s, properties)` evaluates the installed stage's hull. Empty `properties`
  selects the prepared hull (`HullContact.loads`). `[ok, mass, cg x3, inertia x6, inverse x6]` selects the
  geometry-only live hull (`loads_at_properties`). It returns `[1, n, n x (index, f_up, f_n, f_e, vn, ve)]`. It
  returns `[0]` for a lake-covered sample, a refused live sample, or a hull of the other kind. `tick_stats` counts
  calls and answers.
- `flight_session.gd`: `_native_hull_scrape_diagnostics` asks only under `published_endpoint_facts`' conditions:
  - this publication's natively measured endpoint, with the state and aux bits the contact observer measured;
  - no RC track and no pending weather reset;
  - this session class.

  It builds the reference's row dictionaries in the same key order, with `point_ned` from
  `HullContact._point_ned` and `friction_power_w` as the reference writes it. `_packed_mass_properties` packs the
  fields `EffectiveMass.validate_properties` reads and refuses its type failures. The stage checks the values.
  Otherwise the reference runs, and it also answers every refusal. Test hook: `native_hull_rows_enabled`.
- `native_stage.gd`: `hull_scrape_rows` and its binding check.

`mass_properties()` and the surface sample stay in GDScript.

## Evidence

- `app/tests/test_native_hull_rows.gd`: 26 checks, none failed. Aircraft: Corsair (liquid, live hull), Ugly Stik 60
  (prepared hull), Stik glow 61FX (glow, live hull) and Turbo Lumber (pack, prepared hull).
  - Per aircraft, 3,000 endpoint states touch the field, and one in four lies inside the lake's bank bounds, from
    0.5 m above to 2.5 m below the datum. Attitudes are random, with velocities to ±12 m/s and rates to ±3 rad/s.
  - The finite-fuel aircraft also use perturbed mass properties in one sample in six: not ok, NaN mass, a mismatched
    inverse, a negative inertia, a negative mass.
  - Every native answer equals the reference's rows bit for bit, about 80,000 rows in all. The stage refused wherever
    the reference refused or its diagnostics were unavailable: 426–455 lake-covered samples per aircraft. It refused
    1–2 conservative samples near the lake.
  - Flights tipped onto the nose (full power, stick forward) publish identical hull-scrape observations on every tick
    with and without the native rows, and the stage answered every observation.
  - Refusals: the hook off, outside the published endpoint, a derived session class.
- All nineteen installer gates are identical for binary
  `2d0bac70a8dec7aded7dfc07ef37978ff9dc0d1c6c71990a10be86990621bfc5`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T041937645517Z.json` `6cf0a0bbe60539f4e4308c87f79b974c4a82cb5d607f06bd3f738c0dc7ea9a39`
  - `stage_mutant-20261127T042012315140Z.json` `850a003200972b9a07229674009145b7aa44e2deecebdcba8530f868bde5c516`
  - `trajectory-20261127T042044777720Z.json` `6f96156cdd460edb911ae20032371469be9f7866f19e045e677f842da8da4200`
  - `liquid-stage-20261127T042313801679Z.json` `a45dccdb624fc15756416c053635cc4fcf6b4f2ebdfe8390909128c731b08921`
  - `glow-stage-20261127T042336786259Z.json` `fb161bc6ce7de545d92ba920863253adc40e800fee26c58c4654cb302d4cc436`

## Gain

Headless, the same nose-over flights, per observation while the hull touches:

| Aircraft | Reference | NK-6f |
| --- | ---: | ---: |
| Corsair (live hull) | 502 µs | 154 µs |
| Ugly Stik 60 (prepared hull) | 80 µs | 70 µs |
| Turbo Lumber (prepared hull) | 81 µs | 76 µs |

The live hull saves its effective-mass work. A prepared hull already reads stored coefficients.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- Near the lake the native stage can refuse where the reference's diagnostics are still available. It samples
  coverage for every point, while the reference skips points above the datum. The reference then answers.
