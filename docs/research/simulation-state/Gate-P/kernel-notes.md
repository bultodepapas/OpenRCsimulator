# Gate P native slipstream kernel notes

2026-10-07 · **Status: Linux build and direct oracle checks pass; see the [experiment report](README.md) for flight and performance evidence.** Gate P.

## Scope

The C++ kernel ports the operations in [`slipstream.gd`](../../../../app/physics/slipstream.gd): wake calculation, tail-piece immersion, swirl velocity, and accumulation of washed-minus-free tail loads. It ports the matching tail law and load calculation from [`aero.gd`](../../../../app/physics/aero.gd). Thrust and shaft torque are supplied by the caller; this kernel does not calculate propulsion.

`OpenRCNativeSlipstream.tail_loads` resolves the active model dictionaries on every call. Its fixed-size state, velocity, thrust/torque, and result arrays are 13, 3, 2, and 6 doubles. Malformed shapes, non-finite values, and invalid divisors return an empty packed array. The GDScript adapter converts refusal to six nonfinite load values so Dynamics preserves its six-component shape and Simulation rejects the tick atomically. The kernel holds no cross-call state or cache. The bounded piece array accepts up to 16 pieces; current aircraft data uses three.

## Godot 4.7 scalar semantics mirrored

- `lerpf(a, b, t)` evaluates `a + (b - a) * t` in [`math_funcs.h`](https://github.com/godotengine/godot/blob/4.7-stable/core/math/math_funcs.h#L2374-L2378).
- `wrapf` computes `range = max - min`, returns `min` when `abs(range) < CMP_EPSILON`, then evaluates `value - range * floor((value - min) / range)`. It maps a result approximately equal to `max` back to `min`. `is_equal_approx` uses `CMP_EPSILON` (`0.00001`) times the left operand’s magnitude, with that epsilon as the minimum tolerance. See [`math_funcs.h`](https://github.com/godotengine/godot/blob/4.7-stable/core/math/math_funcs.h#L2645-L2696) and [`wrapf`](https://github.com/godotengine/godot/blob/4.7-stable/core/math/math_funcs.h#L2856-L2876).
- `clampf` delegates to `CLAMP`; `maxf` delegates to `MAX`. The comparison order is defined in [`typedefs.h`](https://github.com/godotengine/godot/blob/4.7-stable/core/typedefs.h#L142-L154), and the utility bindings are in [`variant_utility.cpp`](https://github.com/godotengine/godot/blob/4.7-stable/core/variant/variant_utility.cpp#L678-L680) and [`variant_utility.cpp`](https://github.com/godotengine/godot/blob/4.7-stable/core/variant/variant_utility.cpp#L762-L764).

The implementation keeps the oracle’s expression order, including the explicit `+ 0.0` in its free-stream velocity path. The native build must use `-ffp-contract=off` and must not enable fast-math. Compile-time checks require 8-byte IEEE-754 `double`.

## Validation boundary

This note records source mapping and Godot scalar semantics. It does not establish numerical parity, whole-flight equivalence, or a Gate P performance result. Those are measured by the isolated oracle and runner after the extension builds.
