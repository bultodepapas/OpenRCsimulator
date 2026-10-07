# 11 — ARM64 physics accuracy and the 240 Hz budget

2026-10-07 · DT-00-R2 · **Code and primary-source research; no ARM64 numerical or timing result.**

## Question

Does an ARM64 Godot executable preserve this simulator's numerical contract, and can an M1 sustain it alongside graphics? Architecture compatibility, numerical agreement and timing are three separate acceptance results.

## Existing foundations and limits

| Audited foundation | Consequence on Apple Silicon |
| --- | --- |
| `app/sim/` and `app/physics/` use GDScript scalar floats and packed float64 state; `app/test.sh` guards float32 math types | Preserve this boundary; ARM64 does not require rewriting simulation state using rendering vectors |
| `app/tests/replay_policy.gd` fixes per-component error limits and stamps OS, CPU, architecture, engine and build | Apply the same policy to native Mac results; recorded metadata cannot widen acceptance |
| `research/native-slipstream/` is an isolated C++ experiment; production remains GDScript | A faster Linux experiment is not a shipped Mac dependency or an ARM64 performance result |
| Experimental Mac compiler/SDK recipes are pinned but explicitly unbuilt/unrun | Verify availability, effective flags and deployment target on the actual Mac before adoption |
| `bench_physics.gd` reports the best of three mean tick costs | Useful local diagnostic, insufficient evidence for tail cost or sustained M1 thermal behavior |
| Project uses 240 physics ticks/s and at most 12 catch-up steps/frame | Arithmetic scheduling floor is 20 frames/s; practical headroom and the 60 Hz delivery target remain separate |

Godot's scalar `float` is 64-bit, while many built-in vector types use 32-bit components in ordinary builds. A whole-engine double-precision build changes the GDExtension ABI and requires compatible libraries; it is unnecessary to preserve this project's existing scalar-double design. [Float](https://docs.godotengine.org/en/4.7/classes/class_float.html), [large world coordinates and compatibility](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html).

Apple documents architecture-dependent floating-point-to-integer edge cases. Keep nonfinite/range checks at input and trace boundaries; neither an ARM64 label nor an identical source tree proves cross-platform floating-point equality. [Apple architecture differences](https://developer.apple.com/documentation/apple-silicon/addressing-architectural-differences-in-your-macos-code).

Clang can fuse multiply/add and reassociate arithmetic under different compiler flags. The isolated native build appends `-fno-fast-math`, `-ffp-contract=off` and Mac `-ffp-model=strict`. Record the actual final compile commands: these flags constrain the extension, not the already compiled official Godot engine or system math library. They do not promise bit-identical transcendental results across OSes. [Clang floating-point controls](https://clang.llvm.org/docs/UsersManual.html#controlling-floating-point-behavior).

## ARM64 comparison contract

Retain [H9's policy](../../simulation-state/H9/README.md) and read its live implementation when freezing the candidate. Current absolute limits: position/velocity/body-rate/anchor components `1e-6` in their documented units, quaternion/servo/downwash `1e-9`, rpm `1e-5`; discrete mode/tick/timestep comparisons remain exact. These are numerical regression budgets, not aircraft-model validation tolerances.

1. Use one frozen source/data set and pinned Godot release; record native process architecture for Linux reference and Mac candidate. Run the existing golden/replay, float64, nonfinite and branch-boundary checks.
2. Publish maximum error and worst checkpoint per component, with mode/tick differences, rather than one aggregate pass. Include all offered aircraft and ground/stall/spin regimes covered by existing tests.
3. Keep same-platform exact fingerprints as refactor diagnostics. Do not regenerate the Mac goldens or loosen tolerances merely to obtain a green job; investigate whether failure is serialization, different source inputs, math-library behavior or a genuine defect.
4. If the native experiment is reconsidered, compare Mac GDScript versus Mac C++ first, then compare cross-platform outputs. Preserve invalid-input refusal and oracle fallback behavior. Route any numerical-policy decision through the physics owner.
5. Measure physics with graphics active on the M1 floor after thermal soak. Record tick-cost distributions with their sampling unit: batch-average p95 is not individual-tick p95. Run the frozen fleet workloads and compare actual simulation time to monotonic wall time while unpaused.

The owner's existing budget is ≤500 µs per 240 Hz tick. At exactly that cost, arithmetic gives 120 ms of simulation work per second, before rendering/input/OS overhead; this is not a measured CPU utilization or proof that every tick meets budget. A 4.167 ms physics interval is not permission to consume that entire interval and discard the agreed headroom.

With 12 catch-up steps, `240 / 12 = 20` fps is the scheduling bound under ideal conditions. A 20 fps cap leaves no scheduling margin; it is not an acceptable visual target. Retain a proposed 60 Hz pilot target and test drops explicitly. Do not reduce physics frequency, skip validation, change `time_scale`, enable fast-math or lower precision to make a Mac benchmark pass.

## Plan integration

**DT-02b:** add native ARM64 numerical acceptance coordinated with H9/Gate P. **DT-10/10b:** collect M1 sustained tick and frame evidence together without replacing the physics team's budget. **DT-11:** changes to renderer, render scale or idle caps must preserve replay results and real-time progression; a numerical/core port stays a separate decision.

Reproduction requires a Mac editor/platform adapter from report [10](10-native-ci-qualification.md); the current Linux-only downloader is unsuitable. Execute existing `test_replay_policy.gd`, `test_golden.gd`, relevant handling tests and the fleet benchmark on the frozen candidate. These commands/tests were inspected, not run here. Apple text was read through its official DocC JSON when its HTML required JavaScript; other linked primary pages were opened directly on 2026-10-07.
