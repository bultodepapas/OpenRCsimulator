# Native fixed-wing review

Source `71306784a250d634854f0c8bab3a927cc46a61b8` on `audit/swarm-physics-fps-2026-11-28`. The production tree was read only. The C++ probes compile the repository's pure numerical headers with GCC 14.2.0, x86-64 Linux, C++17, `-O2 -fno-fast-math -ffp-contract=off`. The results establish component behavior on this compiler. Neither probe runs the admitted GDExtension, a complete tick, or a rendered frame.

## A late guard refusal can change the reference session's mutability

**U-01: conditional admission concern, priority P2 for qualified testing. The outer native result was not executed here.** The NK-6p evidence promises that a refused native stage leaves a writable reference flight. The public `NativeStage.prepare` also describes refusal as leaving the session untouched. Actual order is numeric decode, irreversible freeze of the live session, weather/configuration guard preparation, then success or refusal. The serious distinction is between acceptance by the numeric decoder and acceptance of the complete preparation transaction.

- `app/sim/native_stage.gd:277,378,382,392–399` and `app/sim/native/native_configuration.gd:38–42,119–122,149–169`.
- `research/native-kernel/src/nk_configuration_guard.hpp:62,223–226,453–461` captures the whole prepared aircraft, including top-level fields outside the numeric model. The maximum depth is 32.
- `app/sim/flight_session.gd:812–816` returns to the reference callback if preparation refuses. It does not restore the old containers. Godot cannot make a read-only dictionary writable again.
- `docs/research/native-kernel/NK-6p/README.md:25–28` gives the expected behavior. Its original Good Enemy fix moved the freeze past numeric decode. `app/tests/test_native_frozen_configuration.gd:218–240` checks only the inner GDScript snapshot builder when asserting preparation leaves the reference writable.

The fixture starts with a normal reference Stik 6S, adds 35 levels of supplemental metadata to its public prepared aircraft envelope outside `model`, and compares the entire ordinary and annotated native configuration byte strings. The late guard sees the metadata that the numeric decoder never receives. The expected outcome is a reasoned native refusal, an unchanged reference evaluator and writable aircraft/model/hull. Source order predicts the same refusal with frozen roots. This is a constructed input at a supported session preparation boundary. No ordinary stock flight crash or production write to these fields has been observed.

`prepare_refusal_probe.gd` checks the real snapshot boundary. If a clean sibling session actually installs a qualified native backend, the script checks the outer refusal as well. A missing or stale library leaves that leg explicitly unverified. Run through the project's checked Godot script runner and require `REFUSAL_PROBE_COMPLETED`. The output marker `REFUSAL_NATIVE_UNAVAILABLE` records the reduced coverage. Do not substitute a mocked library or weaken a guard.

A repair should postpone the irreversible change until all refusal-capable validation completes. One option is a preparation-only pass over writable roots, followed by freezing the accepted roots and constructing their per-tick plan without an additional fallible validation phase. Preserve the original live root identities and external aliases on refusal. Verify actual native acceptance and packed-leaf mutation detection, not just a succeeding control callback. Cover the documented fallback after the final guard returns false, including read-only status, callback identity, endpoint, replay backend and subsequent reference progression.

## Polar-enabled strips discard legacy coefficient work

**Priority P2 for a scoped CPU experiment.** `research/native-kernel/src/nk_aero.hpp:798–819` and `app/physics/aero.gd:511–528` compute legacy lift and drag in both ground-effect branches. Each enabled wing polar replaces both coefficients and the blend weight before they are read. The local strip law is reached from `nk_stage.hpp:307–314` and `nk_aero.hpp:956–989`. The Avanti and Extra 300S declare wing-polar data at `app/data/aircraft/sebart_avanti_s_a200.json:1905` and `app/data/aircraft/gp_extra_300s_60.json:1380`. The global-only attached branch can bypass this local work, depending on the state. Applicable stage counts must be measured on the target scenario.

The disposable candidate changes branch selection only. Every retained operand and reduction remains in its original order. It preserves the ground-effect correction to the base and the wing-flow weights that feed neighboring stations. On a synthetic six-strip model, 320 calls covered positive and negative streamwise speed, near zero, signed zero, quiet NaN, flaps, stall, ground effect and a disabled-polar control.

| Group | Cases | Baseline/candidate calls to pow | Baseline/candidate calls to sin |
| --- | ---: | ---: | ---: |
| Polar enabled | 160 | 3,872 / 1,952 | 3,546 / 1,768 |
| Polar disabled | 160 | 3,080 / 3,080 | 3,042 / 3,042 |

All 1,920 load components matched bit for bit, with identical `errno` and recorded floating-point exception masks for every case. The GNU linker counted calls to the emitted `pow` and `sin` symbols. Other trig symbols were outside the counter's definition. This identifies 12 discarded powers for one six-strip local evaluation on this compiler. It measures neither tick duration nor FPS. A33's original overwritten calculation concerns legacy datum air before spatial wind, at `external Audits/cpu-mathematical-optimization-2026-11-09.md:270–276`. The optimization plan's coupled-flap candidate concerns repeated station stall weights inside an inner reduction. Both are different sites.

For adoption, compare the admitted native stage oracle and deliberate mutant, reference/native flight and exact replay on the matched qualified build. Use Avanti flap extension, ground effect, high angles, reverse flow and ordinary trim control. Count actual local invocations on a frozen 240 Hz production flight and compare the full workload on target hardware before attributing frame impact.

## A family stage copies its disposable derivative vector

**Priority P3.** Both `glow_stage_finish` and `liquid_stage_finish` build an owned derivative vector. `nk_stage.hpp:365,370,415,421` makes the result const, copies its derivative into the outer result, and returns immediately after consuming the remaining fields. The disposable candidate transfers ownership with `std::move` from a nonconst local. Each RK trial retains exclusive ownership. The stage, publication and observer interfaces stay the same.

An allocation counter around the current `stage_evaluate` and its candidate used synthetic finite-liquid turbine fixtures. The actual production function is reached by `nk_kernel.cpp:3117–3122,3532–3535,3571–3583`. Eight accepted cases matched their loads, continuous and body derivatives, rotor momentum and shape. Ten invalid-capacity or out-of-range RPM cases both refused with matching shapes and allocation counts. A warmed three-wheel accepted call made 3 versus 2 scalar allocations, requesting 120 versus 72 bytes. A zero-wheel accepted call made 2 versus 1 allocations, requesting 48 versus 24 bytes. For a three-wheel path doing exactly four evaluations at 240 Hz this corresponds to 960 avoided allocations and 46,080 fewer requested bytes per simulated second. This is allocation traffic. Retained memory, allocator latency, whole-tick duration and FPS remain unmeasured. Glow shares the copy site but is not exercised by this fixture.

This change retains the existing ownership boundary and gives a smaller hypothesis than a shared scratch allocator. Gate a production change on actual hardware allocation or frame attribution, product parity/negative controls and fault/restore behavior, especially while a preview or resource event is active. A historical plan explicitly deprioritized broad buffer-reuse changes without evidence.

## Reproduction

From the repository root:

```bash
python3 research/swarm-audit-2026-11-28/probes/polar_probe.py .
python3 research/swarm-audit-2026-11-28/probes/derivative_probe.py .
python3 research/swarm-audit-2026-11-28/run_probes.py --godot .tools/Godot_v4.8-beta2_linux.x86_64 --case native-refusal
```

The comparison scripts create and remove temporary candidate headers and executables. Machine-readable results are in the audit's `evidence/native-polar.json` and `evidence/native-derivative.json`. The checked refusal run established captured metadata and identical numeric configuration bytes while the root was writable. Its positive native control then printed `REFUSAL_NATIVE_UNAVAILABLE native stage library not installed`. The outer freeze-after-refusal result is unverified.

See the [reproduction guide](../../../../research/swarm-audit-2026-11-28/README.md) for full controls and compiler restrictions. No production source-receipt or toolchain restriction was bypassed.
