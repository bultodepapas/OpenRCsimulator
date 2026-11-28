# NK-7c — the recorded powertrain bank in the native soundscape core

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

After [NK-7b](../NK-7b/README.md), an aircraft with a recorded powertrain bank still ran the bank's GDScript update.
That covers the gasoline, electric, turbine and rotor families, such as the Corsair and the P-51. The core also had
to build a heard-snapshot dictionary for the bank: 30 µs per frame against 18–20 µs without a bank.

## Change

- `nk_soundscape_core.hpp` `Core::bind_bank` and `bank_update` run `audio/powertrain_audio.gd` `update_sound` inside
  the core's frame, where the soundscape called it, on the heard values:
  - rpm smoothing and the family level laws, including the turbine's roar directivity;
  - `band_weights` through the engine's `log`, `sin` and `cos`;
  - the distance gain and the per-player level, pitch, position, start (`play` by method bind) and pause.
  The bank's state stays in the core, and `soundscape.gd` mirrors it back to the bank each frame: `_rpm`,
  `_primed`, `_started`, `levels` and `last_targets`. Both soundscape reset paths reset it, as the bank's
  `reset_observer` and `rebind` do.
- `soundscape.gd` binds the bank with its layers (each layer's rpm and gain, as GDScript reads them), family,
  profile defaults and current state when it binds the core. If the bank cannot bind, the soundscape stays on the
  GDScript path. The heard dictionary is built only for the glow voice now.
- The literal oracle gains the bank's decimal spellings.

## Evidence

- `app/tests/test_native_soundscape_core.gd` (44 checks) now has eleven scenarios of 6,000 frames each:
  - recorded gasoline, turbine, electric and rotor banks; the rotor profile has no `max_rpm` or trim, so it falls
    back to the profile defaults;
  - a gasoline bank bound mid-flight.
  For every scenario, every frame ends bit for bit equal in the bank's rpm state, levels, `last_targets` and each
  player's volume, pitch, position, pause and playback, as well as in everything NK-7b compares.
- A one-part-in-10⁷ change to the GDScript bank's rpm smoothing constant fails the five bank scenarios in
  5,748–5,895 of 6,000 frames and leaves the other six passing.
- These suites pass: `test_soundscape` (180), `test_audio_bank_admission`, `test_powertrain_audio`,
  `test_recorded_audio`, `test_glow_audio`, `test_flight_audio_accepted`, `test_native_soundscape_model` and
  `test_native_retarded_emission`.
- All nineteen installer gates pass for binary `91d934e65105481d8fc26f0bf302b501c0f5e47d6c668e1aad4e9c7394d20be6`;
  the literal check covers 226 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T033933453432Z.json` `8a401df69eca65ebd4e8daee31387d0bb1ed6090eb75de30c3a7320cdb86d393`
  - `stage_mutant-20261128T033959596991Z.json` `ae7ba9e3b5364d10080948027dbc27a38e47a6fb71a19fb993761734131a6a0b`
  - `trajectory-20261128T034025859538Z.json` `74eb19487be6f18d91157ead77c35684c10bf5a89c9cc037863976f6455b1416`
  - `legacy-ground-20261128T034409570951Z.json` `54de80ea172517bc2bef65d4925dc15bf242446207f93ebc5a10d18fa12672e8`

## Gain

Headless, two soundscapes updated alternately on identical snapshots, median of 2,700 frames over two runs. A
gasoline bank costs 22–23 µs against 61–62 µs on the GDScript path; it cost 30 µs after NK-7b. Aircraft without a
bank are unchanged at 18–19 µs.

## Scope

Windows x86_64 only. The macOS and Linux parity runs, live-app timings and listening checks are not done yet.
