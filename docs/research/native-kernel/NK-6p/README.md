# NK-6p — a native flight freezes its guarded configuration

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Owner decision: [a native flight freezes its guarded configuration](../../../DECISIONS.md#a-native-flight-freezes-its-guarded-configuration).
Follows [NK-5h](../NK-5h/README.md), which reduced the guard to one deep comparison per root container.

## Why

The configuration guard checks before every native tick that nothing changed the prepared configuration in place.
Its plan compared each root container with a deep snapshot: 16–42 µs per tick on every aircraft, the largest single
piece of a tick after NK-6o. Most of that time was the aircraft dictionary: 7–9 µs for the Corsair and Stik, and
32 µs for the glow Stik's 1,833 leaves. Godot's container equality stops at once when both sides are the same
object, but a writable container cannot share its snapshot.

## Change

- `native_configuration.gd`: preparation makes every Dictionary and Array the fixed-wing guard watches read-only all
  the way down: the aircraft dictionary, the hull contact and the lake. Godot cannot make a container writable
  again. Test hook: `NativeConfiguration.freeze_guarded_configuration`.
- `nk_guard_plan.hpp`: `frozen()` holds for a value whose containers are read-only all the way down, keys included,
  with no Object. Scalars, strings, packed arrays and Callables qualify: a read-only parent cannot take them back.
- `nk_configuration_guard.hpp`: the per-tick plan keeps each root's identity watch, but a frozen root needs no deep
  snapshot, and an entry of a read-only container needs no watch. Writable containers keep NK-5h's plan. The
  profile reports `plan_frozen_roots`.

An in-place write into a frozen container now fails where it is made, as an engine read-only error. Before, the
next native tick refused it. Replacing a root with another instance still refuses the tick.

## Evidence

- `app/tests/test_native_frozen_configuration.gd`: 30 checks, none failed, for the Corsair, Ugly Stik 60 and glow
  Stik 61FX.
  - After preparation the aircraft, the hull contact and the lake are read-only all the way down, and the plan proves
    three frozen roots by identity.
  - A root replaced by an equal writable copy refuses the configuration, and the original matches again.
  - With the freeze off the containers stay writable and the plan keeps its snapshots.
  - Flights are byte-identical with the freeze on and off.
- `test_native_guard_leaves.gd` (185 checks) and `test_native_session.gd` pass. Their in-place edits now run with the
  freeze off, to keep covering the comparison of writable containers. `test_native_session` also checks that a
  native flight's model is read-only.
- All nineteen installer gates are identical for binary
  `f3e72aa574f1d646652962e2c9c83701002a9b187618f8a477c5250e10dd3521`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T195350936875Z.json` `32e998d02428bc1b8ba513d7fa397e18a59a8f9a4dd943835f00b78bb98f6d06`
  - `stage_mutant-20261127T195417278807Z.json` `9aebab7405f77b9a976257ddb8052121244b7becfa93906ed120b4e36ec2fac3`
  - `trajectory-20261127T195441832853Z.json` `b460dd2971da0dcfdd44186eca7c639f4d89aff08766f353df47583a00b343fc`
  - `legacy-ground-20261127T195816941363Z.json` `da7130d3c6988f45394c8cc93e80d7dca0de496f2bfba2028d53e12c604f3ee4`
- `test_scenery_destruction_runtime.gd` wrote its synthetic hull probe into the frozen aircraft. It now installs the
  probe through a new aircraft and the reset that prepares it, and passes on the native backend (9 checks).
  `test_accident_integration.gd` simulates its developer reload with a replaced aircraft (100 checks).
- Full local suite on the F: build tree with the native stage installed: 1,166 of 1,192 scripts pass. None of the
  other 26 fails on a read-only write. They fail without this change too: the companion profiles' solver pin awaits a
  rebind, the sparse build tree lacks research fixtures, a race test runs the multirotor session (no native stage),
  `test_yaw_damping`'s open R02 gate, load-sensitive UI timing, or runner false positives.
- Live app, native backend: Ugly Stik and Corsair flights, a restart, a return Home and the Workshop opened in flight
  logged no read-only error.

## Gain

Headless, the guard's own profile (whole plan) and `NativeStage.configuration_matches` (with the weather guard and
ownership checks):

| Aircraft | Plan | `configuration_matches` |
| --- | ---: | ---: |
| Corsair | 22.1 → 3.1 µs | 37.8 → 7.3 µs |
| Ugly Stik 60 | 15.9 → 3.1 µs | 30.7 → 7.1 µs |
| Glow Stik 61FX | 42.1 → 3.1 µs | 64.0 → 7.0 µs |
