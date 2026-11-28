# Apple Silicon native kernel qualification

DT-MAC-04n1–n4 qualifies the ARM64 implementation of the aircraft evaluator. SF/NK/FL own numerical behavior, admission and replay. DT/PT own Mac delivery and measurement. Each vehicle owner retains physical validation. Use the [native operator guide](research/native-kernel/README.md#experimental-macos-arm64) for build, installation and the supported domain, the [Apple plan](docs/plans/apple-silicon-performance.md) for display and distribution requirements, and the [project roadmap](ROADMAP.md) for priorities.

## Engineering decisions

- Run strict scalar C++ synchronously in the existing process. One flight's stages, event splits and ticks depend on earlier results. Keep immutable coefficients in the prepared stage, mutable scratch per instance, and reconfiguration at accepted boundaries. Preserve the shared [tick transaction](docs/STACK.md#boundaries-and-data-flow).
- Keep platform arithmetic in the math shim. Match the pinned ARM64 engine's operand order, signed zero, NaN selection, subnormal handling, literal rounding and transcendental behavior. Verify effective flags including `-fno-fast-math` and `-ffp-contract=off`, linked instructions and calling-thread FP control state. Use runtime operands and adjacent threshold values to discriminate fused operations, rounding or altered comparisons. Keep the host's floating-point controls intact.
- Consider NEON or Accelerate for measured independent work after scalar parity. Include packing, dispatch, odd tails, aliasing and the complete consumer in comparisons. An M1 odd-tail control detected byte differences in both candidate vector implementations. Metal lacks the double type needed by the authoritative solver. Keep renderer optimization with the renderer owner. [M1 experiments](docs/research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md)
- At setup, a missing identity or unsupported domain can select reference. Once a tick starts, an invalid native answer goes through the existing fault path. A changed identity at an accepted reconfiguration boundary ends exact recording continuity. In-process native memory faults can terminate the app. Preserve sanitizer controls, symbols and bounded diagnostics. [Selection and replay](research/native-kernel/README.md#normal-flight-backend-selection)

## Evidence to renew when inputs change

| Changed input | Required checks |
| --- | --- |
| Compiler, effective FP flags/LTO, SDK, OS/math library or arithmetic | Same-loader float64 transport, FP witnesses and malformed-input oracle on the pinned engine. Exercise at least 10,000 stage comparisons, applicable exact trajectories, fleet and target cost. Keep exclusions such as untested NaN payloads explicit. |
| Engine, extension API or binding precision | Bind exact engine/API, binding commit, toolchain and binary hashes. Check load, affected sessions, restore and replay. Exercise sanitizer positive controls on the identified diagnostic host and the unsanitized production oracle separately. |
| Aircraft, law, domain guard, collision world or identity schema | Recheck affected fleet union, refusal boundaries, accepted and rejected reset/restore, recording interruption, matching exact replay and marked candidate replay. Count native calls and completed ticks. Preserve each terminal/refusal verdict. |
| Artifact slices, signing, stapling, receipt or bundle layout | Trace final bundle and binary identity. Repeat invalidated binary-bound gates, load, signature and replay. Public distribution additionally requires supported downloaded/quarantined, moved and offline Finder routes. Retain the historical receipt. |
| Tape, fixture, collector or reducer | Recheck detector controls and complete matched work, then collect a comparable baseline. Retain failed or partial results with their verdict. |

Same-host exact equivalence, cross-host numerical budgets, physical realism and packaged product behavior each require their own evidence. [Qualification investigations I01–I12](docs/research/native-kernel/apple-silicon-plan-reinforcement-2026-11-12.md)

## Measuring a candidate

Freeze aircraft, tape, weather/contact regime, complete tick count, observers, engine, library, host/OS, display and settings. Predeclare warmup, pair order, practical threshold, uncertainty method, exclusions and maximum extra pairs. Compare the optimized reference to strict scalar ARM64, then change one candidate at a time. Use A/A and observer-on/off controls. Check matching fingerprints and actual native calls before interpreting time.

| Question | Measurement and acceptance |
| --- | --- |
| Did evaluator work get cheaper? | Measure setup/first-use, context/guards, stage and complete production callback separately. Five alternating pairs screen a candidate. Compare per-case paired runs against observer and run variation. The original practical screen was ≥5% complete-session benefit or removal of a named reproducible failure, without unexplained >5% required-case regression. An ambiguous result at the sample cap remains inconclusive. |
| Does the tick meet its budget? | Gate P uses p95 of 120-tick batch averages in specified regimes. Compare to 500 µs and separately report individual whole-tick p50/p95/p99. Keep the applicable workload and statistic with each result. [Gate P method](docs/research/simulation-state/Gate-P/README.md) |
| Does the user see a difference? | Measure matched normal flights, both paced and uncapped. Record actual output/drawable/internal dimensions, frame tails, hitches, unpaused sim/wall ratio (target 0.99–1.01), input/audio and lifecycle. For finalists collect at least three 30-minute trials per role and compare early and final five minutes. Apply the current [display rules](AGENTS.md#display-resolution-priorities). |
| Which resources improved? | Attribute CPU, GPU, queue waits, pressure/swap, retained growth, thermal drift and energy to available instruments. Collect acceptance samples without profiling. Report unavailable counters as unknown. Repeat on another named Apple Silicon host before claiming family-wide benefit. |

## 3. Technical research and references

The [comparables survey](docs/research/native-kernel/apple-silicon-comparables-2026-11-12.md), [twelve portability investigations](docs/research/native-kernel/apple-silicon-plan-reinforcement-2026-11-12.md) and [M1 primitive experiments](docs/research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md) retain source-specific evidence. Primary references include the [Metal language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), [Clang floating-point controls](https://clang.llvm.org/docs/UsersManual.html#controlling-floating-point-behavior), [Arm Advanced SIMD intrinsics](https://developer.arm.com/documentation/101028/0009/Advanced-SIMD--Neon--intrinsics) and [Apple Silicon scheduling guidance](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon).

## 16. Plan-gap and performance audit — 2026-11-13

The [original feasibility assessment and gap audit](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md#16-plan-gap-and-performance-audit--2026-11-13) preserves the initial assessment of `0cdb3cfd2cb4fca6d71cf508555501c153e15f37`, alternatives, six-phase estimate, evidence tables and work order as evaluated at the time. The original three-case campaign recorded a repeatable Extra 300S fixture failure at tick 7,524. Its electric case used ideal supply. See the [source-default ledger](docs/research/native-kernel/DT-MAC-04n4/README.md) for later guarded B5 source adoption (`9386f5e5…`) and the [R10 bundle record](docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md#2026-11-16-owner-directed-native-default) for the subsequent development package. Each qualifies its recorded artifact, host, routes and workload. Current hardware, display, energy and public distribution claims require their own evidence.

Measure memory bandwidth with supported hardware counters or explicitly scoped byte traffic. If the host cannot expose bandwidth, record it as unknown; CPU time, cache misses and resident memory are not substitutes.
