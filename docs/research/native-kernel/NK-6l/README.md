# NK-6l — the session guard's hull checks from the native stage

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6k](../NK-6k/README.md).

## Why

Within reach of the ground, every accepted tick ran two GDScript loops over the crash hull's points:

- `HullContact.contacts` for the session's soft contacts, 7–10 µs per tick;
- `HullContact.terminal` in the pre-tick guard of aircraft without finite fuel, 7–9 µs per tick.

While rolling on the gear, both find nothing.

## Change

- `nk_kernel.cpp`: `prepare_hull_guard(crash_depth)` takes the session hull's crash depth at installation.
  `stage_hull_guard(previous, s)` answers with two bits, on the stage's hull:
  - Bit 1: `HullContact.terminal` must return no event. NK-6h's `terminal_geometry_quiet` applies: no point newly
    penetrates, lies deeper than the crash depth or meets the lake.
  - Bit 2: `HullContact.contacts` must return no contact. The state is above the hull's reach, or the lake is out of
    reach and every point is at or above the datum, by the reference's depth arithmetic.

  0 leaves both checks to the reference.
- `native_stage.gd`: `hull_guard(previous, s, hull)` answers only for the hull dictionary the installation read.
  Uninstalling also drops NK-6k's and this batch's references to the session's disc, lake and hull.
- `flight_session.gd`: `_refresh_soft_contacts` and the guard's terminal check ask `_native_hull_guard`. It answers
  for the endpoint being natively published or the last natively published one, without an RC track, for this class.
  Test hook: `native_hull_guard_enabled`.

## Evidence

- `app/tests/test_native_ground_guard.gd`: 86 checks, none failed, for the Corsair, Ugly Stik 60 and Turbo Lumber.
  - 3,000 perturbed tick pairs each, a third of them at the lake's bank or over its water, from clear of the ground to
    below it. Every native empty-contacts answer has an empty `HullContact.contacts` (1,141–1,443 answers), and every
    native quiet answer has no `HullContact.terminal` event (1,500–1,753 answers, checked on the two aircraft without
    finite fuel, where the guard asks). Wherever the reference's own `_hull_clear_of_lake` holds, the native stage
    answers every empty contact set. Between 1,021 and 1,331 pairs touch, and 767–1,040 are terminal events, all of
    them in the reference.
  - A hull dictionary other than the installation's is refused.
  - The NK-6g–6k pairs (takeoff roll, lake-shore taxi, hard landing, nose-over) fly byte-identical with every shortcut
    on and off, including the native hull checks.
- All nineteen installer gates are identical for binary
  `793476f4a53fa38cc0677a6408aad8c9d3e4787cd3bbab6c763ddb3ec58805db`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T084605854778Z.json` `b873ed96e8829b68f9af70a14c8409272a266ad9b39ee3dec692907151198888`
  - `stage_mutant-20261127T084633208819Z.json` `0fa5acd4071aa694c10f786dfe2b011aad8e1d6ef9c58810be24eb300082555b`
  - `trajectory-20261127T084659626533Z.json` `8d78427de9f3dd22ab11760e8130b6b605668f69b4cf83a5543dc576cff7ab68`
  - `legacy-ground-20261127T085034668795Z.json` `8836d2bbbee4e0cd066d8bdf2751f092cc7dc45a22a828ea27fb4e9f0d23927c`
- With the native stage installed, 199 of 200 affected suites pass, the same set as [NK-6k](../NK-6k/README.md).
  `test_fixed_gear_brake_input` again needs the checked runner's legacy-engine oracle.

## Gain

Headless, with the native stage installed, on the runway at taxi power (two runs each):

| Aircraft | `_refresh_soft_contacts` | Guard (`_session_after_input`) | Whole tick |
| --- | ---: | ---: | ---: |
| Corsair (liquid fuel) | 8.1–8.2 → 1.7 µs | unchanged (no guard terminal) | within noise |
| Ugly Stik 60 | 9.3–9.7 → 1.7–1.8 µs | 23.3–26.2 → 12.6–12.9 µs | 269–282 → 248–256 µs |
| Turbo Lumber | 7.3–7.8 → 1.7 µs | 20.8–21.7 → 13.0–13.1 µs | 294–298 → 271–282 µs |

The glow Stik 61FX gains the same 6–7 µs in `_refresh_soft_contacts`; its timing flight crashed, so its whole-tick
blocks are not comparable.
