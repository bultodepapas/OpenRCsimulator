# NK-6t — the liquid contact sampler's stores in the native kernel, and four more tick facts

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick main-thread cost](../../../plans/optimization-priorities.md).

## Why

A headless native tick on the Corsair and the P-51 cost 140–142 µs, measured by `Simulation.step` probes and
function wrappers. Three pieces of GDScript glue stood out:
- The liquid contact-mass sampler took 12.7 µs every tick, airborne included. It validated both fuel stores in
  GDScript and built a closure that only a contact ever calls.
- The session's layout getters (`wheel_index`, `liquid_fuel_is_active`, `flap_aux_index` and the substep preview's
  support) re-derived aircraft-static answers on each of their many calls per tick. `_liquid_index()` alone cost
  3.4 µs per call.
- The tick context's `_deflections` and `_should_capture_substep_context` (8 and 7 µs) mostly paid for those
  getters.

## Change

- `nk_kernel.cpp` `stage_liquid_store_valid(values, index)` answers `LiquidFlight.valid` (not a trial) from the
  prepared liquid stage; `NativeStage.liquid_store_valid` binds it.
- `FlightSession._contact_mass_sampler` uses it for a liquid aircraft inside the guarded tick, as NK-6e does for
  glow. When both stores are valid, the sampler is built through `LiquidFlight.contact_sampler` on its first call.
  It reads only this tick's clock and the frozen installation. The scenery, lake and hull-terminal callers all call
  it within the same collision step, so it answers as the eager sampler does. Hook:
  `FlightSession.native_liquid_store_enabled`.
- Four more NK-2a tick facts:
  - `wheel_index` and the substep preview's base also read the shaft integrator, which changes only in a start
    transaction between ticks;
  - `liquid_fuel_is_active` and `flap_aux_index` depend only on the aircraft.
  Facts are armed by the guarded pre-step and dropped on publication, fault, pause and aircraft commit, as before.

## Evidence

- `app/tests/test_native_liquid_store.gd` (4 checks):
  - the native validity equals `LiquidFlight.valid` on 6,000 stores, more than 1,000 of them invalid (NaN and
    infinities, negative or beyond usable capacity, latch 0.5 and −0, an empty store with the latch set, wrong sizes);
  - the lazy sampler answers exactly as `LiquidFlight.contact_sampler` for 200 fractions, out-of-range and NaN
    included;
  - two native P-51 sessions, one building the sampler through the reference, keep identical checkpoints from an
    airborne start, power off and nose down, into ground contact.
- 52 simulation suites pass on the installed binary, including checkpoint, replay, flight log, fuel, gear, flaps,
  hull, lake, wheel, session-guard, tick-fact, P-51 and every native session and stage suite.
- All nineteen installer gates pass for binary `cf3f9d612d638fac595a98a5b8faa410e6db8867e4f2d7373bf9d08cc2273de1`;
  the literal check covers 245 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T051733917802Z.json` `45d8a8a760a077b7fbb5c75d4b352e967861e2de8de1864d1643f099f41f0879`
  - `stage_mutant-20261128T051759355753Z.json` `cf7ddf750f2bea87552c6a733c8e99cb287a70a406d1702e3d99b0657882398f`
  - `trajectory-20261128T051825128106Z.json` `ce397531acfac8bfb94628fab466a14e72a21f4d1aecd25fc047d7b7afb75aef`
  - `legacy-ground-20261128T052159121670Z.json` `5a727d39db557b3654a1809ce1ed42e3ee3ddc1effb0ea57550c57552d99ac98`

## Gain

Headless `sim.step` medians of 4,000 airborne ticks, six alternating rounds of the HEAD sources against these, on
the same binary:

| Aircraft | HEAD | NK-6t |
| --- | --- | --- |
| Corsair | 140–141 µs | 133–134 µs |
| P-51 | 141–142 µs | 135–137 µs |
| .61 Stik glow | 131–133 µs | 132–136 µs (within noise) |

## Scope

Windows x86_64 only. The two edited sources are mirrored, so solver identities change: reinstall the native stage and
requalify where it is installed.
