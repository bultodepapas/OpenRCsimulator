# NK-5h — guard plans: one engine comparison per root

2026-11-26. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5g](../NK-5g/README.md).

## Why

After NK-5g, most of the guarded pre-step was the two native guards that every native tick runs first. They check
that the session's prepared configuration (aircraft, hull, surfaces, lake, sim, vehicle callbacks) and weather have
not changed outside an accepted boundary, in-place edits included. Each walked every leaf: 487–616 configuration
watches and the weather fields. A diagnostic profile of the configuration guard (`configuration_guard_profile`) put
the cost in the per-key engine lookups and Variant copies (`Dictionary::get` 28–33 ns of a 36–70 ns leaf), not in
the comparisons. Per-leaf work cannot get much cheaper through the engine interface.

## Change

- `nk_guard_plan.hpp` holds the plan rules both guards share. Each guard's `build_plan` runs at preparation, after
  the full leaf walk has accepted the live configuration.
  - Root watches (session, simulation and owned properties) stay as they were.
  - Each root container is compared once per tick, inside the engine (`snapshot == live`: Dictionary/Array
    `recursive_equal`), against a `duplicate(true)` snapshot taken at preparation.
  - That comparison is type-strict, independent of key order, and exact for sizes, strings, ints, bools and packed
    bytes. It compares floats with `==`, so it is the guards' bit equality except for the sign of zero (and NaN).
    The following keep their own watch:
    - every nested ±0 float;
    - every packed float array holding a ±0;
    - every Callable (compared by identity);
    - every nested container whose content holds one of those, so those leaf watches read the live container at
      their path. The content is scanned rather than the watch tree, so shared containers are covered on every path.
  - A NaN, an unsupported value, excess depth, or a snapshot the engine does not accept keeps the full leaf walk.
- `nk_configuration_guard.hpp` and `nk_weather_guard.hpp` run the plan in `configuration_guard_matches` and
  `weather_guard_matches`. The kernel binds `configuration_guard_plan_ready()`, `weather_guard_plan_ready()` and the
  diagnostic `configuration_guard_profile(session, iterations)`.
- `native_stage.gd` `owns_stage` compares against the kernel callables built at installation instead of building a
  `Callable` on every call.

The one intended change in what is accepted: a nested container that holds no ±0 and no Callable may be replaced
by an equal copy. Content is what the reference and the stage read; any later change inside the copy still refuses.

## Review

An independent review of the first version found a real hole. The retained leaf watches read their
preparation-time parent container, so a container replaced by an equal copy, followed by a zero's sign flipped inside
the copy, passed both the old watch and `0 == -0`. Keeping the identity watch of every container that holds a
retained leaf closes it, and the test now includes that exact mutation.

## Evidence

- `app/tests/test_native_guard_leaves.gd` (185/185), Corsair and Stik. Both guards' plans are active for the stock
  aircraft. Every earlier in-place mutation still refuses and restores: float, sign of zero, int, bool, string,
  packed, changed type, erased and added keys, and array elements (now including strings). The new cases:
  - an in-place write through an alias into a packed array (the snapshot owns its buffer);
  - the sign of a zero inside a packed array;
  - nested dictionaries replaced by an equal copy: they are accepted only when they hold no zero or Callable, and a
    value or a zero's sign changed inside the copy refuses;
  - in-place float and zero-sign edits of the live weather configuration;
  - a configured NaN keeping the full walk, which still refuses a changed leaf.
- All nineteen installer gates are identical for binary
  `05d085015f6b66a29a913d32fdb12cb672ad16a9604defd048337c246e695423`, and the mutant build still fails. Accepted
  results (tool root, not in Git): `stage-20261126T151604116552Z.json`
  `db4b6d49675ac7906367798cbd5794728c0360cd7a7848f0a47ecbcc8d53b9c6`, `stage_mutant-20261126T151632982237Z.json`
  `898760286b1688a837701f8b372aa38de3a141f07703a5d52382d0216615636f`, `trajectory-20261126T151702386826Z.json`
  `8f97374c9323ec4c7e242ceee13ca28997a62267002bc87b35ac081dd7d665ed`, `liquid-stage-20261126T151949638108Z.json`
  `c47d21d795ec04cdc08d28e6dbbb04ae4419e4881407abd8bea9d6c2e601f632`.
- With the native stage installed, 37 suites pass: the native suites (pre-step, endpoint compressions, published
  compressions, contact reach, fallback, replay, session, stage, substep preview, wake admission, helicopter route
  and session, macOS domain world), golden flights, replay integrity, the runway fleet, reset and restore
  publication (guard restore paths), out-of-trim, turbulence, wind, atmosphere and spatial-weather flights,
  retractable gear, flaps, lake, crash cost, statistics, ground accidents, the electric, Extra and Lumber runways,
  trim throttle, servo-interval flight and helicopter weather admission.
- The independent review re-checked the fix and found no other way for the plan to accept what the full walk
  refuses, apart from the intended equal-copy case.

## Gain

Headless app (debug bridge), paused accepted endpoint, Corsair, P-51, Stik and Avanti, in flight and rolling. Another
session ran its own test suites on the same machine, so the ranges are wide.

| Per tick | Before | NK-5h |
| --- | ---: | ---: |
| configuration guard (native profile, full walk vs plan, same process) | 30–57 µs | 15–29 µs |
| weather guard (four-call eval) | ≈ 15.5 µs | 9–12 µs |
| `owns_stage` | ≈ 5 µs | ≈ 2.7 µs |
| `NativeStage.configuration_matches` (all of the above) | ≈ 51–78 µs, estimated from the parts | 26–39 µs |

Most of what remains is the aircraft root's engine comparison (10–17 µs), which still walks about 550 leaves inside
the engine.

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The plan relies on engine semantics (type-strict `hash_compare`, deep `duplicate`). The test's alias, type and
  zero-sign mutations exercise them on the pinned engine; an engine upgrade must keep that test passing.
- A configuration holding a NaN keeps the full walk and its cost.
