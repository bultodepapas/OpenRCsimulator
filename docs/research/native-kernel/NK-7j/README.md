# NK-7j — the ground audio's loaded contact rows from the native stage

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

On the ground, every ground audio observation runs `GroundAudioModel.snapshot_contacts()` (at least once per frame,
and on every tick near touchdown). NK-6o already takes each wheel's diagnostics and frame from the native wheel law.
The rows built from them still cost 138–142 µs per call in GDScript for three wheels:
- each wheel's point velocity and approach speed (about 30 µs);
- the force and load arithmetic (about 19 µs);
- `surface_observation` (about 63 µs). It calls `Environment.sample_support`, which revalidates the surface table
  and the lake definition, samples the terrain, and builds a 25-key support dictionary. The audio row reads three
  of those keys.

## Change

- `nk_audio_rows.hpp` `loaded_rows` builds those rows from the native wheel rows, in `math3d.gd`'s operation order and
  with the GDScript's key order and types:
  - `_row_kinematics`;
  - the force, normal force and rolling speed;
  - `surface_observation`.
- Its `support_sample` is `GroundSupport.sample`'s legacy law on the stage's validated table and lake:
  - the terrain sample and its normal;
  - the surface row search;
  - the gap and rate finiteness checks;
  - the lake coverage.
- The region and material come from the environment's prepared support (`Environment._ground_support.regions`), and
  the roll family from `MATERIAL_ROLL_FAMILIES`.
- `nk_kernel.cpp` `stage_wheel_audio_rows` answers `stage_wheel_rows` and, from those rows, the audio rows in one call.
  It builds them only when:
  - the environment's surfaces and the prepared support's surfaces carry the stage table's bits;
  - the support is a successful preparation under the legacy law;
  - every region entry it reads holds strings.

  Otherwise it answers the wheel rows alone, and GDScript builds the audio rows from them.
- `NativeStage.wheel_audio_rows` binds it. `FlightSession.published_wheel_audio_rows` answers under
  `published_wheel_rows`'s own conditions, and refuses a ground-vehicle road (`Environment.sample_support`'s other
  refusal).
  - Hook: `native_audio_rows_enabled`.
  - Diagnostic: `native_audio_row_answers`.
- `GroundAudioModel.snapshot_contacts` uses the answer when every contact carries a three-value position. Otherwise it
  keeps NK-6o's rows and then the reference.

## Evidence

- `app/tests/test_native_audio_loaded_rows.gd` (93 checks) covers five aircraft: the Corsair, the Ugly Stik, the Turbo
  Lumber, the glow Stik 61FX and the P-51.
  - Each runs six scenarios on the production field with its lake: a takeoff roll, a steered taxi, a braked taxi, a
    touchdown and a lake-shore taxi (960 ticks each), and a stand on lake-covered ground (480 ticks).
  - Every tick, `snapshot_contacts()` is byte-identical:
    - with the native rows on;
    - with them off (built in GDScript from the native wheel rows);
    - with every native answer off (the reference).
  - The native rows served 873–960 of 960 endpoints in every rolling scenario and every endpoint of the stand.
  - They reached the `field:runway` and `field:rough` regions with their `maintained_turf` and `long_grass` materials,
    and the lake-covered rough ground, which keeps its region without a measured material.
  - A 10⁻⁹ change to a row is detected.
- 110 affected suites pass on the candidate: every `test_native_*` script and the audio, ground, wheel, lake and
  flight-session suites. The local runner flags one, `test_rcv_nitro_audio`, on its own `FAILURES=0` line; it exits 0
  with 23 of 23 checks.
- All nineteen installer gates pass for binary `c16aba48821eaaab9b84ae6e2ad9d4d73d223d7f89105d0853972442fbbb2729`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T115852782541Z.json` `e48d8bd702e5b1609e1f5e3271f4a033b3eb20347a50757f7dd1fc5ce45e2762`
  - `stage_mutant-20261128T115918134710Z.json` `f0c8759a19249a3cb0a108af2ed17d9dd766ff6365e9eff3ab63cc3c1625a217`
  - `trajectory-20261128T115943371064Z.json` `fec7d0f4a2e4854481a52d8283830d060c4486968719da724cd5dafd72dd1bae`
  - `legacy-ground-20261128T120332645212Z.json` `b871f25d5eba62498d3fdc53543ddefb4789b07044541d11991ca04037367642`

## Gain

Headless, native backend, production field with cost observations on, runway start, 1,200 frames of four ticks
(taxi, then a takeoff roll), with the hook alternating each frame. Medians:

| Aircraft | `contact_snapshot()` µs | `FlightAudio._process` µs |
| --- | --- | --- |
| P-51 | 138 → 41 | 298 → 200 |
| Glow Stik 61FX | 138 → 38 | 323 → 224 |
| Electric Stik 6S | 142 → 41 | 273 → 172 |

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- Still in GDScript:
  - the gear and clearance reads before the call (about 17 µs);
  - the rows of a `[0]` answer (no wheel within the terrain's reach);
  - the approach speeds of skipped ticks near touchdown.
