# NK-7a — the soundscape model functions in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F5b per-frame scripts](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).

## Why

Flight audio's soundscape costs about 170 µs per frame in GDScript on a loaded machine. The native soundscape core
(NK-7b) needs the model's laws first, each proven equal to the GDScript reference on its own.

## Change

- `nk_soundscape.hpp` ports `audio/soundscape_model.gd` `doppler`, `targets` (with `turbine_targets`,
  `exhaust_angle_deg` and `table_db`), `humidity_molar_pct`, `can_skip_humidity_fallback`, `absorption_db_per_m`,
  `absorption_cutoff_hz` and `screening`, plus `Wildlife.activity` and `PowertrainAudio.distance_gain`. It keeps
  GDScript's mixed precision: double scalars, `Vector3` in Godot's `real_t` through godot-cpp's copies of the engine
  operators, and the engine's `smoothstep`, `move_toward`, lerp order and dB conversions.
- `exp`, `log`, `pow` and `Vector3.angle_to` call the engine's own functions: the utility functions GDScript calls,
  and the engine's `angle_to` through its builtin-method pointer. Like the NK-5g pre-step, this keeps the results the
  engine's on every platform, whatever libm the library links. Without that method the angle is NaN.
- `nk_kernel.cpp` binds `sound_doppler`, `sound_targets`, `sound_humidity`, `sound_absorption_cutoff`,
  `sound_screening`, `sound_activity` and `sound_distance_gain`. The literal oracle gains every new decimal spelling.
  No GDScript caller changes in this step.

## Evidence

- `app/tests/test_native_soundscape_model.gd` (7 checks) matches the reference bit for bit: 20,000 Doppler cases
  including coincident endpoints; 40,000 target sets over four kinds, 10,000 of them turbines with on-axis and
  undefined exhaust rays; 6,000 humidity and absorption-cutoff cases, more than 1,000 solved inside the bracket; 8,000
  screening rays, more than 1,000 screened; 20,000 wildlife activity and distance-gain cases at every smoothstep edge;
  and an empty answer for a malformed request.
- `test_soundscape.gd` (180 checks) and `test_native_retarded_emission.gd` still pass.
- All nineteen installer gates pass for binary `2eb877b21374f99de9a3fac3f275ed34c518b440e3f3098272d938f678fa7bb8`; the
  literal check covers 194 spellings, and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T024609058894Z.json` `84561d6093c417dc0620105d324e74815438fa23eeaad133f2e6c38c9cf04e2e`
  - `stage_mutant-20261128T024633964755Z.json` `9a447f081d15e33777932b5addaad8214548c5621faf1dbd32a82c70780938ce`
  - `trajectory-20261128T024659306532Z.json` `763c4b66185a4bfe8241cd329b7112b1252ab608a51b5e5a6f0b6dda1d2b75cc`
  - `legacy-ground-20261128T025047385201Z.json` `923f05510db6d92fa5767b2bb997b35790a889e8e5925c7d394a5b62ea3ad5ae`

## Scope

Windows x86_64 only; macOS and Linux need their own runs of the parity test. No frame-time gain yet: callers move in
NK-7b.
