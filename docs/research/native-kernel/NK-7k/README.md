# NK-7k — the ground audio's near-ground band from the native stage

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

`GroundAudioModel.snapshot_contacts()` treats an aircraft as clear of the ground only above the wheels' reach plus a
margin and half a second of travel. Below that, and above the reach itself, the native wheel rows answer `[0]` (no
wheel can touch). NK-7j did not cover this band, and GDScript still built each row:
- `Wheels.frame` per contact;
- `Ground.loads` per contact, which revalidates the lake and answers no loads;
- the support sample.

That cost 188–198 µs per observation. At 30 m/s the band reaches about 16 m above the ground, so it covers most low
flying, every approach and every climb-out. Near touchdown, flight audio also evaluates
`GroundAudioModel.approach_speeds()` on every skipped tick (69–72 µs each, up to three per frame), from the same
frames.

## Change

- `nk_audio_rows.hpp`:
  - `append_row` is the single row builder for NK-7j's loaded rows and this band: approach speed, normal force,
    rolling speed, support sample, and region and material strings.
  - `band_rows` builds the band's rows from each contact's frame, with the force `[0, 0, 0]` and rim speed 0 that the
    reference reaches.
  - `approach_speeds` answers each contact's approach speed against its frame normal.
- `nk_kernel.cpp`:
  - `endpoint_frames` evaluates the stage's `wheel_frame` (`Wheels.frame`'s native law) for every contact of the
    endpoint's ground. It answers only when the GDScript contact positions carry the stage's bits.
  - `stage_wheel_audio_rows` answers the band when the wheel rows are `[0]` and the altitude is beyond both of
    `Ground.loads`' reach bounds: reach plus the table's height bound on the lake route, and reach alone on the plain
    route.
  - `stage_wheel_approach_speeds` answers the approach speeds.
- `NativeStage.approach_speeds` binds it. `FlightSession.published_approach_speeds` answers under
  `published_wheel_rows`' conditions, which `_published_wheel_endpoint` now states once for both audio answers.
  - Hook: `native_approach_speeds_enabled`.
  - Diagnostic: `native_approach_answers`.
- `GroundAudioModel.approach_speeds` uses the native speeds when every contact carries a three-value position, and
  otherwise evaluates its loop.

## Evidence

- `app/tests/test_native_audio_band_rows.gd` (102 checks) covers five aircraft: the Corsair, the Ugly Stik, the Turbo
  Lumber, the glow Stik 61FX and the P-51.
  - Each runs four scenarios on the production field with its lake: a descent onto the runway, a low pass, a rolling
    climb-out and a descent onto lake-covered ground, up to 1,200 ticks.
  - Every tick:
    - `snapshot_contacts()` is byte-identical with the native rows on, with them off, and with every native answer
      off;
    - `approach_speeds()` returns the same speeds and identities with the native answer on and off.
  - The native rows answered every band endpoint in all twenty flights (261–1,200 per flight).
  - A 10⁻⁹ change to a row or a speed is detected.
- `app/tests/test_native_audio_loaded_rows.gd` (NK-7j, 93 checks) still passes with the shared row builder.
- 111 affected suites pass on the candidate: every `test_native_*` script and the audio, ground, wheel, lake and
  flight-session suites. The local runner flags one, `test_rcv_nitro_audio`, on its own `FAILURES=0` line; it exits 0
  with 23 of 23 checks.
- All nineteen installer gates pass for binary `ad33c2500421b1403eb38ff0fcd03a1f897e2b7adcf77c8079a08313cba6f13d`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T122746743727Z.json` `7a4d791a1a53b08def2f00d56c3bda9ea87b59f3f9b192b017d5d46b5dbd339d`
  - `stage_mutant-20261128T122812250720Z.json` `1de36c108403c06e322c28591860c909438f27a198c004c23c6d7c0acd7d20c1`
  - `trajectory-20261128T122840249306Z.json` `bd749c82428075a66b9d51bd25aad9aea3224fb8c94e14189426b85dbd4596ee`
  - `legacy-ground-20261128T123215217984Z.json` `b930762251ba4df011bcb73a04f9631c1290469f8df4fb1e91a065301d38e027`

## Gain

Headless, native backend, production field with cost observations on, airborne start descending onto the runway. The
same ticks are timed with the native answers on and off. Medians:

| Aircraft | `snapshot_contacts()` µs | `approach_speeds()` µs |
| --- | --- | --- |
| P-51 | 193 → 39 | 72 → 19 |
| Glow Stik 61FX | 188 → 35 | 69 → 17 |
| Corsair | 198 → 40 | 72 → 19 |

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- An RC track overlay and a ground-vehicle road keep the GDScript rows.
