# NK-5c — faster per-tick configuration guard

2026-11-25. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-5b](../NK-5b/README.md).

## Why

Every native fixed-wing tick starts with `configuration_guard_matches`, which re-reads about 560 watched leaves of the
session's aircraft, hull, surfaces and model callbacks and refuses the tick if any changed outside an accepted
boundary. Timed headless at a fixed flying state, it cost 47–75 µs per tick, the largest single item of the pre-tick
callback. The cost per watch (about 100 ns) was mostly engine-interface overhead: each tick converted every parent
container from its stored `Variant`, hashed every String key, and converted both sides of every comparison.

## Change

Only `research/native-kernel/src/nk_configuration_guard.hpp` and the result keys in `nk_kernel.cpp` `stage()`
change. No GDScript, mirrored source or physics law changes.

- Each dictionary or array entry watch keeps its parent container, captured once at preparation. This is the same
  instance the old code converted from the stored `Variant` on every tick.
- A String key in an untyped-key dictionary is looked up as the equal `StringName`, which carries its hash. Godot
  dictionaries treat both as one key. The guard keeps the `StringName` only where the dictionary resolves it at
  preparation; an empty `StringName` does not hash like the empty String, so such a key stays a String.
- The expected value of every scalar is primed once: its type, the bool or int value, the float's bits and the packed
  array's bytes. Each tick then checks the type and compares those raw values. The rules are unchanged: bit equality
  for floats (±0 and NaN payloads stay distinct), byte equality for packed arrays, `Variant ==` for strings and packed
  strings, identity for callables and containers, refusal for anything else.
- `stage()` builds its result keys (`body_derivative`, the preview's air and context keys) once as function statics,
  as it already did for `loads`, instead of on every RK stage.

## Exactness

The guard returns a boolean, so exactness means the same accept or refuse decision for every live state:

- `research/native-kernel/test_native_configuration.gd`: pass, 975 checks over five fixtures. It covers changed
  session, simulation, environment and model fields, equal nested replacements (identity), the sign of scalar and
  packed zeros, layout sizes, owners and helicopters.
- New `app/tests/test_native_guard_leaves.gd` mutates nested leaves of the installed Corsair and Stik aircraft in
  place: floats, the sign of zero, ints, bools, strings, packed elements, a changed value type, and a removed or added
  key. Each mutation must refuse and its restore must accept: 98/98, the same result as the previous library.
- The installed Windows binary `dcd07f45fac98eecd4d77f7003f7163a2dac7797f43ff02b963b605c6bc4882c` passes all nineteen
  installer gates identically (`stage_oracle` 140,664; `trajectory` 21,771; `liquid_stage` 64,136; the rest unchanged
  from NK-5b), and the mutant build still fails (28,315 differences).
- An independent review found no bug; its one risk (the empty key) is closed by the resolution check above.
- Production tests after installation: `test_native_stage`, `test_native_session`, `test_native_replay`,
  `test_native_wake_admission` 21/21, `test_native_substep_preview` 97/97.

Accepted gate results (in the tool root, not in Git): `stage-20261125T205536389280Z.json`
`a93535723ca002e7f0c62e609cf4a55ed64724005bcd17572f343d701c27d4ef`, `stage_mutant-20261125T205607074487Z.json`
`01d24d9ed3fef771ad77679e5a0df817b8ac5ad852c99a84f061a473a1c328ae`, `trajectory-20261125T205636503914Z.json`
`5de30cb971fb5c216517b7c1e15974a4a84808537d9108a7285759dabafeff3a`, `liquid-stage-20261125T205902141061Z.json`
`6fb23997b3be9dda2e6c69a2511e93bbff37fdeda63cbd893cb8ae4e034c091d`.

## Gain

Median of 4,000 calls in five rounds at the same flying state on this shared workstation; two runs before, four
runs over the two NK-5c builds after:

| Aircraft | Guard before (µs) | Guard after (µs) |
| --- | ---: | ---: |
| Corsair | 70–72 | 46–52 |
| P-51 | 61–75 | 47–53 |
| Stik | 47–52 | 37–44 |
| Avanti | 57–65 | 47–59 |

That is about 10–25% less, roughly 8–22 µs per tick for every native fixed-wing aircraft, within this host's noise. One Corsair joint-stage call fell
from about 7.5 to 6.3 µs, and each tick makes four. Whole-tick times on this machine vary too much to attribute.

## Limits and next steps

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
- The remaining guard cost is one dictionary lookup and one `Variant` copy per watch through the engine interface.
  Removing it needs a different guard design (for example, read-only preparation snapshots), which would change
  what a mutation outside an accepted boundary does and is not part of this change.
