# NK-4 — Windows native kernel

2026-11-12. Windows 11 x86_64, pinned Godot 4.8-beta2 (`Godot_v4.8-beta2_win64*.exe`), MinGW-w64 GCC 15.2.0
(`x86_64-w64-mingw32`, msvcrt runtime), RTX 3090 host shared with other sessions. Follows [NK-3](../NK-3/README.md)
and the [Windows design note](../../../../research/native-kernel/README.md#windows-build-nk-4).
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
from current sources (WSL Ubuntu, pinned g++ 13.3.0, pinned Linux editor) passed all 19 installer gates and was
reinstalled with `build.py --install-app`; `test_native_stage.gd` then passed 97/97 with `NK3_NATIVE_STAGE_NATIVE
verdict=pass`.

## Qualification

Final Windows binary `b958cc3f…`, final harness (including the Windows loader), every `build.py` installer gate
with its exact arguments, run serially through `run.py`; `build_windows.py --install-app` re-validated each
result against binary, sources, harness and engine before installing.

| Gate | Compared | Identical |
| --- | ---: | ---: |
| Component oracle (`oracle.gd`) | 593,941 | 593,941 |
| Stage (12,000 states) | 128,664 | 128,664 |
| Trajectory (5 cases × 960 ticks, checkpoints, faults) | 21,771 | 21,771 |
| Propeller, electric, liquid, glow | 50,310 / 32,010 / 15,572 / 49,606 | all |
| Wake, spatial wake, gear, weather, helicopter | 19,138 / 20,347 / 35,452 / 21,549 / 50,336 | all |
| Electric, liquid, glow, helicopter, weather, prescribed stages; legacy ground | 66,988 / 64,136 / 79,881 / 61,281 / 59,340 / 49,571 / 14,806 | all |
| Negative control (mutant, must fail) | 128,664 | 100,349 (fails as required) |

Linux (WSL) passed the same 19 gates with its own binary. Before the `sqrt` fix, Windows electric (3 of 32,010),
wake (3 of 19,138) and glow stage (4 of 79,881) differed by 1–2 ulp; Linux passed them, which isolated the
Windows-only cause. An exact-case probe with a diagnostic build (`--define NK_DEBUG_ECM`) traced the battery heat
transfer difference to `sqrt`, and the disassembly showed 188 out-of-line libmingwex calls using x87 `fsqrt`.

Production checks on Windows with the installed library: `test_native_stage` 97/97, `test_native_session` 343/343
(`NK3_NATIVE_SESSION_NATIVE verdict=pass`), `test_native_replay` 170/170, `test_native_helicopter_session` 399/399
(`native exercised=true`), `test_heli_restore_radio` 80/80, `test_native_helicopter_route` 21/21. The debug-bridge
app selected `backend: native` for a P-51 flight and exited without leaks. The companion re-bind report replayed
all nine qualification tapes byte-identically (2,881 rows each) with the new solver identity.

## Measured cost

Session timing from `trajectory.gd` (`only=timing`, 3 alternating pairs × 4,800 samples, debug editor binary,
shared host under load):

| Case | Reference median µs/tick | Native median µs/tick | Speedup | p95 reference → native |
| --- | ---: | ---: | ---: | ---: |
| Runway/ground | 2,064 | 766 | 2.7× | 2,720 → 877 |
| Trim | 998 | 426 | 2.3× | 1,298 → 577 |
| Manoeuvre | 878 | 311 | 2.8× | 1,148 → 514 |

Ground-slide session tick (CR-22e harness, Ugly Stik belly slide, 480 manual ticks, headless, same start state):
reference 2,022–2,215 µs median, native 1,255–1,371 µs with 1,921 native stage calls; the final state hash is
identical for both backends. The remaining cost is the session transaction, collision and presentation
observers, which stay in GDScript under the kernel contract.

## Integration

- `app/sim/native_stage.gd` admits Windows x86_64 source/debug processes with the same checks as Linux: exact
  verified executable hash, exact descriptor, binary hash and every mirrored source. Windows uses its own
  `openrc_native_kernel_windows.gdextension` and `build-receipt-windows.json`, beside (never over) the Linux files.
  Release packages remain Linux-only.
- `research/native-kernel/build_windows.py` builds (and `--mutant`), and `--install-app` installs only with fresh
  passing evidence for every installer gate, using `build.py`'s `verification_error`. Diagnostic `--define` builds
  are refused. `run.py`/`build.py` accept `OPENRC_NK_TOOL_ROOT` to keep the toolchain off a full system drive.

Independent review hardening (before the final qualification run):

- Oracle evidence binds the GUI executable that actually runs (`run.py` hashes it before and after; the console
  wrapper only starts it), the engine label, and every named harness file, as Linux does.
- `build_windows.py` refuses an unpinned toolchain: target `x86_64-w64-mingw32`, g++ 15.2.0, mingw-w64 runtime
  11.0.1. Its default tool root (`tmp/native-kernel-windows`) no longer overlaps the Linux build's.
- Installation removes a cached registration of the Windows descriptor from `.godot/extension_list.cfg`.
- `run.py --app-library` reads the platform's own installed descriptor and receipt.

## Open

- Re-record the installation under the hardened evidence rules. Two later full gate runs again passed every gate
  with the same binary (`b958cc3f…`), but another track edited `tools/godot/run_checked.py` (part of the oracle
  harness) during both, so `--install-app` correctly refused the mixed evidence. The installed receipt still holds
  the first complete run; the loader's runtime checks (binary, executable, descriptor, mirrored sources) pass, and
  `test_native_stage` passes 97/97 natively. Once that file is stable, rerun the gates and `--install-app`.

- Signaling-NaN inputs: inline `sqrtsd` quiets them; the engine's path may not. Ordinary arithmetic produces only
  quiet NaNs, so this is reachable only by injected bit patterns; it is not covered by the oracles.

- Windows release packages (export plugin, embedded manifest), a Windows CI job and target-host timing with the
  release template. Source/debug runs on this host only.
- Companion solver pin: `native_stage.gd` is in the pinned solver directories. The report is identical; after
  committing, run `python tools/companions/rebind.py --accept` (`test_companions_profiles.gd` fails until then).
- Fleet campaign (`fleet_campaign.py`, 1,238 cases) was not rerun on Windows; admission is capability-based and
  every family oracle passed.
