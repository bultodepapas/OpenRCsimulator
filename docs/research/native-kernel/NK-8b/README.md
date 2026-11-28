# NK-8b — render terrain samples from the prepared native ground

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

After [NK-8a](../NK-8a/README.md), the aircraft shadow in daylight still cost 55–66 µs per frame in the live app.
The cost was in `Shadow.receiving_ground`'s seven terrain samples. Each sample went through `main.gd`
`_ground_height` to the GDScript `GroundTerrain.sample`, which validates the surface table behind a mutex and
then evaluates the microrelief. The same helper also serves the chase camera's ground clearance, the crash
director's focus and the tailhook pose.

## Change

- `nk_kernel.cpp` `stage_terrain_sample(north, east, surfaces)` samples the installed fixed-wing stage's prepared
  ground, with no lake, as `GroundTerrain.sample` does. It answers only when `surfaces` holds the prepared table's
  exact bytes; an empty table, GDScript's flat fixture, is left to GDScript.
- `NativeStage.render_terrain_sample` binds it.
- `FlightSession.render_terrain_sample(north, east)` returns that sample, or `GroundTerrain.sample(north, east,
  ground_surfaces)` itself. Hook: `FlightSession.native_render_terrain_enabled`.
- `main.gd` `_ground_height` calls the session's sample when the session has one; helicopter and airship sessions
  keep `GroundTerrain.sample`. The RC-track composition is unchanged. The owner of `main.gd` agreed to the change,
  and renews its companion pin (`behavior-manifest.json`) together with their own pending pin.

## Evidence

- `app/tests/test_native_render_terrain.gd` (5 checks):
  - 20,000 points on a native Corsair session with the production field equal `GroundTerrain.sample` bit for bit,
    all answered natively. The points cover the field, cell and rectangle edges, points 5 km away, −0 and
    non-finite coordinates.
  - After the surfaces are set again, the stage is prepared again and the samples still equal.
  - The hook off, and a session without a field (the flat fixture), sample in GDScript.
- 121 of 125 suites pass on the installed binary: every `test_native_*` script, the shadow suites and every suite
  that loads `main.gd` or reaches `_ground_height` (camera clearance, crash director, tailhook). Two exited cleanly
  but were flagged by the local runner's pattern: helicopter save codes and a dummy-renderer material warning.
  Two companion suites stop on the expected stale pins (main.gd's source pin, and the solver hash that the NK
  batches' simulation sources already moved); both are renewed at push by `tools/companions/rebind.py --accept`.
- All nineteen installer gates pass for binary `f37f56755544e20a8ffff9076751395186299f5887c086b7af83bcbaff2cc6da`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T080331848038Z.json` `7f26fb48e83f2b6bba82b8b2f2cf1bd709d9b7657215d1d70b7e1d50e392490a`
  - `stage_mutant-20261128T080357715879Z.json` `41366bf0ee1a67689dc80deb7d7c77f8b96314091b935a5a07528f036ba54724`
  - `trajectory-20261128T080423756405Z.json` `ae07b0672523b54153d8778e58a4fc08b7b4ab3ce202e0ac951aee2c4c33bcc0`
  - `legacy-ground-20261128T080757614363Z.json` `2b3989fcf5731b35c2678967ecce6f8a5bd6ad55d8aec9c25fe958c4e29b838a`

## Gain

Headless, native backend, production field, `Shadow.receiving_ground` with seven samples, 5,000 calls, three
rounds: 41.0–42.2 µs with the old sampler, 10.7–11.4 µs with this one, identical results.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs and a live-app timing are not done yet.
