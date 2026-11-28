# NK-7f — flight audio's airborne contact rows and source kinematics in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

After [NK-7e](../NK-7e/README.md), two pieces of the airborne flight-audio frame built rows from the accepted
rigid-body state in GDScript, through `math3d.gd` quaternion arrays and frame conversions:
- the ground contact rows, 43–51 µs, about 25 µs of it the airborne rows (`GroundAudioModel._unloaded_rows`);
- the snapshot's source position, velocity and exhaust.

## Change

- `nk_audio_rows.hpp` ports both, exactly:
  - `_unloaded_rows` builds each row as a dictionary with GDScript's keys, order and value types;
  - the snapshot's kinematics run in `math3d.gd`'s operation order;
  - both narrow to `real_t` where `Frames.ned_to_render` does, signed zeros included.
  The kernel binds them as `audio_unloaded_rows` and `audio_source_kinematics`. Each kernel instance owns its
  dictionary keys, so no StringName outlives the engine.
- `ground_audio_model.gd` `_unloaded_rows` and `flight_audio.gd` `snapshot()` call the kernel once the verified
  library is loaded. A malformed arm or offset, or a library without these methods, keeps the GDScript evaluation,
  which stays as the specification. Hooks: `GroundAudioModel.native_rows_enabled` and
  `FlightAudio.native_kinematics_enabled`.

## Evidence

- `app/tests/test_native_audio_rows.gd` (3 checks) runs 5,000 random states (attitudes, velocities, rates), gear
  arms (named, unnamed, without a position, malformed), propulsion offsets and thrust axes (with and without an
  exhaust). Its results:
  - 9,590 airborne rows equal the GDScript rows bit for bit, including value types, key order and signed zeros;
  - the kinematics equal the snapshot's GDScript evaluation;
  - a malformed offset answers empty.
- Changing one GDScript row value by 10⁻⁷ makes 3,952 of the sets differ.
- These pass with the library loaded: `test_flight_audio_accepted` (37), `test_ground_audio` (90),
  `test_mechanical_integration` (28) and `test_soundscape` (180). Without it they pass on GDScript, and the NK-7a–7e
  parity tests pass on this binary.
- All nineteen installer gates pass for binary `6f1cd3942c00718963d004aed8d9b2cd22e29c44c0b516ac84ae839f3c258f4f`;
  the literal check covers 245 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T045618238784Z.json` `47711fb9a2229d763117d5c5e28c2de75528b89b39b6abafae755f09b2610a80`
  - `stage_mutant-20261128T045643561952Z.json` `ceb7ab2740fbf7b309e398d8e7919336d5af77ddebae0b143deb26594d64af05`
  - `trajectory-20261128T045709054300Z.json` `71f6e868aed2809e9c958cc1a157ac7ecfbbe6e27398d45ad9fb78daf69817b2`
  - `legacy-ground-20261128T050043196299Z.json` `26d41b297ead22987964b5fb7e060962007152145984f15c18303a5e039054ac`

## Gain

Headless, native backend, airborne P-51 and .61 Stik, 1,500 frames each over two runs:
- The whole `FlightAudio._process` went from 236–247 µs to 215–227 µs.
- The contact snapshot went from 43–51 µs to 29–38 µs.
- The flight snapshot went from 65–89 µs to 59–82 µs.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs and live-app timings are not done yet.
- The grounded contact rows are unchanged; their per-wheel diagnostics are already native ([NK-6o](../NK-6o/README.md)).
