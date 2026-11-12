# NK-4 — Windows native kernel

2026-11-12. Windows 11 x86_64, pinned Godot 4.8-beta2 (`Godot_v4.8-beta2_win64*.exe`), MinGW-w64 GCC 15.2.0
(`x86_64-w64-mingw32`, msvcrt runtime), RTX 3090 host shared with other sessions. Follows [NK-3](../NK-3/README.md)
and the [Windows design note](../../../../research/native-kernel/README.md#windows-design-note-not-built).
Motivation: [CR-22e](../../crash-damage-investigations/CR-22e/README.md) traced low frame rates in ground contact to
the GDScript reference solver at 240 Hz (2.4–10 ms per contact tick on Windows), where only Linux had the native stage.

## Root causes of non-identity, and their fixes

The design note's preferred route (MinGW-w64 GCC, like the official Godot Windows binaries) links the same math
library family as the engine. Measured on this host:

- The engine resolves `acos asin atan ceil cosh log10 sinh tan tanh _nextafter` from `msvcrt.dll`; `sin cos pow exp
  log atan2 fmod` are statically linked libmingwex code. The extension built with GCC 15.2 has the same split.
  Engine-vs-extension probes found 0 bit differences in 200,324 rows × 16 functions, 200,000 `pow` calls at
  special exponents, 4,000,000 `exp`/`log` calls and 1,000,000 compound arithmetic expressions.
- **`sincos` fusion.** GCC fuses `sin(x)`/`cos(x)` of one argument into libmingwex `sincos()`, which returns the
  hardware default `-NaN` for an infinite argument where separate `sin`/`cos` (as GDScript evaluates them) return
  `+NaN`. Fix: `-fno-builtin-sin -fno-builtin-cos` (also stops compile-time folding of a transcendental of a literal).
- **`lerp` operand order.** The Windows engine binary evaluates Godot's lerp as `(to - from) * weight + from`
  (two-NaN priority), not the Linux binary's `weight * (to - from) + from`. Finite results are identical. Fix:
  `NK_ENGINE_LERP_SOURCE_ORDER` selects that order in `nk_math.hpp`.
- **x87 `sqrt`.** MinGW-w64 GCC called libmingwex `sqrt` out of line at 188 sites; it uses x87 `fsqrt` (extended
  precision, then a second rounding), occasionally 1 ulp from the correctly rounded value the engine returns
  (reproduced: battery heat transfer `sqrt(6.638…)` = `…bac6` vs `…bac7`). Fix: `NK_ENGINE_SQRT_SSE2` makes `sqrt_`
  the SSE2 `sqrtsd` instruction.

All three switches are passed only by `build_windows.py`; the Linux translation unit preprocesses unchanged.
The engine's own two-NaN and NaN-sign behaviour is now matched bit for bit, so D3's NaN-class tolerance tier is
not needed on Windows.

## Stale installed Linux library (found on the way)

The installed Linux receipt (2026-11-08, `7ba15229e`) no longer matched 11 of its 135 mirrored sources
(`aero.gd` separated-force offset and stall progression, `glow/flight.gd` FUEL-12-R5, `wing_polar.gd`, data files,
`simulation.gd`, …). The C++ sources had been updated, but the library was not rebuilt or reinstalled, so the
loader refused native on Linux and normal flight fell back to the reference there too. A fresh Linux build
from current sources (WSL Ubuntu, pinned g++ 13.3.0) passes the electric oracle 32,010/32,010; see the Linux
requalification below.

## Qualification (Windows)

<!-- filled from the final gate run -->

## Measured cost

Session timing from `trajectory.gd` (`only=timing`, 3 alternating pairs × 4,800 samples, debug editor binary,
shared host under load):

| Case | Reference median µs/tick | Native median µs/tick | Speedup | p95 reference → native |
| --- | ---: | ---: | ---: | ---: |
| Runway/ground | 2,064 | 766 | 2.7× | 2,720 → 877 |
| Trim | 998 | 426 | 2.3× | 1,298 → 577 |
| Manoeuvre | 878 | 311 | 2.8× | 1,148 → 514 |

## Integration

- `app/sim/native_stage.gd` admits Windows x86_64 source/debug processes with the same checks as Linux: exact
  verified executable hash, exact descriptor, binary hash and every mirrored source. Windows uses its own
  `openrc_native_kernel_windows.gdextension` and `build-receipt-windows.json`, beside (never over) the Linux files.
  Release packages remain Linux-only.
- `research/native-kernel/build_windows.py` builds (and `--mutant`), and `--install-app` installs only with fresh
  passing evidence for every installer gate, using `build.py`'s `verification_error`. Diagnostic `--define` builds
  are refused. `run.py`/`build.py` accept `OPENRC_NK_TOOL_ROOT` to keep the toolchain off a full system drive.

## Open

- Windows release packages (export plugin, embedded manifest) and CI.
- Companion solver pin: `native_stage.gd` is in the pinned solver directories; run
  `python tools/companions/rebind.py` and, after committing, `--accept`.
