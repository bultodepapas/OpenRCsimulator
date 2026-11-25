# NK-5a — native wing wake in the session pre-step

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

A flying Corsair tick on the native backend still spends most of its time in GDScript around the native stage
([per-tick attribution](../../god-test/2026-11-24-flight-tick-cost.md#first-attribution-of-a-flying-tick)). Timed
without the profiler on a paused flight at about 50 m (headless, current source), one tick split as follows:

| Part of one tick | µs |
| --- | ---: |
| Whole tick, every `stepped` observer connected | 1,146 |
| Tick with only the session's own `stepped` handler | 728 |
| `pre_tick` (`_kernel_pre_step`): configuration guard, `_pre_step`, native tick context | 297 |
| of which the native configuration guard (`configuration_guard_matches`) | 92 |
| of which `Aero.wing_wake_velocity` for the tail downwash lag in `_pre_step` | 72 |
| of which `Ground.anchor_step` | 33 |
| four native stage evaluations | 83 |
| the session's `stepped` handler (`_observe_contact_tick`: 51, of which wheel compressions 44) | 108 |

`Aero.wing_wake_velocity` evaluates the wing strips in GDScript every tick for every aircraft with a tail downwash
lag. The kernel already contains the same function (`nk::wing_lift_coefficient_with` with `nk::ge_factors`), which
the component oracle verifies bit for bit (`aero_component` case 6). It is pure evaluation inside an existing model
callback (`pre_tick`), so it fits the [native policy](../../../DECISIONS.md) without moving the tick transaction.

## Change

- `nk_kernel.cpp` binds `stage_wing_wake(s, air, deflections, ground_up)`. It builds `nk::Air` from the caller's own
  `air_data(s)` values and runs `ge_factors` and `wing_lift_coefficient_with` on the prepared stage's `AeroModel`
  (decoded by the same `decode_aero`). Unusable input returns NaN. A scratch vector avoids an allocation per tick.
- `native_stage.gd` `wing_wake()` packs the values for any installed fixed-wing family.
- `flight_session.gd` `_pre_step` uses it only while `_kernel_pre_step` has just passed the configuration guard
  (`_native_wake_admitted`). Otherwise, or on a NaN, the reference `Aero.wing_wake_velocity` runs with the same
  arguments, so a reference session, a direct `_pre_step` call or a NaN result is unchanged.
- `stage_oracle.gd` compares the new method with `Aero.wing_wake_velocity` on every random stage state.

## Exactness

The installed Windows binary `edb96b304b02839cecb112bc59c722b75c9ee98247648a638b97aa731478c942` was qualified against the exact bytes of the working tree it was installed into (line endings included: the installer binds every loaded script by hash). All installer gates:

| Gate | Result |
| --- | --- |
| `stage_oracle` (12,000 states; includes `stage_wing_wake` 12,000/12,000) | pass, 140,664 identical |
| `negative_control` (mutant build) | fails as required (28,315 differences) |
| `trajectory` (trim, runway, manoeuvre, take-off, lake; 960 ticks each) | pass, fingerprints equal, no divergence |
| `liquid_stage` (P-51, Corsair, Avanti trajectories) | pass, 64,136 identical |
| the other fifteen component and family gates | pass, every comparison identical |

Coverage: `stage_oracle` compares on the Stik with datum `Air.compute` air; `trajectory` flies the Stik's five cases;
`liquid_stage` flies the P-51, Corsair and Avanti (flaps included) through the guarded pre-step; `weather_stage`
includes spatial weather. A new `app/tests/test_native_wake_admission.gd` flies the Corsair and the Stik for 360 ticks
each on the native backend and requires the guarded native `_kernel_pre_step` to return the same bytes as the
reference `_pre_step` on every tick, the native wake to be evaluated rather than its NaN fallback, the admission flag
to be clear outside the guarded call, and a reference session to ignore it (21/21).

After installation the production tests exercise their native branches: `test_native_stage` 104/104,
`test_native_session` 343/343, `test_native_replay` 209/209. The AI-companion solver identity changes
(`7e404f01` → `24d14b3d`); all nine qualification tapes replay identically (2,881 rows each).

Accepted gate results (in the tool root, not in Git): `stage-20261125T145632457740Z.json`
`e302bb3ca7d75d75a80de07fadce1ad5153558972e3ded7350b6699de828a46e`, `stage_mutant-20261125T145701326358Z.json`
`dcba2a492f158d8d0fac9d99cabe1312d9c3b0c3ea9c696595591a18710e9216`, `trajectory-20261125T145730241447Z.json`
`b21bd3f7ed3e88596f13be18c2e48129857388c1d98944d5a58163db70f48c91`, `liquid-stage-20261125T145943037437Z.json`
`fb6eaaf9d1234dde3828d1dce7b3e60e54b412e282375fb4d1706a712c531feb`, `weather-stage-20261125T150058415458Z.json`
`10f7362818b7a4a5394a9379ddc713848c43db676cda2114e8fb9ee4f4006517`.

## Gain

Same Corsair flight protocol, current source with and without NK-5a: the tick core with only the session's handler
fell from 728 to 665 µs and `pre_tick` from 297 to 227 µs, consistent with the 72 µs the replaced GDScript call cost.
The whole tick with every observer also changed (1,146 → 882 µs), but most of that difference is flight-state and
observer variation, not this change. Other fixed-wing aircraft with a tail downwash lag take the same path; only the
Corsair's gain was measured. The reference backend is unchanged.

## Limits and next steps

- Windows only was built and installed locally. CI's `native-kernel-linux`, `native-kernel-windows` and
  `native-kernel-macos` jobs requalify each platform on push. Local Linux and macOS installs stay valid for their
  own frozen snapshots and fall back to the reference with this source until rebuilt.
- After committing the `app/sim` change, re-pin the companions: `python tools/companions/rebind.py --accept`.
- Independent review (no bug found) suggests, for the next requalification: `has_method("stage_wing_wake")` in
  `native_stage.gd` as defence in depth beyond the mirrored-source hash binding, and dropping `const`/`mutable` from
  `stage_wing_wake`. The GDScript side still builds two small packed arrays per tick.
- Remaining native candidates in the same tick: the configuration guard's per-tick walk of about 560 watched model
  leaves (92 µs), the observation's wheel compressions (44 µs, already ported as `nk_wheels`) and
  `Ground.anchor_step` (33 µs).
