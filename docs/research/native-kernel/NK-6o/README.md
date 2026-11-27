# NK-6o — the ground audio's wheel rows from the native stage

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6f](../NK-6f/README.md), which answers the hull-scrape observation's rows the same way.

## Why

On the ground, the flight audio observes each published endpoint once per frame. Its `GroundAudioModel.snapshot_contacts`
cost 264 µs per observation on the live Corsair (three wheels):

- 71 µs re-ran the whole GDScript wheel law (`Ground.evaluate` with diagnostics), only for each wheel's load, forces
  and rim speed;
- 52 µs recomputed each wheel's frame (`Wheels.frame`);
- 70 µs went to material queries;
- the rest was row assembly.

The native stage evaluates the same wheel law on every tick.

## Change

- `nk_wheels.hpp`: `wheels_evaluate` takes an optional row collector, filled where the reference appends its
  diagnostics. It changes no arithmetic of the qualified law.
- `nk_kernel.cpp`: `stage_wheel_rows(s, aux, steer, anchors, speeds, brake)` evaluates that law at the endpoint whose
  ground NK-5e's checks accept (now shared as `endpoint_ground`). It returns [1, n, n rows], or [0] where the
  reference has no diagnostics. Each row holds a wheel's load, longitudinal and lateral force, rim speed, compression,
  position, normal, heading, side and longitudinal speed. A wheel count mismatch or a nonfinite input refuses.
- `native_stage.gd` and `flight_session.gd`: `published_wheel_rows` asks under NK-5i's publication conditions. Test
  hook: `native_wheel_rows_enabled`.
- `ground_audio_model.gd`: `snapshot_contacts` reads the rows in place of `Ground.evaluate` and `Wheels.frame`. It
  computes the point velocity and approach speed itself, as before. Any refusal keeps the GDScript path.

## Evidence

- `app/tests/test_native_wheel_rows.gd`: 75 checks, none failed. Five aircraft were flown: Corsair and P-51
  (retractable gear), Ugly Stik 60, Turbo Lumber and the glow Stik 61FX. Each flew a takeoff roll, a steered taxi, a
  braked taxi, a touchdown and a lake-shore taxi, 960 ticks each.
  - On every published endpoint, each native row equals `Ground.evaluate`'s diagnostics and `Wheels.frame` bit for
    bit.
  - [0] answers exactly where the reference has no diagnostics (wheels beyond the terrain's reach).
  - `GroundAudioModel.snapshot_contacts` returns the same bytes with the rows on and off.
  - The native stage answered every in-reach endpoint except one in each of four glow Stik flights, which the
    reference evaluated.
- All nineteen installer gates are identical for binary
  `8c1cf1f44eab4c820539d3d1f4c0bb5a5c15857d9ca2da9b1ddb1133d9afe9c7`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T111900036987Z.json` `7ead1bcf06e1cdc990cbb27e44ad95ff522ba66d2f1cefe743fa4f48860eef8e`
  - `stage_mutant-20261127T111924305692Z.json` `73de97eacf1e12db640827c42d04092e4a0d208faa9c31523f77b0eb7bf3a234`
  - `trajectory-20261127T111948950853Z.json` `93f4b8d0e845b72093299af4d011050cb40bca6b300a9b08e67b62a189e018a7`
  - `legacy-ground-20261127T112312851619Z.json` `93a7b6746fb593cf87fd83fbca59f02353df09e5b9d6eef3bf7254e92980c540`
- With the native stage installed, 255 of 256 affected suites pass: the NK-6n set plus every audio and sound suite.
  `test_fixed_gear_brake_input` again needs the checked runner's legacy-engine oracle.

## Gain

Headless, `GroundAudioModel.snapshot_contacts` on a held runway endpoint, in alternating 2,000-call blocks:

| Aircraft | GDScript wheel law | Native rows |
| --- | ---: | ---: |
| Corsair (3 wheels) | 268 µs | 163 µs |
| P-51 (3 wheels) | 309 µs | 157 µs |
| Ugly Stik 60 | 260 µs | 144 µs |
| Glow Stik 61FX | 261 µs | 142 µs |

The ground audio observes once per frame on the ground, so a 60 Hz frame saves about 100–150 µs. The material
queries and row assembly remain in GDScript.
