# NK-9b — the statistics sample in one native call

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick main-thread cost](../../../plans/optimization-priorities.md).

## Why

After [NK-9a](../NK-9a/README.md), the statistics adapter's `sample(true)` was the larger half of the per-tick
statistics cost. Each published tick it builds an 18-key sample in GDScript:
- quaternion rotations of the velocity and the ground normal;
- the bank and pitch;
- the support flags from the compressions and the profile's indices;
- the incident and ground-contact flags from the contact events.

## Change

- `nk_stats_sample.hpp` builds that sample from the state, the native endpoint facts (NK-5i), the contact events and
  the validated accident observation:
  - in the GDScript literal's StringName key order and value types;
  - with `math3d.gd`'s `q_rotate` order (as NK-7f) and the engine's own `atan2`, `pow`, `sqrt`, `absf` and
    `deg_to_rad`;
  - with GDScript's short-circuits and its String or StringName comparisons for the event fields.
- The kernel binds it as `stats_sample_bind` and `stats_sample_build`; each adapter holds its own kernel instance.
- `fixed_wing_adapter.gd` binds it at `configure` for the profile values `sample()` reads, and uses it for published
  samples. It keeps in GDScript:
  - the accident-packet checks, the gear-extension read and the damage observation;
  - every case the kernel does not mirror: unpublished samples, authored-hull profiles, other index collections and
    contact fields of other types.
- Hook: `Adapter.native_sample_enabled`, read at `configure`.

## Evidence

- `app/tests/test_native_stats_sample.gd` (13 checks) attaches two adapters to the same native session, one with the
  native sample and one without. Every published tick their samples are byte-identical.
  - The flights run on the production field, lake and scenery world with soft hull contacts: a takeoff roll and
    climb, a hard landing, a nose-over, and an engine-off glide.
  - Each flight uses the Corsair, the glow Stik 61FX and the electric Stik 6S.
  - Support, incidents, terminal outcomes and airborne ticks all occur.
  - A 10⁻⁹ change to one sample value is detected.
- 52 suites pass on the installed binary: every `test_native_*` script and every flight-statistics suite.
- All nineteen installer gates pass for binary `7d789a6119ef351179197a1c551e3fbd03462f1e3e4aa7a2e03f9c79227e9a43`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T094328545662Z.json` `e0d1e12fe8d85a75486a86c183fb562380404c2e2b1791d9d982b36be1a8ff9b`
  - `stage_mutant-20261128T094354137906Z.json` `3021f233fe6775ab29ce4e80d37b3f6acb396745ffe90ead0e410b41947352e6`
  - `trajectory-20261128T094419433117Z.json` `4be3c9a0e720fc936e39116357430bb802cd1d6e8637b99cf8d0fb5a29515f25`
  - `legacy-ground-20261128T094754156202Z.json` `fd7214cf9dbccd4847e31d911474c5061411659d4f6afdd14fe83cb9167c5cbf`

## Gain

Headless, native backend, production field. Corsair and glow Stik, 2,400 ticks; `sample(true)` timed inside each
publication for both adapters, two runs: 27–30 → 22–24 µs per tick.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- The remaining time is session packet plumbing: the accident observation, built, validated and deep-copied each
  tick (about 7 µs live); `published_endpoint_facts`'s byte comparisons of the state and aux; and the contact-event
  copy.
