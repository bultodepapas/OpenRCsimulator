# NK-6e — native glow store checks and the session's reach bounds

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6d](../NK-6d/README.md).

## Why

A headless profile of a glow flight after NK-6d (engine profiler, `-d --profiling`) ranked the remaining GDScript per
tick. The post-step contact filter's mass sampler (`_contact_mass_sampler`) cost about 110 µs: two
`GlowFlight.mass_context` calls. Each rebuilds the lifecycle state (`unpack`, `Life._state_error`), validates the
store (`valid`) and evaluates the fuel mass (`MassInventory.evaluate_reference`). The sampler only uses those contexts
to refuse an invalid store, and their tank list only when a contact samples mass. The auxiliary projection
(`_coupled_aux`) ran `valid` a third time.

Two smaller per-tick costs reach every aircraft:

- `_contact_probe_reach` re-measured the gear and propeller probes for the native contact proof (about 16 µs).
- `_check_prop_strike` evaluated the propeller disc against the field and the lake even at altitude (about 27 µs).

## Change

- `nk_kernel.cpp`:
  - `prepare_glow_validity(bounds)` takes the installation's bounds once from the session (`native_stage.gd`
    `_glow_validity_bounds`); the configuration guard refuses a tick after any later change.
  - `stage_glow_mass_check(values, with_mass)` ports `GlowFlight.valid`. That covers `unpack`'s checks and
    `Life._state_error(state, true)`, then `valid`'s own bounds, with the residue round-off and the source modes.
  - With `with_mass`, it adds `mass_context`'s store bounds and `properties(total, line).ok` from the prepared glow
    mass (`glow_raw_mass`).
  - It returns 1, 0, or -1 to refuse. The literal table adds `2.8`.
- `flight_session.gd`:
  - `_native_glow_mass_check` answers only inside the tick whose guarded pre-step installed the native context,
    and only for this class. It has a hook (`native_glow_mass_enabled`).
  - `_contact_mass_sampler` uses it for both stores. The contact sample builds the start store's context on its first
    call; the context is pure, so its values are the same.
  - `_coupled_aux` uses it for `valid`.
  - `_contact_probe_reach` keeps its answer for the same posed gear and propeller disc, by identity.
    `current_landing_gear()` keeps its dictionary until the gear moves, and the native flights it serves refuse
    in-place edits.
  - `_prop_disc_clear(s)` lets `_check_prop_strike` stop only where `HullContact.prop_disc_depth` must answer a depth
    of zero or less. Every disc point lies within |hub| + radius of the origin, and the rotation rows are bounded by
    1 + 4|q|², as `_disc_near_lake` bounds them. Above that height the flat datum is out of reach. The lake decides
    only within its bank bounds, which the disc's horizontal reach must miss. An invalid lake or a nonfinite state keeps
    the full evaluation.
  - Test hooks: `probe_reach_cache_enabled`, `prop_clear_bound_enabled`.

## Evidence

- `app/tests/test_native_glow_mass.gd`: 40 checks, none failed, for the four native glow aircraft.
  - 12,000 stores perturbed onto, inside and past every bound `valid` and `mass_context` check. The bounds cover
    rpm, fuel against capacity and reserve, temperature, servo and opening, transport, phase, the running flag,
    reason codes, counters, the accumulator, mixture, line liquid, source modes and NaN. Every native answer equals
    the reference; each check came out true about 900 times and false about 2,100 times per aircraft.
  - Takeoffs, landings and fuel exhaustion fly byte-identical with and without the native checks, which answered on
    every tick. On the ground the hull terminal check calls the contact sample, which builds its context there.
  - Refusals: outside the guarded tick, the hook off, a derived session class.
- `app/tests/test_session_reach_bounds.gd`: 24 checks, none failed, for the Corsair, Stik 60, Stik glow 61FX and
  P-51D.
  - Of 4,000 random states per aircraft, every one the bound clears has a disc depth of zero or less. The states lie
    over the field and the lake from 0.5 m below the datum to 12 m up, at random attitudes, including unnormalized
    quaternions.
  - The cached probe reach equals the recomputed one through gear cycles.
  - Takeoffs and landings fly byte-identical with both on and both off.
- All nineteen installer gates are identical for binary
  `bd538729a1369fdc582a5377a57061771180304a2206eb4c885b8394e84b7c02`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T012123842411Z.json` `76358920e2f8d2e051159f70d562b301109dd47768b408f366659d23d2d3ec4f`
  - `stage_mutant-20261127T012153277561Z.json` `a08b230ba8c8bc32e6caf9d286306705a63e8de64fdefc4cc8ed20ca06328e32`
  - `trajectory-20261127T012223648543Z.json` `db4affe014526ef8898a67dbb6692f54485d0cfbd9461131f8a9a71251562d30`
  - `glow-stage-20261127T012500321660Z.json` `f15d22f7e8a5e67805fdd42a6b9a2ba3030b173c0f5d3984b764f53c0ec7c1db`
- With the native stage installed, 131 suites pass:
  - all native suites and all glow, nitro and fuel suites;
  - every suite that reads the propeller strike, propeller disc, hull contact or contact sampler (74 suites);
  - golden flights, replay integrity and policy, the runway fleet, reset and restore publication;
  - weather, lake and lake collision, crash cost, ground accidents (two suites), retractable gear, the Extra runway,
    `Simulation`, statistics and the electric battery session.

  `test_weather_publication` still fails only on the publication fixture renewal pending since NK-5d.

## Gain

Headless, alternating 120-tick blocks of the same flight with the native checks and both bounds on and off. The time
covers the whole tick: the session's input and `Simulation._physics_process`.

| Aircraft | Before | NK-6e |
| --- | ---: | ---: |
| Stik glow 61FX, airborne | 461 µs | 350 µs |
| Stik glow 61FX, from the runway | 534 µs | 454 µs |
| Stik glow FS64V, airborne | 446 µs | 334 µs |
| Stik glow FS64V, engine stopped on the runway | 246 µs | 225 µs |
| Corsair, airborne | 315 µs | 297 µs |
| Corsair, from the runway | 464 µs | 413 µs |
| Ugly Stik 60, airborne | 205 µs | 179 µs |
| Turbo Lumber (pack), airborne | 248 µs | 219 µs |

The glow saves about 110 µs per tick in flight. The reach bounds save 11–51 µs on every aircraft.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The liquid-fuel contact sampler (`LiquidFlight.contact_sampler`) keeps its GDScript validity checks.
