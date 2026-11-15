# R22 — Profile the complete flight before changing its hot path

**Decision:** integrate the measurement plan and reuse existing diagnostics; prototype optimizations only after attribution. **Priority:** P2. **Baseline:** audit app tree `565e4a839e63c1b65064d0da4e6e1366b13ebbc7`. No runtime speed improvement is measured or claimed in this investigation.

## Repository capability and suspected costs

The repository already has substantial diagnostics. `tools/debug/README.md` documents `frames`, `timeline`, `profile`, `objects`, `soak`, rendering timestamps and controlled layer ablation. `tools/godot/perfetto_export.py` exports existing frame/resource evidence with identity and clock-alignment checks; `tools/godtest` has startup, flight, pause and lifecycle phases. `app/main.gd::_log_frame_time` records monotonic frame intervals separately from Godot's engine delta. A new profiler wrapper that duplicates these capabilities would create maintenance work without answering the question.

Source inspection supplies candidates, not timing conclusions: controller snapshot dictionary construction; temporary arrays/dictionaries around fixed-wing evaluations and integration stages; observer copying; and repeated data/geometry work on reset versus steady flight. Their call frequency, allocation cost and contribution to rendered hitches must be measured separately. In particular, observer and capture modes can alter the workload. A low-level force evaluator benchmark cannot establish total flight improvement.

## External research

Godot's profiler distinguishes frame, idle and physics costs and has its own overhead ([LEAD-S08](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/the_profiler.html)). Its optimization guidance separates recurring work, intermittent stalls and loading, and warns that CPU-only views can miss GPU or operating-system effects ([LEAD-S09](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)). Those distinctions map directly to this simulator's startup, steady flight and observer/capture paths.

Godot documents both sampling and tracing profilers: sampling estimates active functions, while a trace contains only instrumented events. Useful native attribution needs an appropriate symbol-bearing build, and tracing integration may require an engine build ([LEAD-S10](https://docs.godotengine.org/en/stable/engine_details/development/profiling/index.html)). These rolling stable docs are not proof that every option is present in this project's pinned 4.8 beta 2 binary. Verify the exact engine revision and build flags before using instructions, and retain build identity with results.

## Ordered experiment

1. Freeze source, accepted aircraft bytes, engine/build, graphics settings, controller tape, seed, field and power-source mode. Run Basic, Electric in ordinary pack mode and one comparison aircraft through the same defined phases; keep ideal-electric research separate.
2. Use the existing wall-clock frame stream for repeated unprofiled captures at 1920×1080 on named target hardware. Report warmup, duration, measured phase coverage, p50/p95/p99, maximum, hitch counts, simulation tick progress and resource sampling coverage. Add 1440p/4K only after the primary question; use 720p only for an identified resolution hypothesis.
3. Repeat the relevant phase with existing script profiling, frame/timeline diagnostics and object baselines. Treat the added observation cost as a perturbation. Correlate events only within the clock-alignment accuracy the evidence actually supports.
4. If native work remains unattributed, use a symbol-bearing matched engine and appropriate host sampling tool; add Tracy/Perfetto engine instrumentation only when the unresolved question needs it. Keep runtime dependency adoption separate from offline inspection.
5. Change one identified cost. A scratch-buffer reuse candidate must retain ownership boundaries and avoid aliasing accepted states or RK stages. A cached geometry candidate needs immutable keys and invalidation on model change. Input allocation work must preserve observation freshness and device-generation semantics.
6. Verify exact same-build input-tape replay and the relevant numerical contracts, then repeat unprofiled whole-flight measurements. Keep failed, partial and slow runs. State uncertainty and include the unaffected comparison aircraft, not only the case that improves.

## Alternatives and acceptance

Moving the kernel into C++ before attribution could optimize a minor contributor while increasing integration and precision risk. Blindly dropping simulation frequency could change stability and control response. Increasing observer batching could hide hitches instead of removing them. The preferred first integration is a reproducible recipe using existing tools, followed by one measured candidate.

Acceptance requires a located cost, a stated hypothesis, a repeatable reduction in the relevant target-hardware metric, no unacceptable tail-latency or memory regression, unchanged accepted input/replay behavior where intended, and separate numerical acceptance when arithmetic order changes. The independent benchmark investigation R24 supplies the statistical design; R15 supplies timing/replay constraints. No headless or software-renderer observation here is promoted to a consumer GPU performance claim.
