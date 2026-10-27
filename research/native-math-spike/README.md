# NK-1 math identity spike — Linux (2026-10-27)

Step NK-1 of the [native-kernel scoping](../../docs/research/native-kernel-scoping-2026-10-27.md#determinism-and-goldens);
research only (nothing goes into `app/native`; build outputs stay in the ignored `tmp/native-math-spike/`).

**Question.** On Linux x86_64, does elementary math in a GDExtension return the same bits as GDScript, through
(a) `std::` `<cmath>` and (b) godot-cpp `UtilityFunctions`, and what does each call cost? **Answer on this host:**
yes for all 16 functions over 10⁶ random plus edge inputs each; no finite result differs on either route. The only
mismatches come from code, not libm: `std::asin`/`std::acos` return NaN for |x| > 1 where the engine clamps; GCC
folds a literal `pow(x, 2.0)` to `x * x` (850 of 10⁶ differ by 1 ulp); GDScript's `-0.0` literal is +0.0.

## Method

- **Inputs.** C++ SplitMix64 (seed 20261027, one stream per function) fills a `PackedFloat64Array`; both sides
  evaluate that array (SHA-256 per input in the JSON). Ranges: sin/cos/tan U(±4π); asin/acos U(−1, 1); atan U(±10);
  atan2 y, x U(±50); sqrt U(0, 10⁴); pow base U(0, 2), exponent 70 % U(0, 4) and 30 % {1/1.4, 0.2857142857, 3.5};
  exp U(±30); log 2^U(±40); sinh/cosh/tanh U(±20); fmod x U(±100), y 2π or U(0.5, 10); floor U(±10⁶).
- **Edges.** Unary (137): ±0, ±subnormal, ±1e-300, ±1e-16, ±0.5, ±1, ±(1 + ulp), ±2, ±1e22, ±1e300, ±DBL_MAX, ±∞,
  ±NaN, exp overflow/underflow thresholds, k·π/2 (k = −16…16) with both neighbours, others in
  [the source](src/math_spike.cpp). Binary (256): 16 × 16 grid of {±0, ±1, 0.5, ±2, 3, 1e±300, ±∞, NaN, π/2, 2π, 1024}.
- **Reference.** The GDScript builtin in a typed loop (`floorf` for floor). The `math3d` column runs the loop
  through `const M := preload("res://physics/math3d.gd")` as app code does (it has no fmod/floor wrappers).
- **Comparison.** Bitwise; differences are classed as finite (ulp distance), ±0 only, NaN payload only, or NaN/∞
  class mismatch. A one-ulp and a sign-of-zero mutation must be detected first; GDScript cross-checks byte equality.
- **Cost.** Warm-up, then median of 5 passes, ns per element including the loop (`copy`); GDScript in the editor
  (debug VM). A second full run gave identical counts and hashes, timings within ~10 % (Utility `exp` 8.1 → 14.1).

## Toolchain and identity

Pins mirror [the truck lock](../rc-monster-truck/native/toolchain-lock.json); `build.py` reuses the [slipstream builder](../native-slipstream/build.py).

| Item | Value |
| --- | --- |
| Host | Ubuntu 24.04.4, Intel i5-10500 (AVX2, FMA), glibc 2.39 (compile and run), `/lib/x86_64-linux-gnu/libm.so.6` |
| Godot | 4.8.beta1.official.4d10419ca editor `28485fbd0e4cda4c503c5f3227d9b296fd5b1b4398f9fb00e9a6d72544b55e82` |
| godot-cpp | 10.0.0-stable `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, API 4.7, profile {OS, RefCounted} `b2dd680a…` |
| SCons | 4.10.1 wheel `bd9d1c52f908d874eba92a8c0c0a8dcf2ed9f3b88ab956d0fce1da479c4e7126` |
| Compiler | g++ 13.3.0, `template_release` (`-O3 -march=x86-64`) + `-fno-fast-math -ffp-contract=off -fexceptions` |
| FP state | `FLT_EVAL_METHOD` 0, no `__FP_FAST_FMA`, `math_errhandling` 3, round-to-nearest, MXCSR 0x1fb0 (no FTZ/DAZ) |
| Library | `libopenrc_math_spike.so` `b9567325b09596eaec8a894f5e109a3884fd4334c3d36a546a34881280c3c6ba` |
| Inputs | source `24aeb3dd…`, lock `17cf097b…`, `math3d.gd` `0900f64c…`, `spike.gd` `b9ffe3e7…` (full in JSON) |

`objdump -T`: the extension imports the trigonometric and hyperbolic functions and `sincos` `@GLIBC_2.2.5`,
exp/log/pow `@GLIBC_2.29` and fmod `@GLIBC_2.38`; sqrt and floor are inline. The editor and the 4.8-beta1
`linux_release.x86_64` template import the same versions for every shared symbol and inline sqrt, fmod and floor
(exact operations). Both sides therefore run the same glibc code inside one process.

## Results

Full data: [results-linux-2026-10-27.json](results-linux-2026-10-27.json) (second run). Cells are identical/total.

| Function | Inputs (random + edge) | GDScript = `std::` | GDScript = `UtilityFunctions` | GDScript = `math3d` | ns GD direct | ns GD `math3d` | ns `std::` | ns Utility |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| copy | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 24.2 | 27.7 | 0.9 | 1.0 |
| sin | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 57.1 | 120.7 | 16.5 | 21.4 |
| cos | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 54.8 | 128.9 | 16.8 | 20.0 |
| tan | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 58.9 | 123.4 | 17.0 | 21.6 |
| asin | 1000000 + 137 | 1000020/1000137 (117 NaN/inf class) | 1000137/1000137 | 1000137/1000137 | 52.5 | 146.0 | 15.0 | 19.8 |
| acos | 1000000 + 137 | 1000020/1000137 (117 NaN/inf class) | 1000137/1000137 | 1000137/1000137 | 53.6 | 118.4 | 14.6 | 21.6 |
| atan | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 59.4 | 123.2 | 13.8 | 15.2 |
| atan2 | 1000000 + 256 | 1000256/1000256 | 1000256/1000256 | 1000256/1000256 | 80.2 | 159.6 | 24.6 | 31.0 |
| sqrt | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 38.0 | 98.4 | 1.8 | 3.7 |
| pow | 1000000 + 256 | 1000256/1000256 | 1000256/1000256 | 1000256/1000256 | 69.1 | 144.7 | 17.1 | 21.4 |
| exp | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 39.7 | 103.5 | 5.2 | 14.1 |
| log | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 42.8 | 111.9 | 4.6 | 8.3 |
| sinh | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 70.1 | 136.8 | 21.5 | 26.3 |
| cosh | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 48.0 | 104.3 | 7.1 | 13.1 |
| tanh | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | 1000137/1000137 | 69.4 | 139.4 | 18.2 | 25.7 |
| fmod | 1000000 + 256 | 1000256/1000256 | 1000256/1000256 | — | 53.1 | — | 7.1 | 9.6 |
| floor | 1000000 + 137 | 1000137/1000137 | 1000137/1000137 | — | 33.0 | — | 1.8 | 3.7 |

Max ulp difference is 0 on every row. The 117 asin/acos mismatches are exactly the edge inputs with |x| > 1 (1 + ulp:
GDScript π/2 or 0, `std::` NaN): the engine clamps; `math3d.asin_` clamps first to the same bits. Net of `copy`, a
GDScript builtin costs 9–56 ns, a `math3d.gd` call 70–130 ns, `std::` 1–24 ns, and Utility adds 1–9 ns over `std::`.

| Compiler-rewrite probe (`std::`) | GDScript reference | Identical |
| --- | --- | --- |
| explicit `sincos`, sin half | `sin(x)` | 1000137/1000137 |
| explicit `sincos`, cos half | `cos(x)` | 1000137/1000137 |
| `pow(x, 2.0)` literal → `mulsd` | `pow(x, 2.0)` | 999406/1000256 (850 finite, max 1 ulp) |
| `pow(x, 0.5)` literal | `pow(x, 0.5)` | 1000256/1000256 |
| `pow(x, 3.5)` literal | `pow(x, 3.5)` | 1000256/1000256 |
| `pow(x, 1.0 / 1.4)` literal | `pow(x, 1.0 / 1.4)` | 1000256/1000256 |

Under the pinned flags GCC 13 fuses `sin(v)` and `cos(v)` of one value into `sincos` (objdump); glibc keeps it
identical. GCC folds `pow(x, 2.0)` to `x * x`, `pow(x, -1.0)` to `1.0 / x` and `pow(x, 1.0)` to `x`; the correctly
rounded product differs from glibc `pow` in 0.085 % of cases. `-fno-builtin-pow` keeps the libm call (objdump
only). GDScript `var z := -0.0` stores `0x0000000000000000`; runtime `-zero` gives `0x8000000000000000`.

## Interpretation for NK-3

1. On Linux with the pinned toolchain both routes keep native/GDScript bit identity: `std::` because extension and
   engine call the same glibc symbols in one process, `UtilityFunctions` because it is the function GDScript
   calls. `std::` is cheaper by 1–9 ns per call.
2. Route every kernel transcendental through one native shim, the C++ twin of `math3d.gd`, never raw `std::`. It
   must reproduce the engine clamps (`asin` ±π/2, `acos` 0 or π beyond ±1; `math3d.acos_` itself does not clamp)
   and keep `pow` exponents out of constant folding (`-fno-builtin-pow` or runtime exponents): `rg` finds 23
   literal `pow(…, 2)` calls in `app/physics`. Port GDScript `-0.0` literals as +0.0.
3. Keep `UtilityFunctions` as the shim's backend for Windows (MSVC CRT vs the MinGW engine) and macOS: it matches
   GDScript by construction at 1–9 ns per call here, unverified off Linux.
4. This supports exact native-vs-reference fingerprints on Linux. It says nothing about cross-host goldens: glibc
   picks FMA/AVX2 variants per CPU, and the two backends share that choice only within one process.

## Limitations

- Linux x86_64 only (one CPU, glibc 2.39, GCC 13.3); Windows and macOS untested, so NK-1 still needs a Windows host.
  GDScript costs are debug-VM (release ×1.2 per tick in VQ-01c) on a shared VM (±10 %); dependent-chain latency,
  GDScript→extension call overhead and `asinh`/`acosh`/`atanh` were not measured.

## Reproduce

The [`.gdextension`](project/openrc_math_spike.gdextension) loads `../../../tmp/native-math-spike/lib/` relative to
the project; sources are [src/math_spike.cpp](src/math_spike.cpp) and [project/spike.gd](project/spike.gd).

```bash
python3 research/native-math-spike/build.py --jobs 4  # pinned SCons + godot-cpp under tmp/native-math-spike/
python3 research/native-math-spike/run.py             # copies math3d.gd to project/physics/ (ignored) and runs
#   tools/godot/run_checked.py -- <godot> --headless --path research/native-math-spike/project --script res://spike.gd
python3 research/native-math-spike/run.py --render research/native-math-spike/results-linux-2026-10-27.json
```
