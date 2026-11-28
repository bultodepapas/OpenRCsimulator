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
  snapshot, and an entry of a read-only container needs no watch unless it is a packed array (below). Writable
  containers keep NK-5h's plan. The profile reports `plan_frozen_roots`.
- `native_stage.gd`: the freeze waits until the kernel has accepted the stage and the macOS domain guard (where
  present) has passed, just before the configuration guard builds its plan. A refused stage leaves a writable
  reference flight.

A container write into a frozen root now fails where it is made, as an engine read-only error. Before, the next
native tick refused it. Replacing a root with another instance still refuses the tick.

### Packed arrays stay writable in place

The Good Enemy review of the first commit found that Godot 4.8-beta2 shares a packed array's buffer with every
alias. An element write changes the array inside a read-only parent, through an alias or directly
(`aircraft.model.crash_hull[0] = x`), with no engine error. The first commit dropped those leaves' watches, so the
guard missed such a write (probe: the write reached the aircraft and `configuration_matches` stayed true). Each
packed leaf under a frozen root now keeps its bitwise watch (35–64 per aircraft), and such a write still faults the
next native tick. The first commit also froze before the kernel accepted the stage.

## Evidence

- `app/tests/test_native_frozen_configuration.gd`: 78 checks, none failed, for the Corsair, Ugly Stik 60 and glow
  Stik 61FX.
  - After preparation the aircraft, the hull contact and the lake are read-only all the way down, and the plan proves
    three frozen roots by identity.
  - A root replaced by an equal writable copy refuses the configuration, and the original matches again.
  - An element write into a packed leaf of the aircraft, the hull contact or the lake, through an alias or directly,
    reaches it and is refused; the restored value matches again.
  - `NativeConfiguration.prepare` alone leaves the aircraft writable.
  - With the freeze off the containers stay writable and the plan keeps its snapshots.
  - Flights are byte-identical with the freeze on and off.
- `test_native_guard_leaves.gd` (185 checks) and `test_native_session.gd` pass. Their in-place edits run with the
  freeze off, to keep covering the comparison of writable containers. `test_native_session` also checks that a
  native flight's model is read-only.
- All nineteen installer gates are identical for binary
  `b586af923a64ab6324ded772c95fff8d2a3637114c6bbb281ff20bef3318c4d3`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T213413378953Z.json` `66b505997ef3d5a977123135856ea869ddb630ef8c996d107450d267840ccfef`
  - `stage_mutant-20261127T213439398372Z.json` `51e004409210c3e7743e9173640e1a3417b76f87018d7ea4831682e166318e75`
  - `trajectory-20261127T213505527545Z.json` `d80ec23fd852eef9315e6bcc50b70dc15e9118f89b6d38e4a66cebce2afbddb6`
  - `legacy-ground-20261127T213845818576Z.json` `75d3ee712a926985ca4df0c194a81ddd6463ff4f56e2ec6cee3fdb6d4e408f35`
- `test_scenery_destruction_runtime.gd` wrote its synthetic hull probe into the frozen aircraft. It now installs the
  probe through a new aircraft and the reset that prepares it, and passes on the native backend (9 checks).
  `test_accident_integration.gd` simulates its developer reload with a replaced aircraft (100 checks).
- Full local suite with the first commit's binary, on the F: build tree with the native stage installed: 1,166 of
  1,192 scripts pass. None of the other 26 fails on a read-only write. They fail without this change too: the
  companion profiles' solver pin awaits a rebind, the sparse build tree lacks research fixtures, a race test runs the
  multirotor session (no native stage), `test_yaw_damping`'s open R02 gate, load-sensitive UI timing, or runner
  false positives. With the fix, the 38 scripts that prepare a native stage or test the guard, the accident ledger
  or the session all pass.
- Live app, native backend (first commit): Ugly Stik and Corsair flights, a restart, a return Home and the Workshop
  opened in flight logged no read-only error.

## Gain

Headless, the guard's own profile (whole plan) and `NativeStage.configuration_matches` (with the weather guard and
ownership checks), before NK-6p and now. The packed leaves' watches (69–100 plan watches) cost 2.5–4.5 µs of the
plan; the first commit's unsound plan took 3.1 µs.

| Aircraft | Plan | `configuration_matches` |
| --- | ---: | ---: |
| Corsair | 22.1 → 7.5 µs | 37.8 → 12.0 µs |
| Ugly Stik 60 | 15.9 → 5.5 µs | 30.7 → 9.9 µs |
| Glow Stik 61FX | 42.1 → 6.6 µs | 64.0 → 12.0 µs |
