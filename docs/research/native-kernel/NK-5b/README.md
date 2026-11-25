# NK-5b — the substep preview publishes its source-off shaft rate

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5a](../NK-5a/README.md).

## Why

After NK-5a, a headless split of a flying Corsair tick on the native backend (current source, repeated calls at one
accepted state, calm air at about 30 m) showed two GDScript model callbacks that run every tick even with the native
stage installed:

| Per tick | µs |
| --- | ---: |
| `substeps_joint` (`_substeps_joint`) | 78 |
| of which `LiquidFlight.properties(…, true)` | 27 |
| of which `_coupled_response(…, false, preview)` | 28 |
| `post_tick_joint` (contact resolution with the lake) | 54–60 |
| configuration guard | 52–71 |

For a finite-liquid gas engine (P-51, Corsair), `_substeps_with_context` refines the tick near the combustion cutoff.
To do so it rebuilt the trial mass properties and a whole coupled shaft response with the source forced off, from the
substep preview that the tick's first stage had just captured. The stage already holds every input of that response:
the trial properties, the CG pre-reaction wrench, the propeller and datum air, throttle, density and charge.

## Change

- The stage publishes the rate it can compute from the same values. In `liquid_fuel_flight.gd` `evaluate()` the
  reference calls `_coupled_response(body, base, at, live, false, preview)` once on the captured preview evaluation and
  adds `source_off_rpm_rate` to `stage_context` when the response is usable and finite. The native
  `liquid_stage_finish` calls `liquid_gas_coupled_stage` with the source off on the same captured wrench and air and
  publishes the same key, value and key order (`nk_stage.hpp` `StageResult`, `nk_kernel.cpp` `stage()`).
- `_substeps_with_context` uses a finite published rate while finite liquid fuel is active. Without it (non-liquid
  coupled engines, an unusable response, an old library, a context from a caller) the legacy computation runs
  unchanged. Unusable responses and non-finite rates already requested an over-cap count, so the count is identical.
- NK-5a follow-ups: `native_stage.gd` checks `has_method("stage_wing_wake")` once per installation, and the native
  method is no longer `const` with a `mutable` scratch vector.
- `liquid_stage_oracle.gd` byte-compares the reference and native stage dictionaries, now including the key, and
  requires the forced running preview to publish it.

## Exactness

The published rate is the same expression on the same inputs. The stage captures its preview only for the committed
body, continuous values and time (`_should_capture_substep_context`), and the kernel passes exactly that evaluation to
`substeps_joint` within the same tick. `liquid_oracle` already verifies the native `liquid_gas_coupled_stage` against
`_coupled_response` bit for bit with the source on and off.

The installed Windows binary `25f407854d4ec96cad79b9be9a6e753353375077d8dc670903319fa3f38aa983` was qualified against
the exact bytes of the working tree it was installed into:

| Gate | Result |
| --- | --- |
| `stage_oracle` (12,000 states) | pass, 140,664 identical |
| `negative_control` (mutant build) | fails as required (28,315 differences) |
| `trajectory` (960 ticks per case) | pass, 21,771 identical |
| `liquid` (component gas and turbine laws, source on and off) | pass, 15,572 identical |
| `liquid_stage` (P-51, Corsair, Avanti; seven weathers; runway, trim and exhaustion trajectories) | pass, 64,136 identical, with the key byte-compared and required on the forced running preview |
| the other fourteen component and family gates | pass, every comparison identical |

`app/tests/test_native_substep_preview.gd` runs the P-51 and the Corsair on both backends (97/97 with the native
library installed; the reference half alone is 55/55). Each run covers 360 airborne and idle ticks, 240 spatial-weather
ticks with explicit propeller air, a 720-tick engine-off ground rundown and six engine-off starts between 1.000001 and
5 RPM. Every one of 1,326 preview ticks per aircraft published the key. Each published rate equals the legacy
response's bytes, and each count equals the legacy count. The four cutoff starts that refine are integrated by the real
kernel tick with exactly four stage evaluations per legacy substep.

Reference regressions are unchanged: `test_shaft_coupled` 101, `test_shaft_refinement` 3, `test_fuel_event_boundaries`
46, `test_fuel_live_mass` 13, `test_liquid_fuel` 34, `test_golden` (4 golden flights), `test_p51_handling` 19,
`test_p51_ground` 14, `test_replay_integrity` 153, `test_turbine_continuous` 46. Native production tests after
installation: `test_native_stage` 104, `test_native_session` 343, `test_native_replay` 209,
`test_native_wake_admission` 21.

Accepted gate results (in the tool root, not in Git): `stage-20261125T160350976889Z.json`
`465485353227a55c32248089aa36ed8d1c2fe8eb6edeb9e35abe0792b319a7d4`, `stage_mutant-20261125T160428346859Z.json`
`457a56852594887c540a040b9ea584e15a994403d967682b098590154d85f454`, `trajectory-20261125T160505896106Z.json`
`ad8c0445a5bb07a4ee6de8d00e19815332ac543481e488ddaf20e3c3216cd671`, `liquid-20261125T160604315703Z.json`
`d9708b2affbf2348a0e4d4aacab2863a9a5832bd2cc99d506a71604b54446de5`, `liquid-stage-20261125T160745013234Z.json`
`536e95718e5fd413a7e9db8381ae02a778af63659d5d380cef413eb3b6165f42`, `weather-stage-20261125T160908743395Z.json`
`0848e95d6fae5bf97f6c5c13b910dcd6eeab686059e50220d0895e77dfd49559`.

## Gain

With the same headless protocol on the native backend, `substeps_joint` fell from 78 µs to 14–25 µs per tick on the
Corsair and the P-51. The removed work, `LiquidFlight.properties` and the source-off `_coupled_response` (27–38 µs
each in two runs), is about 55–65 µs per tick for every finite-liquid gas aircraft. Whole-tick times on this shared
workstation varied between 470 and 660 µs from run to run, so they are not used as evidence. On the reference backend,
the stage now evaluates the source-off response once per captured preview instead of `_substeps_joint`, which also
drops the second `LiquidFlight.properties` call.

## Limits and next steps

- Windows only was built and installed locally. CI's `native-kernel-linux`, `native-kernel-windows` and
  `native-kernel-macos` jobs requalify each platform on push.
- The single-tick contract: `stage_context` is opaque, k1-only and owned by the tick that captured it, like its
  `air` and `pre_reaction_loads`. A caller that keeps or edits a context across ticks would also carry a stale rate.
- On the reference backend, another stage evaluation at exactly the committed body, values and time inside one tick
  (for example the first piece of a refined tick) evaluates the source-off response again. It is not consumed there.
- Turbine and non-liquid coupled engines keep the legacy computation.
- The AI-companion solver identity changes again; re-pin with `tools/companions/rebind.py --accept` after the commit.
- Remaining GDScript per tick on these aircraft: contact resolution with the lake (`post_tick_joint`, about 55 µs), the
  configuration guard (55–70 µs) and the session's endpoint checks (`gear_collapsed` 26 µs, `_check_prop_strike` 15 µs).
