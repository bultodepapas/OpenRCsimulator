# NK-7e — the accepted-tick mechanical audio in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

After [NK-7d](../NK-7d/README.md), servo and retract audio was the largest part of an airborne flight-audio frame.
Measured headless on the native backend, with a P-51 and a .61 Stik and the surfaces still:
- the accepted observation cost 33–40 µs, through `mechanical_motion.gd` `observe` and its dictionaries;
- the per-frame update cost 62–86 µs: the observer again, the voices and the event queue.

Moving sticks add motion voices and transition cues on top of that.

## Change

- `nk_mechanical_audio_core.hpp` `MechanicalCore` runs `audio/mechanical_audio.gd` in accepted-tick mode, on
  `mechanical_motion.gd` `observe`. It covers:
  - `observe_accepted`, with the same refusals, discontinuities and bounded queue;
  - `update_sound`: render refresh, stale ticks, distance culling, pause fades, servo and retract motion voices,
    the two event voices with pending cues, release envelopes, priorities, rotating takes and gesture variations;
  - `reset` and the counters `diagnostics` reports.
  It writes the players through the engine's method binds, which gain `set_stream`.
- Motion players still appear lazily, in channel order, made by `_ensure_motion_player`. A frame therefore runs in
  two calls: `mechanical_core_prepare` returns the keys that need a player this frame, GDScript makes and binds
  them, then `mechanical_core_finish` runs the voices. With four surfaces and the gear, the voice pool's reuse branch
  cannot run; if any bound node disappears, the core stops.
- `mechanical_audio.gd` binds the core when accepted mode turns on, or when the profile is reconfigured, with
  `native_core_enabled` on and the verified library loaded. The counters that survive resets carry over at bind.
  `diagnostics` keeps its shape. `_accepted_events` reads the core's queue while the core runs. The legacy direct
  mode and the accepted GDScript path remain the specification.
- The literal oracle gains the new decimal spellings.

## Evidence

- `app/tests/test_native_mechanical_audio_core.gd` (8 checks) compares a native rig and a GDScript rig in accepted
  mode, fed the same endpoints and render snapshots, for 3,000 frames in each of two profiles: standard/electric
  and high-torque/pneumatic at servo level 0.7. Every frame matches bit for bit:
  - every observe answer;
  - the full diagnostics, including the last targets;
  - every motion and event player: name, volume, pitch, position, playback and stream;
  - the voices' gains, pitches, offsets, roles, envelopes and pending cues;
  - the queued transitions.
- Each profile's run covers:
  - 2,013 events played and 3,704 dropped by voice contention;
  - five motion voices;
  - 307 far-culled updates and six stale-tick resets;
  - 39 refused endpoints;
  - pauses, rewinds, gaps and `since_tick` intervals;
  - invalid listeners and a missing tick.
- A one-part-in-10⁷ change to the GDScript servo base gain makes about 2,330 of the 3,000 frames differ in each profile.
- These suites pass both with and without the library loaded: `test_mechanical_integration` (28),
  `test_flight_audio_accepted` (37), `test_ground_audio` (90), `test_soundscape` (180), `test_powertrain_audio`
  (49), `test_recorded_audio` (47) and `test_audio_bank_admission` (18). `test_glow_audio` (47) passes on GDScript.
  The NK-7a–7d parity tests pass on this binary.
- All nineteen installer gates pass for binary `d2d152f78260054a7e97512327f22745ddb596ec95f8971bbf2025168a711409`;
  the literal check covers 245 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T043059646507Z.json` `8bb5920a837c9a5ebbbebe0237dfbbc7da1976b7e9090302cef6c12f3af3a9bd`
  - `stage_mutant-20261128T043125120793Z.json` `de83a01299ef5c7ff0df423e9127df0adf332be8dff08e4f7e898033d6e6a3c7`
  - `trajectory-20261128T043150604145Z.json` `a7ec5c70c5153bdd4771b144d8504c5ca442505bf6ca4aad05cea34064b4018e`
  - `legacy-ground-20261128T043524126294Z.json` `f366e554e08920c2280cb335ad0e602f033f687579f75aec02e0df39f2134169`

## Gain

Headless, native backend, airborne P-51 and .61 Stik, 1,500 frames each over two runs:
- The whole `FlightAudio._process` went from 316–319 µs to 236–247 µs.
- The mechanical observation went from 33–40 µs to 7–9 µs.
- The mechanical per-frame update went from 62–86 µs to 24–39 µs. The rest of that is GDScript building the render
  snapshot (surface angles, gear state and hinge positions).

## Scope

- Windows x86_64 only. The macOS and Linux parity runs, live-app timings and listening checks are not done yet.
- The legacy direct mode stays in GDScript.
