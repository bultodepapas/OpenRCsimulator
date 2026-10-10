# M5-W04a: float64 turbulence kernel

2026-10-09 · **Status: implemented and software verified.** Scope: a pure, three-axis NED Ornstein–Uhlenbeck sampler. This does not establish atmospheric or pilot validity.

## Method

For each world-NED component, `initial` draws the stationary state `x = sigma · z`. Each fixed-step update uses the exact discrete transition for a stationary OU process:

```text
a = exp(-dt / tau)
x_next = a · x + sigma · sqrt(max(0, 1 - a²)) · z
```

The clamp handles roundoff if `a²` rounds just above one. `sigma` is the per-axis stationary standard deviation in m/s; `tau` is the correlation time in seconds. State and math use `PackedFloat64Array` and the project’s float64 `Math3d` helpers. Zero-sigma axes have exactly zero innovation and consume no random words; an all-zero vector consumes none.

Independent standard normals come from Box–Muller. A private `RandomNumberGenerator` supplies raw `randi()` words; their high 27 and 26 bits form a 53-bit midpoint uniform in `(0, 1)`. The rare top midpoint that rounds to `1.0` in binary64 is clamped to the greatest representable value below one. No normal cache or mutable static state is kept. Each call sets the seed, restores the caller’s signed-int64 state before drawing, and returns the advanced state. Replay therefore depends on the pinned engine RNG implementation and its draw order.

Godot 4.7.2’s `RandomNumberGenerator` delegates to `RandomPCG`: setting `seed` runs PCG’s seeded initialization; `randi()` returns the raw 32-bit generator output; `state` is the raw 64-bit PCG state exposed through signed `int64`. Godot passes the default PCG sequence input `1442695040888963407` to `pcg32_srandom_r`, which transforms it to the recurrence increment `(sequence << 1) | 1 = 2885390081777926815`. The node constructor randomizes, so this kernel always overwrites the seed and, for continuation, the state before the first draw. Godot documents the algorithm as an implementation detail; cross-version sequence identity is not promised.

## Verification

Pinned Godot `4.7.2.stable.official.ed1daf0bf` ran `app/tests/test_wind_turbulence.gd`: **29 checks, 0 failures**. The test covers known answers, zero-noise decay, seed/state validation, signed-state continuation, checkpoint replay, independence from unrelated calls, and three fixed 20,000-step streams. For the statistical runs (`dt = 0.02 s`, `tau = 0.5 s`, `sigma = 1 m/s`), each axis checks mean within `0.12 sigma`, RMS within 8%, and lag-one correlation within `0.015` of `exp(-0.04)`. Cross-axis sample covariances stay within `0.07`; the wider bound accounts for temporal correlation in these finite streams.

These are implementation checks on synthetic Gaussian streams. They do not validate a weather spectrum, atmospheric turbulence model, flight response, or pilot perception.

The independent Python trace reader verifies v4 compatibility and v5 OU replay, including the tick-zero seeded initialization, 53-bit normal draws, signed raw state, midflight interval, exact-zero RMS axes, current/force-time wind, and both TAS columns. Its 9 real-engine CLI tests passed on Godot 4.7.2: all four flyable aircraft, a partial-sigma v2 config (`tau = 0.7 s`, seed `4294967295`), a v2 all-zero-RMS v4 trace, malformed-state/config/gap mutations, and a 480-tick full-checkpoint SHA-256 identical at 30, 60, and 144 render FPS (`2b924c3462106172f4669b6fb1fd5b56c9c204bbaa7a4bdcbf1abbfeb86af36b`). The trace tolerances account for nine-decimal CSV output; these checks verify implementation and replay only.

## Primary sources

- [Godot 4.7 `RandomNumberGenerator` docs](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html): PCG32 note and warning that the implementation is not a stable contract.
- [Godot 4.7.2 `random_number_generator.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_number_generator.h): seed/state accessors and raw `randi()` binding.
- [Godot 4.7.2 `random_pcg.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_pcg.h) and [`random_pcg.cpp`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_pcg.cpp): seed initialization, state access, and raw PCG output.
- [Godot 4.7.2 `pcg.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/misc/pcg.h) and [`pcg.cpp`](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/misc/pcg.cpp): default sequence input, recurrence increment transformation, and PCG32 state/output transition.
