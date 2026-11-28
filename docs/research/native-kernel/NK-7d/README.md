# NK-7d — the accepted-tick ground audio in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

The ground audio cost about 100 µs per frame even with every wheel well clear of the ground. That was measured
headless on the native backend, with a P-51 and a .61 Stik airborne. Each frame, the accepted observation advanced
every wheel through dictionaries; `update_contacts` advanced each wheel again; and nine silent roll players had their
volume, pitch and `stop()` rewritten.

## Change

- `nk_ground_audio_core.hpp` `GroundCore` runs `audio/ground_audio.gd` in accepted-tick mode, the mode flight audio
  uses. That covers:
  - `observe_accepted`, with the same refusals and counters;
  - `touchdown_possible`, `touchdown_possible_at`, `note_skipped_tick` and `accepted_tick`;
  - `update_contacts`, including queued touchdowns, roll levels and pitch, pause fades and rewinds;
  - `stop`, `reset`, the bus release and `accepted_diagnostics`.
  The wheel law is `ground_audio_motion.gd` `advance`. The core writes the slots' roll and touchdown players
  through the engine's method binds, which NK-7b's table gains: `stop`, `is_playing` and `play`.
- `ground_audio.gd` binds the core when accepted mode turns on, with `native_core_enabled` on and the verified
  library loaded. Before each frame, `ground_core_pending_slots` lists the slots that frame would make; GDScript makes
  them with `_slot_for`, in the same order, names and offsets, and binds them. Only `touchdown_events`, `_was_paused`,
  `_scene_gain` and `_needs_seed` are kept in GDScript while the core runs. The legacy render mode and the accepted
  GDScript path stay as they were and remain the specification.
- The literal oracle gains the new decimal spellings.

## Evidence

- `app/tests/test_native_ground_audio_core.gd` (4 checks) compares a native rig and a GDScript rig, both in accepted
  mode, fed the same snapshots and frame updates. Over 4,000 frames they agree bit for bit after every call:
  - every observe and touchdown-query answer;
  - the diagnostics and the touchdown count;
  - each slot's roll and touchdown players: volume, pitch, position and playback;
  - roll levels and pitch, and the accepted wheel states.
- The run covers:
  - approaches, touchdowns, bounces and liftoff;
  - rolling on every surface, with and without roll;
  - pauses, rewinds, gaps, `since_tick` intervals, skipped ticks and rate changes;
  - 72 refused snapshots;
  - wheels appearing and leaving, more wheels than slots, and a detach.
- A one-part-in-10⁷ change to the GDScript roll-level constant makes 3,711 of the 4,000 frames differ.
- With the verified library loaded, `test_ground_audio` (90), `test_flight_audio_accepted` (37) and
  `test_mechanical_integration` (28) pass on the native cores. Without it, they pass on GDScript, as do
  `test_soundscape` (180), `test_native_soundscape_core` (44) and `test_windsock_motion` (37).
- All nineteen installer gates pass for binary `c45fe8409ae604f4067c01a6e075bcd676c98a1205da0998792362f13cebd319`;
  the literal check covers 235 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T040329308598Z.json` `51b9c0d85d0344b86fb94bca8c507ad28a5a8e966c91ef2c52038ea8fe26e97e`
  - `stage_mutant-20261128T040355302848Z.json` `a006e470a711f60072a06f1084f7dfb6cb45dc04e2596d4626f878e04796ee7d`
  - `trajectory-20261128T040421687570Z.json` `af9b380a42586a63486e114a46c9ba6ec8dec18eaa01eb44dc4e1be1e313003e`
  - `legacy-ground-20261128T040804167182Z.json` `525703c8ff02bddcec8a50c84a3480f65fb84e6c4ece26753cb634f6fbab783a`

## Gain

Headless, native backend, airborne P-51 and .61 Stik, 1,500 frames each:
- The whole `FlightAudio._process` went from 385–395 µs to 316–319 µs.
- `update_contacts` went from about 60 µs to 16 µs.
- The endpoint observations went from 138–163 µs to 105–137 µs. The ground contact snapshot (45–54 µs) still builds
  its rows in GDScript.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs, live-app timings and listening checks are not done yet.
- The contact rows (`GroundAudioModel.snapshot_contacts`) and the legacy render mode stay in GDScript.
