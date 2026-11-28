# NK-7b — the soundscape core in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

`audio/soundscape.gd` `update_sound` cost 50–63 µs per frame headless and about 170 µs on a loaded machine. Most of that
went to dictionaries (the delay history kept a dictionary per sample, and each frame copied the snapshot twice) and
to about 60 engine property writes made through the GDScript VM. [NK-7a](../NK-7a/README.md) ported its laws.

## Change

- `nk_soundscape_core.hpp` `nk::sound::Core` runs `update_sound` in two calls per frame:
  - It reads the snapshot dictionary itself.
  - It keeps the propagation-delay history and the mix state: gain, clock, screening, absorption smoothing, Doppler,
    levels and wildlife presence.
  - It writes the fourteen voices, the glow player and both bus filters through the engine's own method binds
    (GDExtension ptrcall). The library's build profile is unchanged.
  - Between the two calls, four parts stay in GDScript: the recorded powertrain bank, the glow voice, the windsock
    and the wildlife scheduler. The bank and the glow voice receive the heard snapshot from `sound_core_heard`. The
    windsock and the scheduler read no delayed key, so they take the snapshot itself.
- Exactness:
  - The core keeps GDScript's operation order and mixed precision.
  - `Vector3` operations narrow the scalar to `real_t` first.
  - Float lengths use a correctly rounded single-precision square root.
  - `exp`, `log`, `sin` and `pow` are the engine's functions.
  - NK-6r's delay solver moved to `nk_soundscape.hpp`, shared with the `retarded_emission` binding.
  - The literal oracle gains the core's new decimal spellings.
- Refusal. The core refuses a frame before changing anything when:
  - a key holds a type the reference would convert differently, such as a String;
  - a key is present but null;
  - a bound node is gone.

  The soundscape then takes the mix state back (`sound_core_state`) and stays on GDScript. Its delay history
  restarts, so the heard delay re-grows once. Flight producers emit only floats, ints, bools and `Vector3`.
- Binding. `soundscape.gd` binds the core at an update with an empty delay history, with `native_core_enabled` on
  and the verified library loaded (a native flight loads it). Binding transfers the current mix state. The core is
  never bound when the engine lacks a method bind or `Vector3.angle_to`.
- The GDScript path stays the specification and the fallback. `test_soundscape.gd`'s absorption-sequence oracle
  reads that path's internal absorption state, so it pins `native_core_enabled = false`.

## Evidence

- `app/tests/test_native_soundscape_core.gd` (36 checks) runs two soundscapes side by side, one native and one
  GDScript, with the reference solving the delay in GDScript too. They are fed identical snapshots for 6,000 frames
  in each of nine scenarios: glow, electric, turbine and unknown kinds, a glow voice, gasoline and turbine recorded
  banks, a core bound mid-flight from non-default state, and a refused frame. Every frame ends bit for bit equal in
  every voice's volume, pitch, position, pause and playback, the glow player and telemetry, the bank, the windsock,
  both filters, the mix state, levels, targets, wildlife presence, events and scheduler, and the core's state.
- The runs cover:
  - 7–9 wildlife events per scenario, 82–84 disturbed frames where the motor is loud enough, and delays up to
    5.32 s, so history expiry and compaction run;
  - pauses, camera cuts, rewinds and gaps;
  - every read key missing in turn, and int or bool values;
  - delay and absorption switches, observer resets and a detach.
- A one-part-in-10⁷ change to the GDScript ducking constant fails the test, so the comparison is not vacuous.
- `test_soundscape.gd` passes 180 of 180 both with and without the library loaded. These suites pass:
  `test_audio_bank_admission`, `test_glow_audio`, `test_powertrain_audio`, `test_recorded_audio`,
  `test_flight_audio_accepted`, `test_ground_audio`, `test_windsock_motion`, `test_mechanical_integration`,
  `test_glow_audio_state`, `test_native_soundscape_model` and `test_native_retarded_emission`.
- An independent review found no divergence in the frame path. Its test-coverage and refusal points are addressed
  above.
- All nineteen installer gates pass for binary `0a23e3fb634bef07fa4f2c77bbe8b2b7dcc368afa1174c25ca394e046eabdb2e`;
  the literal check covers 212 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T032836952476Z.json` `7d75b933441ce3cd4f46efbed20846b9919e92c366eebd6d1f2881b7d1ee33a3`
  - `stage_mutant-20261128T032903175813Z.json` `d61fae9ab49ef13af74116463776b7f6bf2080f454c86f4446b53c18b5f8540c`
  - `trajectory-20261128T032929552073Z.json` `83c1e3472c09aa6ac60810dbabd8d4ba2807e1dc692f324df1cb2bb1f3c60a4b`
  - `legacy-ground-20261128T033313064240Z.json` `b2c92568bc685f64ce161d45fd2f40aec338711236b6c817032681a11948cab5`

## Gain

Headless, two soundscapes updated alternately on identical snapshots, median of 2,700 frames over two runs:

| Case | GDScript | Native core |
| --- | --- | --- |
| glow_prop | 50–51 µs | 18–19 µs |
| turbine | 55–59 µs | 19–20 µs |
| gasoline bank | 61–63 µs | 30 µs |

The bank case still runs the GDScript powertrain bank and builds its heard dictionary; the next step moves it.

## Scope

Windows x86_64 only. The macOS and Linux parity runs, live-app timings and listening checks are not done yet.
