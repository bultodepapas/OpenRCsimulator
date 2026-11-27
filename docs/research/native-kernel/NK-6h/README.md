# NK-6h — quiet hull terminal for liquid aircraft

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6g](../NK-6g/README.md).

## Why

On every accepted tick near the ground, a liquid-fuel aircraft's contact resolution grades the hull terminal:
`HullContact.terminal_at_properties(previous, s, live hull, mass_at_fraction.call(0.0))`. Measured headless on the
Corsair rolling on the runway, the contact sample at fraction 0 (`FuelSample.build` of `Liquid.properties`) cost
36 µs and the terminal 22 µs. On an ordinary rolling tick the answer is `{ok, no event}`: no hull point newly
penetrates, none lies past the crash depth, and none meets the lake.

## Change

- `nk_kernel.cpp`:
  - `prepare_liquid_terminal(crash_depth, sample_static_ok)` runs at installation, for a liquid stage with a
    geometry-only hull. Each `prepare_stage` clears it.
  - `stage_liquid_terminal_quiet(previous, s, usable_before)` returns 1 only where the reference must answer
    `{ok, no event}`:
    - The start store's properties are valid. The stage computes them as its own live mass does
      (`liquid_trial_onboard_mass`, `liquid_inventory_usable_mass`, `liquid_mass_evaluate`), exactly as the contact
      sampler's `Liquid.properties` of the clamped onboard store. It checks them with `live_hull_properties_error`
      (`EffectiveMass.validate_properties`).
    - Both states pass the terminal's input and attitude checks.
    - Every hull point is above ground, already in contact before the tick, or past the hull's reach, and no point is
      lake-covered.
  - It returns 0 everywhere else, and the reference evaluates. `tick_stats` counts calls and quiet answers.
- `native_stage.gd`:
  - It passes `HullContact.crash_depth` of the session's hull.
  - `_liquid_sample_static_ok` passes whether `FuelSample.build` accepts the installation's tanks at both ends of the
    amount range the contact sampler clamps to. Its other checks read only the properties, tick and time.
- `flight_session.gd`: `_resolve_mass_contact_step` keeps the start store for `_native_terminal_quiet`. That function
  asks only inside the tick whose guarded pre-step installed the native context, for this class. A quiet answer skips
  the sample and the terminal. Test hook: `native_terminal_quiet_enabled`.

## Evidence

- `app/tests/test_native_liquid_terminal.gd`: 12 checks, none failed, for the Corsair and the P-51D.
  - Per aircraft, 4,000 tick pairs on the field and over the lake, with random start stores including invalid and
    NaN ones. One in five pairs is tilted or lowered so hull points touch, sink or newly penetrate. Attitudes are
    normalized in float64.
  - Every quiet answer (2,320 and 2,336) is the reference's `{ok, no event}`. About 620 such ticks are left to the
    reference: new penetrations it grades below the crash threshold, and lake-covered points.
  - Full-power takeoff rolls, a hard landing and a nose-over fly byte-identical with the answer on and off. Rolling,
    the stage answered 1,711 and 1,925 of 2,000 ticks.
- All nineteen installer gates are identical for binary
  `c3f9a38eec1ea60afcb50f06b0b09e9c55b8f1116620de94cf716c83ca32b5e5`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T065217205228Z.json` `e760f2e5de8f8db0b2858c88fbbc315ba549a41a32e6a20d4990a0294b139c70`
  - `stage_mutant-20261127T065243093951Z.json` `915b2067b93b013983c4c96c6413f1b629d84b4305728eedc8b22cb2e9764123`
  - `trajectory-20261127T065309343495Z.json` `51956fd5c54f417cf9aea22c76e24f89d2fb494d99b10a047a4a348d0588b973`
  - `liquid-stage-20261127T065509560863Z.json` `af47342636bad1d9063ffb99004d59b51adc39af3de3975830251c65d6ba894d`
  - `legacy-ground-20261127T065649846179Z.json` `779166c1dee4d879ffc8635060d49f8af8b4b853dd7a0de3213b656c1fc72cee`
- With the native stage installed, 116 affected suites pass:
  - native, crash, hull, liquid, fuel and contact suites;
  - ground, lake collision and strike suites;
  - golden flights, replay integrity and policy, and reset publication.

## Gain

Headless, alternating 120-tick blocks of the same flight with the answer on and off (whole tick):

| Aircraft | On the runway | Airborne |
| --- | ---: | ---: |
| Corsair | 469 → 392 µs | 325 → 331 µs |
| P-51D | 460 → 377 µs | 311 → 303 µs |

Airborne the hull is out of reach and the check already returned early.

## Limits

- Liquid fuel only; glow keeps its terminal in GDScript.
- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
